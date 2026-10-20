import SwiftUI
import HanSearchCore

struct OnboardingShortcutPage: View {
    @ObservedObject var store: SearchStore
    let settings: (SettingsPage) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                OnboardingKey(text: store.hotkeyNotice)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.text("按一次開啟，再按一次收起。")).font(.headline)
                    Text(L.text("切換到其他 App 後，也用同一組快捷鍵叫出 Han。"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(L.text("喚出搜尋")).font(.headline)
                        Spacer()
                        Button(L.text("設定快捷鍵…")) { settings(.search) }
                    }
                    Text(L.text("可自訂組合，也可使用 ⌘Space。若原 Spotlight 仍占用，設定會提示並提供系統設定入口。"))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !store.hotkeyError.isEmpty {
                        Label(L.text(store.hotkeyError), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(8)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(L.text("再次開啟搜尋")).font(.headline)
                Picker(L.text("開啟時的行為"), selection: $store.reopenBehavior) {
                    ForEach(SearchReopenBehavior.allCases, id: \.rawValue) { value in Text(L.text(value.title)).tag(value) }
                }
                if store.reopenBehavior == .timed { SearchRetentionEditor(store: store) }
                Picker(L.text("預設搜尋頁"), selection: $store.defaultSearchMode) {
                    ForEach(SearchMode.allCases, id: \.rawValue) { value in Text(L.text(value == .apps ? "應用程式" : value.rawValue)).tag(value) }
                }
            }
            OnboardingNote(text: "預設保留 3 分鐘。從收起開始計時，只在下次開啟時判斷，不會打斷正在輸入的內容。")
        }
    }
}
