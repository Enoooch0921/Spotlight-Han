import SwiftUI
import AppKit
import HanSearchCore

struct ResultRow: View {
    let item: SearchItem
    let query: String
    private struct PreviewKey: Equatable { let id: String; let query: String; let enabled: Bool }
    @State private var loadedKey: PreviewKey?
    @State private var preview: DocumentPreview?
    private var previewKey: PreviewKey { PreviewKey(id: item.id, query: query, enabled: item.excerpt.isEmpty && item.source == "文件・系統索引") }
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
                    HighlightedText(text: item.excerpt, query: query).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                } else if previewKey.enabled {
                    if loadedKey == previewKey, case let .match(snippet) = preview {
                        HighlightedText(text: snippet, query: query).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    } else {
                        Text(L.text(previewStatus)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }.padding(.vertical, 5)
            .task(id: previewKey) {
                let key = previewKey
                guard key.enabled else { return }
                let value = await DocumentPreviewStore.shared.preview(url: item.url, query: query)
                guard !Task.isCancelled else { return }
                preview = value; loadedKey = key
            }
    }
    private var previewStatus: String {
        guard loadedKey == previewKey, let preview else { return "正在準備命中段落…" }
        switch preview {
        case .noLiteralMatch: return "系統索引命中；未找到可凸顯的內文片段"
        case .unavailable(let reason): return L.format("無法取得內文摘要：%@", L.text(reason.title))
        case .limited: return "已達摘要讀取上限；可開啟文件查看"
        case .cancelled: return "內文摘要已取消"
        case .match: return ""
        }
    }
}
