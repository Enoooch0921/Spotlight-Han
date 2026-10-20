import SwiftUI
import HanSearchCore

struct OnboardingSourcesPage: View {
    @ObservedObject var store: SearchStore
    let settings: (SettingsPage) -> Void
    private let sources: [SearchMode] = [.notes, .contacts, .calendar, .reminders]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sources, id: \.self) { source in
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: symbol(source)).font(.title3).foregroundStyle(.secondary).frame(width: 26)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L.text(source.rawValue)).font(.headline)
                        Text(L.text(detail(source))).font(.callout).foregroundStyle(.secondary)
                        if let health = store.sourceHealth[source] { SourceHealthView(health: health) }
                        if let status = store.personalStatus[source], store.sourceHealth[source]?.needsAttention(at: Date()) == true {
                            Text(L.text(status)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    if store.connecting.contains(source) { ProgressView().controlSize(.small) }
                    Button(L.text(store.sourceHealth[source]?.hasSnapshot == true ? "重新讀取" : "連接")) { store.connect(source) }
                        .disabled(store.connecting.contains(source) || store.authorizationInFlight || store.setupRunning || store.actionInFlight)
                }
                if source != sources.last { Divider() }
            }
            OnboardingNote(text: "只有按下「連接」才會要求對應權限。授權有效時，已連接來源可安靜背景更新。", symbol: "hand.raised")
            HStack {
                Text(L.text("Mail、捷徑與系統時鐘，也能在設定中連接。"))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(L.text("管理所有來源…")) { settings(.sources) }
            }
        }
    }
    private func symbol(_ source: SearchMode) -> String {
        switch source { case .notes: return "note.text"; case .contacts: return "person.crop.rectangle"; case .calendar: return "calendar"; default: return "checklist" }
    }
    private func detail(_ source: SearchMode) -> String {
        switch source {
        case .notes: return "搜尋標題與可讀取的純文字內文；不讀取鎖定備忘錄。"
        case .contacts: return "搜尋你允許取用的姓名、電話與電子郵件。"
        case .calendar: return "搜尋前後各一年的行程、地點與備註。"
        default: return "搜尋未完成提醒；也能在確認預覽後新增。"
        }
    }
}
