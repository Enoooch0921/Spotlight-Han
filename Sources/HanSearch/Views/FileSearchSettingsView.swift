import SwiftUI
import HanSearchCore

struct FileSearchSettingsView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Form {
            Section(L.text("快速檔名搜尋")) {
                TimelineView(.periodic(from: Date(), by: 30)) { context in SourceHealthView(health: store.sourceHealth[.names], now: context.date) }
                Text(L.text(store.catalogStatus)).font(.caption)
                if store.unavailableFolderCount > 0 {
                    Label(L.format("有 %@ 個資料夾尚無法恢復存取；已保留原有選擇，請重新選擇相同資料夾。", String(store.unavailableFolderCount)), systemImage: "folder.badge.questionmark").font(.caption).foregroundStyle(.orange)
                }
                ForEach(store.catalogRoots, id: \.path) { root in
                    HStack {
                        Text(root.path).font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(L.text("移除")) { store.removeRoot(root) }.disabled(store.catalogRefreshing)
                    }
                }
                HStack {
                    Button(L.text("選擇搜尋資料夾…")) { store.chooseCatalogFolder() }.disabled(store.catalogRefreshing)
                    Button(L.text("更新檔名清單")) { store.refreshCatalog() }.disabled(store.catalogRefreshing || store.indexing || store.catalogRoots.isEmpty)
                    Button(L.text("忘記資料夾")) { store.forgetFolders() }.disabled(store.catalogRefreshing || store.indexing || store.catalogRoots.isEmpty && store.unavailableFolderCount == 0)
                }
                Text(L.text("開發測試版在重新編譯或重新簽章後，macOS 仍可能要求重新授權；正式發行需要固定的開發者簽章。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.text("Han 文件全文索引")) {
                DocumentIndexSettingsView(store: store)
            }
        }.formStyle(.grouped)
    }
}
