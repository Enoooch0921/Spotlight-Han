import Foundation

/// A verified alternative query, never a score boost or a change to stored text.
public struct SearchSupplement: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case zhuyinKeyboard, taiwanVocabulary }
    public let kind: Kind
    public let query: String
    public init(kind: Kind, query: String) { self.kind = kind; self.query = query }
    public var displayQuery: String { kind == .taiwanVocabulary ? ChineseSearch.traditional(query) : query }
}

public enum TaiwanVocabulary {
    // Deliberately small: no broad words such as 文件/檔案, 視頻/影片 or ambiguous AI synonyms.
    // Longest phrases win, so 打印機 never becomes 列印機 via the shorter 打印 rule.
    private static let groups = [
        ["印表機", "打印機"], ["隨身碟", "U盤"], ["滑鼠", "鼠標"],
        ["列印", "打印"], ["軟體", "軟件"], ["硬體", "硬件"]
    ].map { $0.map(ChineseSearch.normalized) }

    /// At most seven alternatives plus the original; only complete curated phrases are replaced.
    public static func alternatives(for query: String) -> [SearchSupplement] {
        let text = ChineseSearch.normalized(String(query.prefix(200)))
        guard !text.isEmpty else { return [] }
        var variants = [""], cursor = text.startIndex, changed = false
        while cursor < text.endIndex {
            let match = groups.flatMap { group in group.map { ($0, group) } }
                .filter { phrase, _ in
                    guard text[cursor...].hasPrefix(phrase) else { return false }
                    if phrase.first?.isASCII == true, cursor > text.startIndex {
                        let previous = text[text.index(before: cursor)]
                        if previous.isASCII && (previous.isLetter || previous.isNumber) { return false }
                    }
                    return true
                }.max { $0.0.count < $1.0.count }
            if let (phrase, group) = match {
                // Keep the original branch first, even when the cap is reached.
                variants = Array((variants.map { $0 + phrase } + variants.flatMap { prefix in
                    group.filter { $0 != phrase }.map { prefix + $0 }
                }).prefix(8))
                cursor = text.index(cursor, offsetBy: phrase.count); changed = true
            } else {
                variants = variants.map { $0 + String(text[cursor]) }
                cursor = text.index(after: cursor)
            }
        }
        guard changed else { return [] }
        var seen: Set<String> = [text]
        return variants.filter { seen.insert($0).inserted }.map { SearchSupplement(kind: .taiwanVocabulary, query: $0) }
    }
}

/// Standard (大千) Zhuyin physical keys only. No global keyboard monitoring or IME changes.
public enum ZhuyinKeyboard {
    private static let symbols = Array("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
    private static let keys = Array("1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-")
    private static let mapping = Dictionary(uniqueKeysWithValues: zip(keys, symbols))
    private static let consonants = Set("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
    public struct Query: Sendable {
        let symbols: String
        let initialsOnly: Bool
        public init?(_ raw: String) {
            let raw = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.count >= 3, raw.count <= 80, raw.allSatisfy({ $0.isASCII }) else { return nil }
            var syllables: [String] = [], current = "", tones = 0
            for key in raw {
                if "3467 ".contains(key) {
                    guard !current.isEmpty else { return nil }
                    syllables.append(current); current = ""; tones += 1
                } else if let symbol = mapping[key] { current.append(symbol) }
                else { return nil }
            }
            if !current.isEmpty { syllables.append(current) }
            let joined = syllables.joined()
            if tones == 0, joined.count >= 3, joined.allSatisfy({ consonants.contains($0) }) {
                symbols = joined; initialsOnly = true; return
            }
            guard syllables.count >= 2, syllables.allSatisfy({ value in
                value.range(of: #"^[ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ]?[ㄧㄨㄩ]?[ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ]?$"#, options: .regularExpression) != nil
                    && (!value.allSatisfy { consonants.contains($0) } || value.count == 1 && "ㄓㄔㄕㄖㄗㄘㄙ".contains(value))
            }) else { return nil }
            symbols = joined; initialsOnly = false
        }
        public func matches(_ title: PhoneticSearch) -> Bool {
            initialsOnly ? title.zhuyinInitials == symbols : title.zhuyin == symbols
        }
        public var supplement: SearchSupplement { SearchSupplement(kind: .zhuyinKeyboard, query: symbols) }
    }
}
