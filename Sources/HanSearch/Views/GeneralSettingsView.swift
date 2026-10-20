import SwiftUI
import HanSearchCore

struct GeneralSettingsView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Form {
            Section(L.text("一般")) {
                Picker(L.text("介面語言"), selection: $store.interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                StartupSettingsView(service: store.loginItem)
                Toggle(L.text("柔和過渡動畫"), isOn: $store.motionEnabled)
            }
            SearchReopenSettingsView(store: store)
        }.formStyle(.grouped)
    }
}
