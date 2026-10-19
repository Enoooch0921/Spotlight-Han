import Foundation

public enum SearchMode: String, CaseIterable, Sendable {
    case all = "全部", apps = "App", names = "檔名", videos = "影片", contents = "文件內容"
    case notes = "備忘錄", contacts = "聯絡人", calendar = "行事曆", mail = "郵件", shortcuts = "動作", clipboard = "剪貼板"
    case reminders = "提醒事項", alarms = "鬧鐘"
}

public enum ChineseSearch {
    public static func simplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }

    public static func traditional(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    public static func normalized(_ text: String) -> String {
        if text.utf8.allSatisfy({ $0 < 128 }) { return text.lowercased() }
        return simplified(text.precomposedStringWithCompatibilityMapping).lowercased()
    }

    public static func variants(_ text: String) -> [String] {
        let candidates = [text, simplified(text), traditional(text), traditional(simplified(text))]
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    public static func terms(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    public static func matches(_ text: String, query: String) -> Bool {
        let needle = terms(normalized(query))
        let haystack = normalized(text)
        return !needle.isEmpty && needle.allSatisfy { haystack.contains($0) }
    }

    // Values are data in Spotlight's query grammar, never shell commands.
    public static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
    }

    public static func predicate(_ text: String, mode: SearchMode) -> String {
        let fields: [String]
        switch mode {
        case .contents: fields = ["kMDItemTextContent"]
        case .apps, .names, .videos: fields = ["kMDItemDisplayName", "kMDItemFSName"]
        default: fields = ["kMDItemDisplayName", "kMDItemFSName", "kMDItemTextContent"]
        }
        let clauses = terms(text).map { term in
            "(" + variants(term).flatMap { variant in
                fields.map { "\($0) == \"*\(escape(variant))*\"cd" }
            }.joined(separator: " || ") + ")"
        }
        guard !clauses.isEmpty else { return "kMDItemFSName == \"\"" }
        var predicate = clauses.joined(separator: " && ")
        if mode == .apps {
            predicate = "(\(predicate)) && kMDItemContentTypeTree == \"com.apple.application-bundle\""
        }
        return predicate
    }
}
