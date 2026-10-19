import Foundation

/// Preserve complete alphanumeric identifiers rather than treating digits as tones.
public enum ModelSearch {
    public static func key(_ query: String) -> String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 40, value.range(of: #"^[A-Za-z]+[ _.-]*[0-9]+(?:[_\.-]*[A-Za-z0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        return value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
    public struct Query: @unchecked Sendable {
        private let expression: NSRegularExpression?
        public var isIdentifier: Bool { expression != nil }
        public init(_ query: String) {
            guard let key = ModelSearch.key(query) else { expression = nil; return }
            var pattern = "(?<![A-Za-z0-9])", previous: Character?
            for character in key {
                if let previous, previous.isNumber != character.isNumber { pattern += "[ _.-]*" }
                pattern += NSRegularExpression.escapedPattern(for: String(character)); previous = character
            }
            pattern += "(?![A-Za-z0-9])"
            expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
        public func matches(_ text: String) -> Bool {
            expression?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        public func ranges(in text: String, firstOnly: Bool = false) -> [NSRange]? {
            guard let expression else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            if firstOnly { return expression.firstMatch(in: text, range: range).map { [$0.range] } ?? [] }
            return expression.matches(in: text, range: range).map(\.range)
        }
    }
    public static func ranges(in text: String, query: String, firstOnly: Bool = false) -> [NSRange]? { Query(query).ranges(in: text, firstOnly: firstOnly) }
    public static func matches(_ text: String, query: String) -> Bool {
        let matcher = Query(query)
        return matcher.isIdentifier ? matcher.matches(text) : ChineseSearch.matches(text, query: query)
    }
}
