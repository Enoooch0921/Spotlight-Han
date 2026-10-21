import SwiftUI
import HanSearchCore

/// Advanced controls are separate from the everyday overview and folder list.
struct DocumentIndexSettingsView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Form {
            Section(L.text("搜尋整合")) {
                Toggle(L.text("「全部」搜尋 Han 文件內文索引"), isOn: $store.fullTextInAll)
                Toggle(L.text("額外使用 Spotlight 補充全機文件結果"), isOn: $store.spotlightSupplement)
                Text(L.text("Spotlight 補充受系統索引與權限限制；不會擴大 Han 的資料夾索引範圍。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.text("儲存空間")) {
                LabeledContent(L.text("索引占用"), value: ByteCountFormatter.string(fromByteCount: store.indexSnapshot.bytes, countStyle: .file))
                Picker(L.text("索引容量上限"), selection: $store.indexStorageMB) {
                    ForEach([100, 500, 1000, 2000], id: \.self) { size in Text(size >= 1000 ? "\(size/1000) GB" : "\(size) MB").tag(size) }
                }.disabled(store.indexing)
                DisclosureGroup(L.text("索引位置與讀取限制")) {
                    Text(store.documentIndexURL.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(L.text("容量包含文字、頁碼、搜尋索引及暫存日誌；預設 500 MB。實際大小取決於文字量，不按原始照片或 PDF 檔案大小等量複製。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L.text("開啟 OCR 時圖片與 PDF 單檔上限 100 MB，PDF 最多 2,000 頁；其他文件單檔 20 MB。單頁辨識逾時或讀取失敗會列出原因，保留已完成片段。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !store.documentIssues.isEmpty || store.documentIndexCapped {
                Section(L.text("讀取狀況")) {
                    if store.documentIndexCapped {
                        Text(L.text("空間或掃描範圍達限，尚有文件未收錄；請調整範圍或容量後更新索引。")).font(.caption).foregroundStyle(.orange)
                    }
                    DocumentReadDetailsView(issues: store.documentIssues, capped: false, totalIssues: store.indexSnapshot.unfinished)
                }
            }
            Section(L.text("維護與清除")) {
                HStack {
                    Button(L.text("在 Finder 顯示索引")) { store.revealDocumentIndex() }
                    Button(L.text("清除並重建索引")) { store.clearAndRebuildDocumentIndex() }.disabled(store.indexing || store.documentIndexRoots.isEmpty)
                }
                Button(L.text("移除所有文件範圍並清除索引"), role: .destructive) { store.clearDocumentScopes() }
                    .disabled(store.indexing || store.documentRoots.isEmpty && store.unavailableDocumentRoots.isEmpty)
                Button(L.text("忘記所有資料夾與搜尋索引"), role: .destructive) { store.forgetFolders() }
                    .disabled(store.catalogRefreshing || store.indexing)
                DisclosureGroup(L.text("資料夾授權說明")) {
                    Text(L.text("開發測試版在重新編譯或重新簽章後，macOS 仍可能要求重新授權；正式發行需要固定的開發者簽章。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
}
