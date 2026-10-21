import SwiftUI
import AppKit
import HanSearchCore

struct ResultRow: View {
    let item: SearchItem
    let query: String
    var preview: DocumentPreview? = nil
    @State private var creationDate: Date?
    @State private var datedPath: String?
    private var needsPreview: Bool { item.excerpt.isEmpty && item.source == "文件・系統索引" }
    private var matchingQuery: String { item.supplement?.query ?? query }
    private var sourceLabel: String {
        if needsPreview, case .match = preview { return "文件・內文命中" }
        if needsPreview, ModelSearch.matches(item.name, query: query) { return "文件・檔名命中" }
        return item.source
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HighlightedText(text: item.name, query: matchingQuery).font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text(L.text(sourceLabel)).font(.caption2).foregroundStyle(.secondary)
                }
                if let match = item.supplement { SearchSupplementLabel(match: match) }
                if !item.matchPages.isEmpty {
                    Text(L.format("命中第 %@ 頁", item.matchPages.map(String.init).joined(separator: "、")) + (item.isOCR ? " · " + L.text("OCR 辨識") : ""))
                        .font(.caption2).foregroundStyle(.secondary)
                } else if item.isOCR {
                    Text(L.text("OCR 辨識")).font(.caption2).foregroundStyle(.secondary)
                }
                Text(item.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if !item.isApplication, datedPath == item.id {
                    Text(creationDate.map { L.format("建立日期：%@", $0.formatted(Date.FormatStyle(date: .numeric, time: .shortened).locale(L.language.locale))) } ?? L.text("建立日期無法取得"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !item.excerpt.isEmpty {
                    HighlightedText(text: item.excerpt, query: matchingQuery).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                } else if needsPreview {
                    if case let .match(snippet) = preview {
                        HighlightedText(text: snippet, query: query).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    } else {
                        Text(L.text(previewStatus)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }.padding(.vertical, 5)
            .task(id: item.id) {
                guard !item.isApplication else { return }
                let value = await FileCreationDateStore.shared.date(for: item.url)
                guard !Task.isCancelled else { return }
                creationDate = value
                datedPath = item.id
            }
    }
    private var previewStatus: String {
        guard let preview else { return "正在準備命中段落…" }
        switch preview {
        case .noLiteralMatch: return "系統索引命中；未找到可凸顯的內文片段"
        case .unavailable(let reason): return L.format("無法取得內文摘要：%@", L.text(reason.title))
        case .limited: return "已達摘要讀取上限；可開啟文件查看"
        case .cancelled: return "內文摘要已取消"
        case .match: return ""
        }
    }
}
