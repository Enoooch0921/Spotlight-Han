import SwiftUI
import HanSearchCore

struct AboutSettingsView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Form {
            Section(L.text("軟體更新")) { AppUpdateSettingsView(updater: store.appUpdater) }
            Section(L.text("關於")) {
                HStack {
                    Link(L.text("GitHub 專案與原始碼"), destination: URL(string: "https://github.com/Enoooch0921/Spotlight-Han")!)
                    Link(L.text("回報問題"), destination: URL(string: "https://github.com/Enoooch0921/Spotlight-Han/issues")!)
                }
                Text(L.format("Spotlight Han %@ · 繁簡中文搜尋", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"))
            }
        }.formStyle(.grouped)
    }
}
