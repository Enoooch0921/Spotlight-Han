import SwiftUI
import HanSearchCore

struct SearchReopenSettingsView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Section(L.text("再次開啟搜尋")) {
            Picker(L.text("開啟時的行為"), selection: $store.reopenBehavior) {
                ForEach(SearchReopenBehavior.allCases, id: \.rawValue) { behavior in Text(L.text(behavior.title)).tag(behavior) }
            }
            if store.reopenBehavior == .timed {
                SearchRetentionEditor(store: store)
            }
            Picker(L.text("預設搜尋頁"), selection: $store.defaultSearchMode) {
                ForEach(SearchMode.allCases, id: \.rawValue) { mode in Text(L.text(mode == .apps ? "應用程式" : mode.rawValue)).tag(mode) }
            }
            Text(L.text(explanation))
                .font(.caption).foregroundStyle(.secondary)
            Text(L.text("上次搜尋僅在本次執行期間保留；重新啟動 App 會開啟空白的預設頁。未確認的新增事項草稿會保留。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var explanation: String {
        switch store.reopenBehavior {
        case .timed: return "從收起時開始計時；逾時後，下次開啟才清空搜尋並回到預設頁。正在輸入時不會被清除。"
        case .reset: return "每次重新開啟時清空搜尋文字，並回到預設頁；正在使用的搜尋不受影響。"
        case .keep: return "重新開啟時接續上次的搜尋文字與頁面；預設頁只用於重新啟動 App。"
        }
    }
}
