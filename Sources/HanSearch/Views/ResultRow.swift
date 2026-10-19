import SwiftUI
import AppKit
import HanSearchCore

struct ResultRow: View {
    let item: SearchItem
    let query: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HighlightedText(text: item.name, query: query).font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text(L.text(item.source)).font(.caption2).foregroundStyle(.secondary)
                }
                Text(item.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if !item.excerpt.isEmpty {
                    HighlightedText(text: item.excerpt, query: query).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }.padding(.vertical, 5)
    }
}
