import SwiftUI
import HanSearchCore

struct SettingsView: View {
    @ObservedObject var store: SearchStore
    private let sources: [SearchMode] = [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts, .alarms]
    var body: some View {
        Form {
            Section(L.text("一般")) {
                Picker(L.text("介面語言"), selection: $store.interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                StartupSettingsView(service: store.loginItem)
                LabeledContent(L.text("喚出搜尋"), value: store.hotkeyNotice)
                Toggle(L.text("柔和過渡動畫"), isOn: $store.motionEnabled)
                Text(L.text("開啟／收起使用短淡入淡出，結果面板平順展開。系統開啟「減少動態效果」時保留淡化、停止高度動畫。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L.text("⌘1 App、⌘2 檔案、⌘3 捷徑、⌘4 剪貼板。Escape 收起面板。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    ShortcutRecorder(title: L.format("自訂：%@", store.hotkeyNotice)) { store.changeHotkey?($0) }.frame(width: 230, height: 26)
                    Button(L.text("使用 ⌘Space")) { store.changeHotkey?(.commandSpace) }
                    Button(L.text("恢復預設")) { store.changeHotkey?(.standard) }
                }
                if !store.hotkeyError.isEmpty { Label(L.text(store.hotkeyError), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                Text(L.text("快捷鍵可開啟及收起面板。若要用 ⌘Space，先在系統設定 → 鍵盤 → 鍵盤快捷鍵 → Spotlight 關閉「顯示 Spotlight 搜尋」，再按上方「使用 ⌘Space」。App 會記住你的選擇；若有衝突，保留原快捷鍵。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L.text("開啟 Spotlight 快捷鍵開關")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Spotlight")!)
                }
            }
            Section(L.text("快速檔名搜尋")) {
                TimelineView(.periodic(from: Date(), by: 30)) { context in SourceHealthView(health: store.sourceHealth[.names], now: context.date) }
                Text(L.text(store.catalogStatus)).font(.caption)
                ForEach(store.catalogRoots, id: \.path) { root in
                    HStack {
                        Text(root.path).font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(L.text("移除")) { store.removeRoot(root) }.disabled(store.catalogRefreshing)
                    }
                }
                HStack {
                    Button(L.text("選擇搜尋資料夾…")) { store.chooseCatalogFolder() }.disabled(store.catalogRefreshing)
                    Button(L.text("更新檔名清單")) { store.refreshCatalog() }.disabled(store.catalogRefreshing || store.indexing || store.catalogRoots.isEmpty)
                    Button(L.text("忘記資料夾")) { store.forgetFolders() }.disabled(store.catalogRefreshing || store.indexing || store.catalogRoots.isEmpty)
                }
                Text(L.text("開發測試版在重新編譯或重新簽章後，macOS 仍可能要求重新授權；正式發行需要固定的開發者簽章。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L.text("首次集中選擇搜尋範圍，之後使用已保存的資料夾書籤；不會在啟動時自動探查未選的下載或文件資料夾。選擇使用者資料夾可涵蓋下載、影片、文件。只讀取檔名、不依賴 Spotlight，更新間隔至少 30 秒。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.text("Word 與 PDF 內容")) {
                if store.folder != nil { TimelineView(.periodic(from: Date(), by: 30)) { context in SourceHealthView(health: store.sourceHealth[.contents], now: context.date) } }
                Text(store.folder?.path ?? L.text("未指定資料夾：文件內容模式使用 Spotlight 索引")).font(.caption)
                if !store.indexNotice.isEmpty { Text(L.text(store.indexNotice)).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button(L.text("加入文件資料夾…")) { store.chooseFolder() }.disabled(store.indexing)
                    if store.folder != nil {
                        Button(L.text("重新讀取")) { store.rebuildIndex() }.disabled(store.indexing)
                        Button(L.text("使用系統索引")) { store.resetScope() }.disabled(store.indexing)
                    }
                }
                Text(L.text("資料夾全文索引只留在記憶體，結束 App 後需重新加入。掃描文件尚未提供 OCR。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.text("系統 App 資料來源")) {
                Toggle(L.text("背景自動更新已連接來源"), isOn: $store.autoRefreshEnabled)
                    .onChange(of: store.autoRefreshEnabled) { _, enabled in if enabled { store.refreshAuthorizedSources() } }
                Text(L.text("授權有效時安靜更新，不會反覆詢問。行事曆／提醒事項每5分鐘及收到變更後更新；其他已連接來源與文件索引每15分鐘更新。權限失效會暫停並顯示狀態，等你主動重新連接。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L.text("全部重新讀取")) { store.refreshAllConnectedSources() }
                        .disabled(store.refreshableSources.isEmpty || store.setupRunning || !store.connecting.isEmpty || store.authorizationInFlight || store.actionInFlight)
                    Button(L.text("一次設定所有資料來源")) { store.setupAllSources() }.disabled(store.setupRunning || !store.connecting.isEmpty || store.authorizationInFlight || store.actionInFlight)
                    if store.setupRunning { ProgressView().controlSize(.small) }
                    if !store.connecting.isEmpty { Button(L.text("停止連接")) { store.cancelConnections() } }
                }
                Text(L.text(store.setupStatus.isEmpty ? "按「全部重新讀取」即可一次更新所有已連接來源，不會彈出授權視窗。首次使用可按「一次設定所有資料來源」，缺少的系統授權會依序詢問。更新顯示各來源進度，可隨時停止。" : store.setupStatus))
                    .font(.caption).foregroundStyle(.secondary)
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
                Text(L.text("資料只留在本次執行的記憶體；搜尋不修改或上傳；只有你確認新增指令時才寫入行事曆、提醒事項或系統時鐘。系統授權由你確認。移除來源會清除 App 內的搜尋副本；撤銷系統授權請至系統設定。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.text("翻譯與貨幣換算")) {
                if #available(macOS 15.0, *) { TranslationLanguageSettingsView(store: store) }
                Toggle(L.text("顯示查詢翻譯"), isOn: $store.translationEnabled)
                Text(L.text("使用 Apple 本機翻譯（macOS 15 以上）。語言已下載時自動顯示；缺少語言時，選取翻譯結果按 Return 開啟語言視窗，再進入系統語言下載設定。下載後可跨 App 共用。原查詢的檔案與 App 結果仍保留。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L.text("貨幣可輸入 3000tb=rmb、3000tb rmb、nt3000 = rmb。只輸入 3000tb 或 3000台幣，會顯示下方選取的目標；也可明寫 3000tb=rmb,usd,jpy。參考匯率每日更新，結果標示資料時間及過期快取，非銀行成交價。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L.text("也可用國名：3000NT=馬來西亞、3000NT 馬來、3000NT=Malaysia；New Zealand、South Korea 等英文國名也支援。")).font(.caption).foregroundStyle(.secondary)
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
            Section(L.text("剪貼板")) {
                Toggle(L.text("記錄剪貼板文字"), isOn: $store.clipboardEnabled)
                Text(L.text("預設關閉。啟用後只在記憶體保留最近 50 筆、每筆最多 2,000 字；略過標示為隱藏／暫存的內容及常見密碼管理器。其他 App 未標示的敏感文字仍可能被記錄。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L.text("清除記錄")) { store.clearClipboard() }
            }
            Section(L.text("行程、提醒與鬧鐘指令")) {
                EventCalendarPicker(store: store, selection: $store.defaultEventCalendarID, label: "Han 預設行事曆")
                Text(L.text("新行程會先選這個行事曆；確認預覽時仍可更改。此設定只影響 Han。")).font(.caption).foregroundStyle(.secondary)
                Text(L.text("設定30分鐘後的鬧鐘\n提醒我明天上午9點交報告\n明天下午3點開會30分鐘"))
                    .font(.callout).textSelection(.enabled)
                Text(L.text("行程與提醒：輸入 cal／行事曆或提醒／rem，按 Tab 後輸入時間和事項。Return 進入確認預覽，按「確認建立」或 ⌘Return 才寫入。行程可選擇 Han 預設行事曆及當次目的地；提醒使用系統預設清單。系統鬧鐘仍按 Return 建立，首次需連接內附捷徑。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L.text("連接系統時鐘")) { store.beginClockSetup() }
                    Button(L.text("檢查連接")) { store.connect(.alarms) }
                    Button(L.text("開啟時鐘")) { SystemClockService.openClock() }
                }
            }
            Section(L.text("關於")) {
                Text(L.format("Spotlight Han %@ · 繁簡中文搜尋", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"))
                Text(L.text("依 macOS 27 Spotlight 官方參考重做的獨立啟動器。目前在 macOS 26 驗證；不包含 Siri／Apple Intelligence 或所有系統 App 動作。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
            .environment(\.locale, store.interfaceLanguage.locale)
            .id(store.interfaceLanguage.rawValue)
            .onAppear { store.settingsPresented = true; store.settingsVisibilityChanged?(true); store.reconcileSourcePermissions() }
            .onDisappear { store.settingsPresented = false; store.settingsVisibilityChanged?(false) }
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
