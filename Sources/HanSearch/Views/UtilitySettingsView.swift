import SwiftUI
import HanSearchCore

struct UtilitySettingsView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Form {
            Section(L.text("單位與溫度換算")) {
                Picker(L.text("未寫明溫標時"), selection: $store.temperaturePreference) {
                    ForEach(TemperaturePreference.allCases, id: \.rawValue) { preference in Text(L.text(preference.title)).tag(preference) }
                }
                Text(L.format("目前按 %@ 解讀「37度」；明寫攝氏或華氏時，以輸入為準。", store.temperaturePreference.resolved().symbol))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L.text("例如：3公斤換成磅、5公里多少公尺、32°F=°C。溫度可只輸入37攝氏度或37度，自動顯示另一種溫標。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.text("翻譯與貨幣換算")) {
                if #available(macOS 15.0, *) { TranslationLanguageSettingsView(store: store) }
                Toggle(L.text("顯示查詢翻譯"), isOn: $store.translationEnabled)
                Text(L.text("預設換算目標（至少選一種，可多選）")).font(.caption)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(CurrencyQuery.supportedCodes, id: \.self) { code in
                        Toggle((store.interfaceLanguage.locale.localizedString(forCurrencyCode: code) ?? code) + " " + code, isOn: Binding(get: { store.currencyTargets.contains(code) }, set: { store.setCurrencyTarget(code, enabled: $0) }))
                            .toggleStyle(.checkbox).font(.caption)
                            .disabled(store.currencyTargets.count == 1 && store.currencyTargets.contains(code))
                    }
                }
                Link("Rates by ExchangeRate-API", destination: URL(string: "https://www.exchangerate-api.com")!)
                Text(L.text("只下載公開的 USD 匯率表並在本機換算，金額與搜尋文字不會傳送。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.text("行程、提醒與鬧鐘指令")) {
                EventCalendarPicker(store: store, selection: $store.defaultEventCalendarID, label: "Han 預設行事曆")
                Text(L.text("新行程會先選這個行事曆；確認預覽時仍可更改。此設定只影響 Han。")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L.text("連接系統時鐘")) { store.beginClockSetup() }
                    Button(L.text("檢查連接")) { store.connect(.alarms) }
                    Button(L.text("開啟時鐘")) { SystemClockService.openClock() }
                }
            }
            Section(L.text("剪貼板")) {
                Toggle(L.text("記錄剪貼板文字"), isOn: $store.clipboardEnabled)
                Text(L.text("預設關閉。啟用後只在記憶體保留最近 50 筆、每筆最多 2,000 字；略過標示為隱藏／暫存的內容及常見密碼管理器。其他 App 未標示的敏感文字仍可能被記錄。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L.text("清除記錄")) { store.clearClipboard() }
            }
        }.formStyle(.grouped)
    }
}
