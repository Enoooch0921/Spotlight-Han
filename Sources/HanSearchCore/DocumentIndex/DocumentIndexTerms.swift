import Foundation

/// Unicode substring candidates, including one/two-character Chinese queries.
/// Exact original-text matching after FTS rejects gram intersections and model false positives.
enum DocumentIndexTerms {
    static func folded(_ text: String) -> String {
        ChineseSearch.normalized(text).replacingOccurrences(of: #"(?<=[a-z])[ _.-]+(?=[0-9])|(?<=[0-9])[ _.-]+(?=[a-z])"#, with: "", options: .regularExpression)
    }
    static func grams(_ text: String, widths: ClosedRange<Int>, cancellation: ProcessCancellation? = nil) -> Set<String> {
        let scalars = Array(text.unicodeScalars)
        let encoded = scalars.map { scalar -> String in
            let value = String(scalar.value, radix: 16)
            return String(repeating: "0", count: 6-value.count) + value
        }
        var result = Set<String>()
        for width in widths where scalars.count >= width {
            for start in 0...(scalars.count-width) {
                if start % 4096 == 0, cancellation?.isCancelled == true { return [] }
                let slice = scalars[start..<(start+width)]
                guard !slice.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) else { continue }
                result.insert("g" + encoded[start..<(start+width)].joined())
            }
        }
        return result
    }
    static func tokens(name: String, body: String, cancellation: ProcessCancellation? = nil) -> String {
        // Never connect filenames, cell lines or separate paragraphs into false phrases.
        grams(folded(name + "\n" + body), widths: 1...3, cancellation: cancellation).sorted().joined(separator: " ")
    }
    static func expression(_ query: String) -> String? {
        let terms = ChineseSearch.terms(folded(query))
        guard !terms.isEmpty else { return nil }
        var tokens = Set<String>()
        for term in terms {
            let width = min(3, term.unicodeScalars.count)
            guard width > 0 else { continue }
            tokens.formUnion(grams(term, widths: width...width))
        }
        return tokens.isEmpty ? nil : tokens.sorted().map { "\"" + $0 + "\"" }.joined(separator: " AND ")
    }
}
