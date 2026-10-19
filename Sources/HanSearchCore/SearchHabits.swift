import Foundation
import CryptoKit

public enum SearchResultKind: String, Codable, Sendable, CaseIterable {
    case app, file, note, contact, calendar, reminder, mail, shortcut
}

public struct HabitCandidate: Sendable {
    public let id: String
    public let identity: String
    public let title: String
    public let kind: SearchResultKind
    public let aliases: [String]
    public init(id: String, identity: String, title: String, kind: SearchResultKind, aliases: [String] = []) {
        self.id = id; self.identity = identity; self.title = title; self.kind = kind
        self.aliases = aliases
    }
}

/// Stores salted identifiers and counts, never raw queries, paths, titles or note contents.
public struct SearchHabitHistory: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        let query: String
        let target: String
        let kind: SearchResultKind
        var count: Int
        var lastUsed: Date
    }
    public private(set) var entries: [Entry] = []
    private var salt: String
    public init(salt: String = UUID().uuidString) { self.salt = salt }
    public static func queryKey(_ query: String) -> String {
        ChineseSearch.normalized(String(query.prefix(200))).filter { !$0.isWhitespace }
    }
    private func digest(_ value: String) -> String {
        let alphabet = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []; bytes.reserveCapacity(64)
        for value in SHA256.hash(data: Data((salt + "\u{0}" + value).utf8)) {
            bytes.append(alphabet[Int(value >> 4)]); bytes.append(alphabet[Int(value & 15)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    public mutating func record(query: String, identity: String, kind: SearchResultKind, now: Date = Date()) {
        let key = Self.queryKey(query)
        guard !key.isEmpty, !identity.isEmpty else { return }
        prune(now: now)
        let q = digest("q:" + key), t = digest("t:" + identity)
        if let index = entries.firstIndex(where: { $0.query == q && $0.target == t }) {
            entries[index].count = min(10_000, entries[index].count + 1); entries[index].lastUsed = now
        } else { entries.append(Entry(query: q, target: t, kind: kind, count: 1, lastUsed: now)) }
        if entries.count > 2000 { entries = Array(entries.sorted { $0.lastUsed > $1.lastUsed }.prefix(2000)) }
    }
    public mutating func prune(now: Date = Date()) {
        entries.removeAll { now.timeIntervalSince($0.lastUsed) > 365 * 86400 || $0.count <= 0 || $0.count > 10_000 || $0.query.count != 64 || $0.target.count != 64 }
    }
    public func ordered(_ candidates: [HabitCandidate], query: String, now: Date = Date()) -> [String] {
        guard !Self.queryKey(query).isEmpty, !entries.isEmpty else { return candidates.map(\.id) }
        let key = digest("q:" + Self.queryKey(query))
        var queryCounts: [String: Double] = [:], targetCounts: [String: Double] = [:], kinds: [SearchResultKind: Double] = [:]
        for entry in entries where now.timeIntervalSince(entry.lastUsed) <= 365 * 86400 {
            let weight = Double(entry.count) * pow(0.5, max(0, now.timeIntervalSince(entry.lastUsed)) / (90 * 86400))
            if entry.query == key { queryCounts[entry.target, default: 0] += weight }
            targetCounts[entry.target, default: 0] += weight; kinds[entry.kind, default: 0] += weight
        }
        guard !kinds.isEmpty else { return candidates.map(\.id) }
        let total = max(1, kinds.values.reduce(0, +))
        let needle = ChineseSearch.normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        func score(_ item: HabitCandidate) -> Double {
            let name = ChineseSearch.normalized(item.title)
            let compact = ChineseSearch.applicationKey(name), compactNeedle = ChineseSearch.applicationKey(needle)
            let alias = ApplicationAliases.matches(query, aliases: item.aliases.map(ChineseSearch.normalized))
            let relevance: Double = name == needle || (item.kind == .app && compact == compactNeedle) ? 300 : alias ? 260 : name.hasPrefix(needle) || (item.kind == .app && compact.hasPrefix(compactNeedle)) ? 220 : name.contains(needle) ? 140 : 60
            let target = digest("t:" + item.identity)
            let count = queryCounts[target, default: 0]
            // Repeated choices for this query can override title relevance; one accidental
            // opening cannot replace a clear exact title match. General preferences stay small.
            let queryBoost = count >= 1.5 ? 450 + min(150, count * 10) : count * 100
            return relevance + queryBoost + min(20, log2(targetCounts[target, default: 0] + 1) * 3) + 12 * kinds[item.kind, default: 0] / total
        }
        let scored: [(index: Int, id: String, score: Double)] = candidates.enumerated().map { index, item in
            (index: index, id: item.id, score: score(item))
        }
        let sorted = scored.sorted { left, right in
            left.score == right.score ? left.index < right.index : left.score > right.score
        }
        return sorted.map(\.id)
    }
}
