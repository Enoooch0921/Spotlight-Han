import Foundation

/// Precomputed title keys. Body text is deliberately not transliterated.
public struct PhoneticSearch: Codable, Hashable, Sendable {
    public let pinyin: String
    public let initials: String
    public let zhuyin: String
    public let zhuyinInitials: String
    public init(_ title: String) {
        let title = String(title.prefix(240))
        guard title.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) || (0x20000...0x3134f).contains($0.value) }) else {
            pinyin = ""; initials = ""; zhuyin = ""; zhuyinInitials = ""; return
        }
        let latin = title.applyingTransform(StringTransform("Han-Latin"), reverse: false) ?? title
        let plain = latin.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let syllables = plain.split { !$0.isLetter && !$0.isNumber }
        pinyin = syllables.joined(); initials = String(syllables.compactMap(\.first))
        let symbols = latin.applyingTransform(StringTransform("Latin-Bopomofo"), reverse: false) ?? ""
        zhuyin = Self.symbolKey(symbols)
        zhuyinInitials = String(symbols.split(whereSeparator: \.isWhitespace).compactMap { $0.unicodeScalars.first(where: Self.isSymbol).map(Character.init) })
    }
    private static func isSymbol(_ scalar: Unicode.Scalar) -> Bool {
        (0x3105...0x312f).contains(scalar.value) || (0x31a0...0x31bf).contains(scalar.value)
    }
    private static func symbolKey(_ text: String) -> String { String(String.UnicodeScalarView(text.unicodeScalars.filter(isSymbol))) }
    public struct Query: Sendable {
        fileprivate let key: String
        fileprivate let symbols: Bool
        public init(_ query: String) {
            symbols = query.unicodeScalars.contains(where: PhoneticSearch.isSymbol)
            if symbols {
                let valid = query.unicodeScalars.allSatisfy { PhoneticSearch.isSymbol($0) || CharacterSet.whitespaces.contains($0) || "ˉˊˇˋ˙12345".unicodeScalars.contains($0) }
                key = valid ? PhoneticSearch.symbolKey(query) : ""
            } else {
                let plain = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                    .replacingOccurrences(of: "([ln])(?:v|u:)", with: "$1u", options: .regularExpression)
                let valid = plain.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.letters.contains($0) || CharacterSet.whitespaces.contains($0) || "12345'".unicodeScalars.contains($0)) }
                let letters = String(plain.filter { $0.isLetter })
                key = valid && letters.count >= 2 ? letters : ""
            }
        }
    }
    public func matches(_ query: String) -> Bool { matches(Query(query)) }
    public func matches(_ query: Query) -> Bool {
        guard !pinyin.isEmpty, !query.key.isEmpty else { return false }
        if query.symbols { return zhuyin.contains(query.key) || query.key.count >= 2 && zhuyinInitials.contains(query.key) }
        return pinyin.contains(query.key) || initials.contains(query.key)
    }
}
