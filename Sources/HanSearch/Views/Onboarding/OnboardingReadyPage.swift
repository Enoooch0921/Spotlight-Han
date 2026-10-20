import SwiftUI
import HanSearchCore

struct OnboardingReadyPage: View {
    @ObservedObject var store: SearchStore
    let settings: (SettingsPage) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                OnboardingKey(text: store.hotkeyNotice)
                Text(L.text("任何時候，按下它就能叫出 Han。"))
                    .font(.title3.weight(.medium))
            }.padding(.vertical, 8)
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    summary("預設搜尋頁", value: L.text(store.defaultSearchMode == .apps ? "應用程式" : store.defaultSearchMode.rawValue))
                    Divider()
                    summary("檔名搜尋範圍", value: store.catalogRoots.isEmpty ? L.text("尚未選擇，可稍後設定") : L.format("已選 %@ 個資料夾", String(store.catalogRoots.count)))
                    if !store.catalogRoots.isEmpty { SourceHealthView(health: store.sourceHealth[.names]) }
                    Divider()
                    summary("文件全文範圍", value: store.documentRoots.isEmpty ? L.text("尚未選擇，可稍後設定") : L.format("已選 %@ 個資料夾", String(store.documentRoots.count)))
                    if !store.documentRoots.isEmpty { SourceHealthView(health: store.sourceHealth[.contents]) }
                }.padding(10)
            }
            HStack(alignment: .top, spacing: 28) {
                OnboardingFeatureLine(title: "先輸入，再按 Return", detail: "方向鍵選取結果，Return 開啟；Escape 收起。", symbol: "return")
                OnboardingFeatureLine(title: store.habits.enabled ? "選擇會慢慢被記住" : "搜尋習慣由你決定", detail: store.habits.enabled ? "成功開啟的常用結果會逐漸優先，學習紀錄只留在本機。" : "目前已關閉搜尋習慣學習，可在「搜尋與快捷鍵」更改。", symbol: "clock.arrow.circlepath")
            }
            OnboardingNote(text: "還沒設定的項目不影響 App、計算與系統設定搜尋。之後可從「更新與關於」重看引導。")
            Button(L.text("檢查資料來源與更新狀態…")) { settings(.sources) }
        }
    }
    private func summary(_ title: String, value: String) -> some View {
        HStack { Text(L.text(title)).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.callout)
    }
}
