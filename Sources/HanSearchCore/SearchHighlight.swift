import Foundation

/// Match using the search engine's folding, and return ranges in the unchanged original text.
public enum SearchHighlight {
    public static func ranges(in text: String, query: String) -> [NSRange] {
        let terms = Array(Set(ChineseSearch.terms(ChineseSearch.normalized(String(query.prefix(200))))))
        guard !text.isEmpty, !terms.isEmpty else { return [] }
        let folded = ChineseSearch.normalized(text)
        let searchable = folded as NSString
        var matches: [NSRange] = []
        for term in terms {
            var start = 0
            while start < searchable.length {
                let match = searchable.range(of: term, options: .literal, range: NSRange(location: start, length: searchable.length - start))
                guard match.location != NSNotFound else { break }
                matches.append(match)
                start = match.location + 1 // Include overlapping matches, e.g. 叔叔 in 叔叔叔.
            }
        }
        guard !matches.isEmpty else { return [] }
        let boundaries = Array(text.indices) + [text.endIndex]
        var foldedOffsets = [0]
        for character in folded { foldedOffsets.append(foldedOffsets.last! + character.utf16.count) }
        let preservesCharacters = boundaries.count == foldedOffsets.count
        var prefixLengths = [0: 0, boundaries.count - 1: searchable.length]
        func length(at index: Int) -> Int {
            if preservesCharacters { return foldedOffsets[index] }
            if let cached = prefixLengths[index] { return cached }
            // Compatibility characters such as ﬃ expand when folded. Never apply folded offsets
            // directly to original text; locate their enclosing original character boundaries.
            let value = ChineseSearch.normalized(String(text[..<boundaries[index]])).utf16.count
            prefixLengths[index] = value
            return value
        }
        func boundary(for offset: Int, roundUp: Bool) -> Int {
            var low = 0, high = boundaries.count - 1
            while low < high {
                let mid = roundUp ? (low + high) / 2 : (low + high + 1) / 2
                if roundUp {
                    if length(at: mid) < offset { low = mid + 1 } else { high = mid }
                } else {
                    if length(at: mid) <= offset { low = mid } else { high = mid - 1 }
                }
            }
            return low
        }
        let original = matches.compactMap { match -> NSRange? in
            let start = boundary(for: match.location, roundUp: false)
            let end = boundary(for: NSMaxRange(match), roundUp: true)
            guard start < end else { return nil }
            return NSRange(boundaries[start]..<boundaries[end], in: text)
        }.sorted { $0.location < $1.location || ($0.location == $1.location && $0.length < $1.length) }
        var merged: [NSRange] = []
        for range in original {
            if let last = merged.last, range.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else { merged.append(range) }
        }
        return merged
    }

    /// Keep the hit visible even when it appears late in a long paragraph or note.
    public static func excerpt(in text: String, query: String, limit: Int = 160) -> String {
        guard limit > 0, !text.isEmpty else { return "" }
        let first = ranges(in: text, query: query).first.flatMap { Range($0, in: text) }
        let hit = first?.lowerBound ?? text.startIndex
        let window = max(limit, min(200, query.count))
        let context = min(35, max(0, window - min(window, first.map { text.distance(from: $0.lowerBound, to: $0.upperBound) } ?? 0)) / 4)
        let before = text.index(hit, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
        let start = text[before..<hit].lastIndex(where: \.isNewline).map { text.index(after: $0) } ?? before
        var end = text.index(start, offsetBy: window, limitedBy: text.endIndex) ?? text.endIndex
        if let newline = text[hit..<end].firstIndex(where: \.isNewline) { end = newline }
        let snippet = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let leading = start > text.startIndex && !text[text.index(before: start)].isNewline
        let trailing = end < text.endIndex && !text[end].isNewline
        return (leading ? "…" : "") + snippet + (trailing ? "…" : "")
    }
}
