import Foundation

/// Preserve complete alphanumeric identifiers rather than treating digits as tones.
public enum ModelSearch {
    public static func key(_ query: String) -> String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // The former nested quantifiers could backtrack exponentially on an
        // almost-valid identifier, such as a long serial number ending in ':'.
        // Recognize the same ASCII grammar once, in linear time.
        guard value.utf8.count <= 40 else { return nil }
        let bytes = Array(value.utf8)
        func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
        func digit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
        func separator(_ byte: UInt8) -> Bool { byte == 95 || byte == 46 || byte == 45 }
        var index = 0
        while index < bytes.count, letter(bytes[index]) { index += 1 }
        guard index > 0 else { return nil }
        while index < bytes.count, separator(bytes[index]) || bytes[index] == 32 { index += 1 }
        guard index < bytes.count, digit(bytes[index]) else { return nil }
        while index < bytes.count {
            let byte = bytes[index]
            guard letter(byte) || digit(byte) || separator(byte) else { return nil }
            index += 1
        }
        guard let last = bytes.last, letter(last) || digit(last) else { return nil }
        return String(decoding: bytes.filter { letter($0) || digit($0) }.map { (65...90).contains($0) ? $0 + 32 : $0 }, as: UTF8.self)
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
