import SwiftUI
import HanSearchCore

struct SearchPreferencesView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Form {
            Section(L.text("快捷鍵")) {
                LabeledContent(L.text("喚出搜尋"), value: store.hotkeyNotice)
                HStack {
                    ShortcutRecorder(title: L.format("自訂：%@", store.hotkeyNotice)) { store.changeHotkey?($0) }.frame(width: 230, height: 26)
                    Button(L.text("使用 ⌘Space")) { store.changeHotkey?(.commandSpace) }
                    Button(L.text("恢復預設")) { store.changeHotkey?(.standard) }
                }
                if !store.hotkeyError.isEmpty { Label(L.text(store.hotkeyError), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                Button(L.text("開啟 Spotlight 快捷鍵開關")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Spotlight")!)
                }
            }
            Section(L.text("搜尋習慣")) { SearchHabitSettingsView(habits: store.habits) }
            Section(L.text("拼音、注音與搜尋縮寫")) { Text(L.text("右鍵點搜尋結果，即可自訂搜尋縮寫。拼音、注音與 App 首字母的用法請見使用說明。" )).font(.callout).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
}
