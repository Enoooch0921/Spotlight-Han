import SwiftUI
import HanSearchCore

struct SettingsView: View {
    @ObservedObject var store: SearchStore
    private let sources: [SearchMode] = [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts, .alarms]
    var body: some View {
        Form {
            Section("一般") {
                LabeledContent("喚出搜尋", value: store.hotkeyNotice)
                Text("⌘1 App、⌘2 檔案、⌘3 動作、⌘4 剪貼板。Escape 收起面板。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("目前使用 ⌃⌥Space。接管 ⌘Space 的設定尚未提供；原本 Spotlight 仍可使用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("快速檔名搜尋") {
                Text(store.catalogStatus).font(.caption)
                ForEach(store.catalogRoots, id: \.path) { root in
                    HStack {
                        Text(root.path).font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("移除") { store.removeRoot(root) }.disabled(store.catalogRefreshing)
                    }
                }
                HStack {
                    Button("加入資料夾…") { store.chooseCatalogFolder() }.disabled(store.catalogRefreshing)
                    Button("更新檔名清單") { store.refreshCatalog() }.disabled(store.catalogRefreshing)
                }
                Text("只讀取檔名，使用自己的本機清單；不依賴 Spotlight。啟動及叫出面板時會更新（間隔至少 30 秒）。新檔案可手動更新。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Word 與 PDF 內容") {
                Text(store.folder?.path ?? "未指定資料夾：文件內容模式使用 Spotlight 索引").font(.caption)
                if !store.indexNotice.isEmpty { Text(store.indexNotice).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("加入文件資料夾…") { store.chooseFolder() }.disabled(store.indexing)
                    if store.folder != nil {
                        Button("重新讀取") { store.rebuildIndex() }.disabled(store.indexing)
                        Button("使用系統索引") { store.resetScope() }.disabled(store.indexing)
                    }
                }
                Text("資料夾全文索引只留在記憶體，結束 App 後需重新加入。掃描文件尚未提供 OCR。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("系統 App 資料來源") {
                HStack {
                    Button("一次設定所有資料來源") { store.setupAllSources() }.disabled(store.setupRunning || !store.connecting.isEmpty)
                    if store.setupRunning { ProgressView().controlSize(.small) }
                }
                Text(store.setupStatus.isEmpty ? "集中連接備忘錄、聯絡人、行事曆、提醒事項、郵件、捷徑與系統時鐘。macOS 仍可能分別詢問授權；成功後會記住，之後自動連接。" : store.setupStatus)
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(sources, id: \.self) { source in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(source.rawValue).fontWeight(.medium)
                            Spacer()
                            if store.connecting.contains(source) { ProgressView().controlSize(.small) }
                            Button(source == .alarms ? "檢查連接" : (store.personalStatus[source] == nil ? "連接" : "重新讀取")) { store.connect(source) }.disabled(store.connecting.contains(source) || store.setupRunning)
                            if store.personalStatus[source] != nil && !store.connecting.contains(source) {
                                Button("移除") { store.disconnect(source) }
                            }
                        }
                        Text(store.personalStatus[source] ?? scope(source)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                }
                Text("資料只留在本次執行的記憶體；搜尋不修改或上傳；只有你確認新增指令時才寫入行事曆、提醒事項或系統時鐘。系統授權由你確認。移除來源會清除 App 內的搜尋副本；撤銷系統授權請至系統設定。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("剪貼板") {
                Toggle("記錄剪貼板文字", isOn: $store.clipboardEnabled)
                Text("預設關閉。啟用後只在記憶體保留最近 50 筆、每筆最多 2,000 字；略過標示為隱藏／暫存的內容及常見密碼管理器。其他 App 未標示的敏感文字仍可能被記錄。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("清除記錄") { store.clearClipboard() }
            }
            Section("行程、提醒與鬧鐘指令") {
                Text("設定30分鐘後的鬧鐘\n提醒我明天上午9點交報告\n明天下午3點開會30分鐘")
                    .font(.callout).textSelection(.enabled)
                Text("先顯示時間與內容，按 Return 才建立。行程及提醒使用系統預設行事曆／清單；新增需要相應的存取授權。鬧鐘交給 Apple 系統時鐘。首次按下方「連接系統時鐘」，在系統視窗加入一次捷徑；不用自己編輯。系統鬧鐘精度為分鐘，只支援下一次的指定時分。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("連接系統時鐘") { store.beginClockSetup() }
                    Button("檢查連接") { store.connect(.alarms) }
                    Button("開啟時鐘") { SystemClockService.openClock() }
                }
            }
            Section("關於") {
                Text("Spotlight Han 0.4.0 · 繁簡中文搜尋")
                Text("依 macOS 27 Spotlight 官方參考重做的獨立啟動器。目前在 macOS 26 驗證；不包含 Siri／Apple Intelligence、即時匯率或所有系統 App 動作。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { store.hideLauncher?() }
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
