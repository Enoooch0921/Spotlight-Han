import SwiftUI
import HanSearchCore

struct FileIndexOverviewView: View {
    @ObservedObject var store: SearchStore
    let editScopes: () -> Void
    let showDetails: () -> Void
    private var hasScopes: Bool { !store.catalogRoots.isEmpty || !store.documentIndexRoots.isEmpty }
    var body: some View {
        Form {
            Section(L.text("搜尋狀態")) {
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    IndexOverviewRow(title: "檔名與影片", symbol: "folder", count: store.catalogCount,
                        hasScope: !store.catalogRoots.isEmpty, health: store.sourceHealth[.names], now: context.date)
                }
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    IndexOverviewRow(title: "文件與圖片內容", symbol: "doc.text.magnifyingglass", count: store.indexSnapshot.searchable,
                        hasScope: !store.documentIndexRoots.isEmpty, health: store.sourceHealth[.contents], now: context.date)
                }
                if store.catalogRefreshing { ProgressView(L.text(store.catalogStatus)).controlSize(.small) }
                if store.indexing { OCRFileProgressView(store: store) }
                if store.sourceHealth[.contents]?.phase == .failed { Text(L.text(store.indexNotice)).font(.caption).foregroundStyle(.red) }
                if store.sourceHealth[.names]?.phase == .failed { Text(L.text(store.catalogStatus)).font(.caption).foregroundStyle(.red) }
            }
            if !store.documentIndexRoots.isEmpty && store.ocrEnabled {
                Section(L.text("背景辨識狀態")) {
                    Label(L.text(store.indexPaused ? "已手動暫停文件索引" : store.ocrWorkDecision.title), systemImage: store.indexPaused ? "pause.circle" : "leaf")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(L.format("OCR 已處理 %@ 頁，涵蓋 %@ 份檔案", String(store.indexSnapshot.ocrPages), String(store.indexSnapshot.ocrFiles)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Button(L.text(hasScopes ? "管理搜尋範圍…" : "加入搜尋範圍…"), action: editScopes)
                    Button(L.text("更新搜尋索引")) {
                        if !store.catalogRoots.isEmpty { store.refreshCatalog() }
                        if !store.documentIndexRoots.isEmpty { store.rebuildIndex() }
                    }.disabled(!hasScopes || store.indexing || store.catalogRefreshing)
                    Spacer()
                    if !store.documentIndexRoots.isEmpty {
                        Button(L.text(store.indexPaused ? "繼續文件索引" : "暫停文件索引")) {
                            if store.indexPaused { store.rebuildIndex() } else { store.pauseDocumentIndex() }
                        }.disabled(store.indexPaused && store.indexing)
                    }
                }
                if store.unavailableFolderCount + store.unavailableDocumentRoots.count > 0 {
                    Label(L.text("部分搜尋範圍需要重新授權，請到搜尋範圍重新選擇。"), systemImage: "folder.badge.questionmark")
                        .font(.caption).foregroundStyle(.orange)
                }
                if store.indexSnapshot.unfinished > 0 || store.documentIndexCapped {
                    Button(L.format("查看未完成項目（%@）", String(store.indexSnapshot.unfinished)), action: showDetails)
                }
            }
        }.formStyle(.grouped)
    }
}

private struct IndexOverviewRow: View {
    let title: String
    let symbol: String
    let count: Int
    let hasScope: Bool
    let health: SourceHealth?
    let now: Date
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.text(title)).fontWeight(.medium)
                Text(hasScope ? L.format("已收錄 %@ 筆可搜尋資料", String(count)) : L.text("尚未選擇搜尋範圍"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if hasScope { SourceHealthView(health: health, now: now) }
        }.padding(.vertical, 4)
    }
}

struct OCRFileProgressView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.text(store.indexRecognizing ? "正在辨識圖片文字…" : "正在讀取文件文字…")).font(.caption)
                if !store.indexCurrentFile.isEmpty { Text(store.indexCurrentFile).font(.caption).lineLimit(1).truncationMode(.middle) }
                if store.indexTotalPages > 0 {
                    Text(L.format("目前第 %@／%@ 頁", String(store.indexCurrentPage), String(store.indexTotalPages))).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
