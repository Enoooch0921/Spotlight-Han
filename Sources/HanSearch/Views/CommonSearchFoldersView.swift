import SwiftUI
import HanSearchCore

struct CommonSearchFoldersView: View {
    @ObservedObject var store: SearchStore
    @State private var selected = Set(CommonSearchFolder.allCases)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.text("建議的常用範圍")).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 8) {
                ForEach(CommonSearchFolder.allCases) { folder in
                    Toggle(L.text(folder.title), isOn: Binding(get: { selected.contains(folder) }, set: { if $0 { selected.insert(folder) } else { selected.remove(folder) } }))
                        .toggleStyle(.checkbox)
                }
            }
            Text(L.text("預選不代表已授權。確認資料夾後才建立檔名、文件與 OCR 索引；影片和音樂不辨識聲音或畫面。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L.text("確認並授權常用資料夾…")) { store.chooseCommonSearchFolders(selected) }.disabled(selected.isEmpty || store.indexing || store.catalogRefreshing)
                Button(L.text("加入 iCloud Drive…")) { store.chooseFolder() }.disabled(store.indexing)
            }
            Text(L.text("iCloud 請在選擇視窗側欄選取；僅在雲端的檔案不會自動下載。照片圖庫套件不掃描，請選擇匯出的圖片資料夾。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
