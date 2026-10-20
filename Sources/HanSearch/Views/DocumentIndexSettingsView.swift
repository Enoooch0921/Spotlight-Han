import SwiftUI
import HanSearchCore

struct DocumentIndexSettingsView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L.text("「全部」搜尋 Han 文件內文索引"), isOn: $store.fullTextInAll)
            Text(L.text("Han 自行讀取已選資料夾的 Word、文字 PDF、PowerPoint、Excel 與文字文件，索引保存在本機，重新開啟後可接續搜尋，不依賴 Spotlight。"))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(L.text("額外使用 Spotlight 補充全機文件結果"), isOn: $store.spotlightSupplement)
            Text(L.text("預設關閉。補充結果受 macOS 系統索引與權限限制；不會把未選的文件加入 Han 索引。"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(store.documentRoots, id: \.path) { root in
                HStack {
                    Text(root.path).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L.text("移除並清除索引")) { store.removeDocumentRoot(root) }.disabled(store.indexing)
                }
            }
            ForEach(store.unavailableDocumentRoots, id: \.path) { root in
                HStack {
                    Text(L.format("無法恢復授權：%@", root.path)).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(L.text("移除並清除索引")) { store.removeDocumentRoot(root) }.disabled(store.indexing)
                }
            }
            if store.documentIndexRoots.isEmpty { Text(L.text("尚未選擇文件資料夾；Han 不會自動掃描整個使用者資料夾。" )).font(.caption) }
            if !store.documentIndexRoots.isEmpty { SourceHealthView(health: store.sourceHealth[.contents]) }
            if !store.indexNotice.isEmpty { Text(L.text(store.indexNotice)).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Text(L.format("索引占用：%@", ByteCountFormatter.string(fromByteCount: store.indexSnapshot.bytes, countStyle: .file))).font(.caption)
                Spacer()
                Picker(L.text("索引容量上限"), selection: $store.indexStorageMB) {
                    ForEach([100, 500, 1000, 2000], id: \.self) { size in Text(size >= 1000 ? "\(size/1000) GB" : "\(size) MB").tag(size) }
                }.fixedSize().disabled(store.indexing)
            }
            HStack {
                Button(L.text("加入文件資料夾…")) { store.chooseFolder() }.disabled(store.indexing)
                if !store.documentIndexRoots.isEmpty {
                    Button(L.text(store.indexPaused ? "繼續索引" : "更新索引")) { store.rebuildIndex() }.disabled(store.indexing)
                    if store.indexing { Button(L.text("暫停索引")) { store.pauseDocumentIndex() } }
                    Button(L.text("清除並重建索引")) { store.clearAndRebuildDocumentIndex() }.disabled(store.indexing)
                }
            }
            HStack {
                Button(L.text("在 Finder 顯示索引")) { store.revealDocumentIndex() }
                Button(L.text("移除所有文件範圍並清除索引")) { store.clearDocumentScopes() }.disabled(store.indexing)
            }.controlSize(.small)
            if store.documentIndexCapped { Text(L.text("空間或掃描範圍達限，尚有文件未收錄；請調整範圍或容量後更新索引。" )).font(.caption).foregroundStyle(.orange) }
            DocumentReadDetailsView(issues: store.documentIssues, capped: false, totalIssues: store.indexSnapshot.unfinished)
            Text(L.text("索引含文件文字，僅保存在這台 Mac，不上傳，也不複製原始文件。預設略過 Library、快取、隱藏與部分開發資料夾；不跟隨符號連結。單檔 20 MB、可擷取文字 8 MB；首次建立較慢，之後只重新擷取有變動的文件。掃描 PDF 尚無 OCR。"))
                .font(.caption).foregroundStyle(.secondary)
            Text(store.documentIndexURL.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
