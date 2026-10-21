import SwiftUI
import HanSearchCore

struct FileIndexScopesView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Form {
            Section(L.text("加入常用資料夾與 iCloud")) { CommonSearchFoldersView(store: store, compact: true) }
            Section(L.text("檔名與影片")) {
                ForEach(store.catalogRoots, id: \.path) { root in
                    IndexScopeFolderRow(url: root, unavailable: false) { store.removeRoot(root) }.disabled(store.catalogRefreshing)
                }
                ForEach(store.unavailableCatalogRoots, id: \.path) { root in
                    IndexScopeFolderRow(url: root, unavailable: true, remove: nil)
                }
                if store.catalogRoots.isEmpty && store.unavailableCatalogRoots.isEmpty { Text(L.text("尚未選擇搜尋範圍")).foregroundStyle(.secondary) }
                Button(L.text("選擇檔名搜尋範圍…")) { store.chooseCatalogFolder() }.disabled(store.catalogRefreshing)
            }
            Section(L.text("文件與圖片內容")) {
                ForEach(store.documentRoots, id: \.path) { root in
                    IndexScopeFolderRow(url: root, unavailable: false) { store.removeDocumentRoot(root) }.disabled(store.indexing)
                }
                ForEach(store.unavailableDocumentRoots, id: \.path) { root in
                    IndexScopeFolderRow(url: root, unavailable: true) { store.removeDocumentRoot(root) }.disabled(store.indexing)
                }
                if store.documentRoots.isEmpty && store.unavailableDocumentRoots.isEmpty { Text(L.text("尚未選擇搜尋範圍")).foregroundStyle(.secondary) }
                Button(L.text("加入文件資料夾…")) { store.chooseFolder() }.disabled(store.indexing)
            }
            Section {
                Text(L.text("移除搜尋範圍只會清除 Han 的索引，不會刪除原始檔案。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct IndexScopeFolderRow: View {
    let url: URL
    let unavailable: Bool
    let remove: (() -> Void)?
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: unavailable ? "folder.badge.questionmark" : "folder").foregroundStyle(unavailable ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent).fontWeight(.medium)
                Text(unavailable ? L.format("無法恢復授權：%@", url.path) : url.path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.help(url.path)
            Spacer()
            if let remove {
                Button(action: remove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    .help(L.text("移除搜尋範圍")).accessibilityLabel(L.format("移除範圍：%@", url.lastPathComponent))
            }
        }.padding(.vertical, 3)
    }
}
