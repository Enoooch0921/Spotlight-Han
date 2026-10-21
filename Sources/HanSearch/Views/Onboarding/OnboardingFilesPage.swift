import SwiftUI
import HanSearchCore

struct OnboardingFilesPage: View {
    @ObservedObject var store: SearchStore
    let settings: (SettingsPage) -> Void
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisclosureGroup(L.text("先選常用資料夾")) { CommonSearchFoldersView(store: store).padding(.vertical, 8) }
            indexPanel(title: "檔名與影片", detail: "找名稱與路徑，不讀取影片內容。適合先加入下載、文件、影片等常用位置。", symbol: "folder", mode: .names, roots: store.catalogRoots) {
                Button(L.text(store.catalogRoots.isEmpty ? "選擇檔名搜尋範圍…" : "管理檔名範圍…")) {
                    if store.catalogRoots.isEmpty { store.chooseCatalogFolder() } else { settings(.files) }
                }.disabled(store.catalogRefreshing)
            }
            indexPanel(title: "文件全文", detail: "讀取 Word、PDF、PPTX、XLSX、文字及圖片；掃描頁與圖片用 Apple Vision 辨識，結果顯示片段與 PDF 頁碼。", symbol: "doc.text.magnifyingglass", mode: .contents, roots: store.documentRoots) {
                HStack {
                    Button(L.text(store.documentRoots.isEmpty ? "選擇文件範圍…" : "管理文件範圍…")) {
                        if store.documentRoots.isEmpty { store.chooseFolder() } else { settings(.files) }
                    }.disabled(store.indexing && store.documentRoots.isEmpty)
                    if store.documentRoots.isEmpty && !store.catalogRoots.isEmpty {
                        Button(L.text("沿用檔名搜尋範圍")) {
                            do { try store.addDocumentRoots(store.catalogRoots); error = "" }
                            catch { self.error = error.localizedDescription }
                        }.disabled(store.indexing)
                    }
                }
            }
            if !error.isEmpty { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            OnboardingNote(text: "首次索引可能較久；完成後會保存在本機，背景只重新讀取有變動的文件。")
            OnboardingNote(text: "OCR 會增加耗電與溫度，預設僅接電時辨識；使用中降低頻率，閒置後加快。低耗電或溫度升高會等待，可在索引設定暫停或調整。")
            DisclosureGroup(L.text("搜尋範圍與限制")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.text("預設不掃描整台 Mac；只讀取已選且可存取的範圍。檔名與內文結果會合併到「全部」。"))
                    Text(L.text("圖片與掃描 PDF 使用 Apple Vision 背景 OCR，顯示片段與 PDF 頁碼；舊版 PPT／XLS 可轉成 PPTX／XLSX。iCloud 只處理已下載檔案。"))
                    Text(L.text("內文索引預設上限 500 MB，含擷取文字，僅存本機且未額外加密。移除索引不會刪除原始文件。"))
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.callout)
        }
    }
    private func indexPanel<Actions: View>(title: String, detail: String, symbol: String, mode: SearchMode, roots: [URL], @ViewBuilder actions: () -> Actions) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: 30)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L.text(title)).font(.headline)
                        Text(L.text(detail)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !roots.isEmpty {
                    HStack(alignment: .top) {
                        Text(L.format("已選 %@ 個資料夾", String(roots.count))).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        SourceHealthView(health: store.sourceHealth[mode])
                    }
                    if mode == .contents && !store.indexNotice.isEmpty { Text(L.text(store.indexNotice)).font(.caption).foregroundStyle(.secondary) }
                } else if unavailableRoots(for: mode).isEmpty {
                    Text(L.text("尚未選擇，可稍後設定")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(unavailableRoots(for: mode), id: \.path) { root in
                    Label(L.format("無法恢復授權：%@", root.lastPathComponent), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                actions().controlSize(.regular)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func unavailableRoots(for mode: SearchMode) -> [URL] {
        mode == .contents ? store.unavailableDocumentRoots : store.unavailableCatalogRoots
    }
}
