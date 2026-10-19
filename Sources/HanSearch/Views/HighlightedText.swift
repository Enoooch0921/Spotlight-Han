import SwiftUI
import HanSearchCore

struct HighlightedText: View {
    let text: String
    let query: String
    private var attributed: AttributedString {
        var result = AttributedString(text)
        for match in SearchHighlight.ranges(in: text, query: query) {
            guard let source = Range(match, in: text),
                  let start = AttributedString.Index(source.lowerBound, within: result),
                  let end = AttributedString.Index(source.upperBound, within: result) else { continue }
            result[start..<end].backgroundColor = Color.accentColor.opacity(0.22)
            result[start..<end].foregroundColor = Color.primary
            result[start..<end].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }
    var body: some View { Text(attributed) }
}
