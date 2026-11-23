import Foundation

/// Only consume explicit leading phrases. Keep the user's spelling in the remaining query.
public struct FileQueryFilter: Sendable {
    public enum Kind: Hashable, Sendable { case folder, date, type }
    public struct Chip: Sendable {
        public let kind: Kind
        public let phrase: String
    }
    public private(set) var text: String
    public private(set) var chips: [Chip] = []
    public private(set) var folder: CommonSearchFolder?
    public private(set) var extensions: Set<String> = []
    private var folderPrefix: String?
    public private(set) var interval: DateInterval?
    public private(set) var created = false
    public var active: Bool { !chips.isEmpty }
    public var suggestedWeek: String? {
        guard interval == nil else { return nil }
        return ["上週", "上周"].first { text.hasPrefix($0) && text.count > $0.count }
    }

    public init(_ raw: String, now: Date = Date(), calendar: Calendar = .current) {
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var calendar = calendar
        calendar.firstWeekday = 2
        while !text.isEmpty {
            let original = text
            let normalized = ChineseSearch.traditional(original).lowercased()
            func prefix(_ candidates: [String]) -> String? {
                candidates.first { normalized.hasPrefix($0) }
            }
            var length = 0
            var kind: Kind?
            if folder == nil {
                for scope in CommonSearchFolder.allCases {
                    let names = [scope.title + "資料夾", scope.title + "文件夾"]
                    let suffixes = ["裡面的", "裏面的", "裡的", "裏的", "里的", "中的", "的"]
                    if let phrase = prefix(names.flatMap { name in suffixes.map { name + $0 } }) {
                        folder = scope; folderPrefix = scope.url.path + "/"; kind = .folder; length = phrase.count; break
                    }
                }
            }
            if kind == nil && interval == nil {
                let periods: [(String, Calendar.Component, Int)] = [
                    ("上週", .weekOfYear, -1), ("上周", .weekOfYear, -1), ("本週", .weekOfYear, 0), ("本周", .weekOfYear, 0),
                    ("昨天", .day, -1), ("今天", .day, 0), ("上個月", .month, -1), ("上月", .month, -1), ("本月", .month, 0)]
                for (period, component, offset) in periods {
                    if let phrase = prefix(["修改的", "更新的", "建立的", "創建的"].map { period + $0 }),
                       let date = calendar.date(byAdding: component, value: offset, to: now),
                       let range = calendar.dateInterval(of: component, for: date) {
                        interval = range; created = phrase.contains("建立") || phrase.contains("創建")
                        kind = .date; length = phrase.count; break
                    }
                }
            }
            if kind == nil && extensions.isEmpty {
                let types: [(String, Set<String>)] = [("pdf", ["pdf"]), ("word", ["doc","docx"]), ("excel", ["xls","xlsx"]), ("ppt", ["ppt","pptx"]), ("影片", FileCatalog.videoExtensions)]
                // Bare "PDF" and literal filenames such as "PDF報價單.pdf" remain searchable.
                for (name, exts) in types where normalized.hasPrefix(name) {
                    let tail = original.dropFirst(name.count)
                    if ["檔案", "文件", "档案"].contains(String(tail)) {
                        extensions = exts; kind = .type; length = original.count; break
                    }
                    if tail.first?.isWhitespace == true || (tail.isEmpty && !chips.isEmpty) {
                        extensions = exts; kind = .type; length = name.count; break
                    }
                }
            }
            guard let kind else { break }
            chips.append(Chip(kind: kind, phrase: String(original.prefix(length))))
            text = String(original.dropFirst(length)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func removing(_ kind: Kind) -> String {
        let kept = chips.filter { $0.kind != kind }
        if kept.count == 1, kept[0].kind == .type, text.isEmpty {
            let phrase = kept[0].phrase
            return ["檔案", "文件", "档案"].contains(where: phrase.hasSuffix) ? phrase : phrase + "檔案"
        }
        return (kept.map(\.phrase) + [text]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public func accepts(_ url: URL) -> Bool {
        if let folderPrefix, !url.path.hasPrefix(folderPrefix) { return false }
        if !extensions.isEmpty && !extensions.contains(url.pathExtension.lowercased()) { return false }
        if let interval {
            let key: URLResourceKey = created ? .creationDateKey : .contentModificationDateKey
            guard let values = try? url.resourceValues(forKeys: [key]),
                  let date = created ? values.creationDate : values.contentModificationDate,
                  date >= interval.start && date < interval.end else { return false }
        }
        return true
    }
}
