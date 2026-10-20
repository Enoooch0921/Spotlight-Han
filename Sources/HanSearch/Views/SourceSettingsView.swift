import SwiftUI
import HanSearchCore

struct SourceSettingsView: View {
    @ObservedObject var store: SearchStore
    private let sources: [SearchMode] = [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts, .alarms]
    var body: some View {
        Form {
            Section(L.text("系統 App 資料來源")) {
                Toggle(L.text("背景自動更新已連接來源"), isOn: $store.autoRefreshEnabled)
                    .onChange(of: store.autoRefreshEnabled) { _, enabled in if enabled { store.refreshAuthorizedSources() } }
                HStack {
                    Button(L.text("全部重新讀取")) { store.refreshAllConnectedSources() }
                        .disabled(store.refreshableSources.isEmpty || store.setupRunning || !store.connecting.isEmpty || store.authorizationInFlight || store.actionInFlight)
                    Button(L.text("一次設定所有資料來源")) { store.setupAllSources() }.disabled(store.setupRunning || !store.connecting.isEmpty || store.authorizationInFlight || store.actionInFlight)
                    if store.setupRunning { ProgressView().controlSize(.small) }
                    if !store.connecting.isEmpty { Button(L.text("停止連接")) { store.cancelConnections() } }
                }
                if !store.setupStatus.isEmpty { Text(L.text(store.setupStatus)).font(.caption).foregroundStyle(.secondary) }
                ForEach(sources, id: \.self) { source in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(L.text(source.rawValue)).fontWeight(.medium)
                            Spacer()
                            if store.connecting.contains(source) { ProgressView().controlSize(.small) }
                            if store.shouldOfferSourcePrivacy(source) {
                                Button(L.text("開啟隱私權設定")) { store.openSourcePrivacy(source) }
                            }
                            Button(L.text(source == .alarms ? "檢查連接" : (store.personalStatus[source] == nil || store.sourceHealth[source]?.phase == .needsPermission ? "連接" : "重新讀取"))) { store.connect(source) }.disabled(store.connecting.contains(source) || store.setupRunning)
                            if store.personalStatus[source] != nil && !store.connecting.contains(source) {
                                Button(L.text("移除")) { store.disconnect(source) }
                            }
                        }
                        TimelineView(.periodic(from: Date(), by: 30)) { context in SourceHealthView(health: store.sourceHealth[source], now: context.date) }
                        Text(L.text(store.personalStatus[source] ?? scope(source))).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                }
                Text(L.text("只在本機搜尋已授權資料；移除來源不會刪除原始內容。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func scope(_ mode: SearchMode) -> String {
        switch mode {
        case .notes: return "標題與純文字內文，最多 2,000 則；不讀取受密碼保護的備忘錄"
        case .contacts: return "你允許取用的聯絡人姓名、電話與電子郵件"
        case .calendar: return "前後各一年行程，最多 10,000 筆；包含標題、地點與備註"
        case .reminders: return "未完成提醒事項，最多 10,000 筆；亦可依輸入指令新增"
        case .alarms: return "Apple 系統時鐘橋接捷徑；首次加入一次，之後輸入指令即可"
        case .mail: return "系統 Mail 收件匣前 200 封，內文每封前 16,000 字；不是所有信箱"
        case .shortcuts: return "列出捷徑；執行選取的捷徑前會請你確認"
        default: return ""
        }
    }
}
