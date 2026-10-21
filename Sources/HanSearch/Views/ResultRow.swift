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
    private var indexOnlyMatch: Bool { needsPreview && preview == .noLiteralMatch }
    private var matchingQuery: String { item.supplement?.query ?? query }
    private var sourceLabel: String {
        if needsPreview, case .match = preview { return "文件・內文命中" }
        if needsPreview, ModelSearch.matches(item.name, query: query) { return "文件・檔名命中" }
        return item.source
    }
    private var filenameMatches: Bool { ModelSearch.matches(item.name, query: matchingQuery) }
    private var contentMatches: Bool {
        let snippet: String
        if !item.excerpt.isEmpty { snippet = item.excerpt }
        else if case let .match(text) = preview { snippet = text }
        else { return false }
        return !SearchHighlight.ranges(in: snippet, query: matchingQuery).isEmpty
    }
    private var informationHeading: String {
        if contentMatches { return filenameMatches ? "檔名與內文符合" : "已確認內文命中" }
        if filenameMatches { return "已確認檔名符合" }
        if needsPreview { return preview == nil ? "正在讀取內文片段" : "內文尚未確認" }
        return "搜尋結果資訊"
    }
    private var informationDetails: String {
        if contentMatches { return L.text("結果片段已標示符合搜尋詞的文字。") }
        if needsPreview {
            if preview == .noLiteralMatch {
                return L.text(filenameMatches ? "檔名符合搜尋詞；尚未找到可凸顯的內文片段。"
                    : "系統索引提供此結果，可能來自檔名、屬性或分詞；Han 尚未確認內文命中。")
            }
            return L.text(previewStatus)
        }
        return L.text(filenameMatches ? "檔名符合搜尋詞，可在下方查看完整位置。" : "可在下方查看結果來源與完整位置。")
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HighlightedText(text: item.name, query: matchingQuery).font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                    ResultSourceHint(source: L.text(sourceLabel), explanation: informationDetails,
                                     heading: L.text(informationHeading), url: item.url,
                                     pages: item.matchPages, isOCR: item.isOCR)
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
                } else if needsPreview && !indexOnlyMatch {
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
