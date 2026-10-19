import Foundation
import Combine
import HanSearchCore

@MainActor final class SearchAliasStore: ObservableObject {
    @Published private(set) var values: [String: [String]]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.dictionary(forKey: "searchAliases.v1") as? [String: [String]] ?? [:]
    }
    func aliases(for identity: String) -> [String] { values[identity] ?? [] }
    static func parse(_ text: String) -> [String]? {
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ",，、\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard parts.count <= 8, parts.allSatisfy({ $0.count <= 32 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else { return nil }
        var seen = Set<String>()
        return parts.filter { seen.insert(ChineseSearch.normalized($0)).inserted }
    }
    @discardableResult func set(_ aliases: [String], for identity: String) -> Bool {
        guard !identity.isEmpty, let valid = Self.parse(aliases.joined(separator: ",")), values[identity] != nil || values.count < 2000 || valid.isEmpty else { return false }
        if valid.isEmpty { values.removeValue(forKey: identity) } else { values[identity] = valid }
        defaults.set(values, forKey: "searchAliases.v1"); return true
    }
    func matchingTargets(_ query: String) -> Set<String> {
        Set(values.compactMap { ApplicationAliases.matches(query, aliases: $0.value.map(ChineseSearch.normalized)) ? $0.key : nil })
    }
}
