import AppKit
import SwiftUI
import HanSearchCore

@MainActor
final class SearchStore: ObservableObject {
    @Published var query = ""
    @Published var mode: SearchMode = .all
    @Published var results: [SearchItem] = []
    @Published var quickResults: [QuickResult] = []
    @Published var translationResult: QuickResult?
    @Published var currencyResult: QuickResult?
    @Published var translationEnabled = UserDefaults.standard.object(forKey: "translationEnabled.v1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(translationEnabled, forKey: "translationEnabled.v1") }
    }
    var prepareTranslation: ((String) -> Void)?
    var allQuickResults: [QuickResult] { [currencyResult, translationResult].compactMap { $0 } + quickResults }
    private var currencyTask: Task<Void, Never>?
    private var currencyQuery = ""
    @Published var selection: String?
    @Published var searching = false
    @Published var indexing = false
    @Published var folder: URL?
    @Published var notice = ""
    @Published var indexNotice = ""
    @Published var hotkeyNotice = "⌃⌥Space"
    @Published var hotkeyError = ""
    var changeHotkey: ((ShortcutBinding) -> Void)?
    @Published var focusToken = UUID()
    @Published var catalogStatus = "準備檔名清單…"
    @Published var catalogRefreshing = false
    @Published var catalogCount = 0
    @Published var catalogRoots: [URL] = []
    @Published var milliseconds: Double = 0
    @Published var personalStatus: [SearchMode: String] = [:]
    @Published var connecting = Set<SearchMode>()
    @Published var setupRunning = false
    @Published var setupStatus = ""
    @Published var details: String? { didSet { onLayoutChanged?() } }
    @Published var clockSetupPending = false
    @Published var actionInFlight = false
    @Published var clipboardEnabled = false { didSet { updateClipboard() } }
    var onLayoutChanged: (() -> Void)?
    var hideLauncher: (() -> Void)?
    private let fileAccess = FileAccessBookmarks()
    private var documents: [IndexedDocument] = []
    private var entries: [CatalogEntry] = []
    private var personal: [PersonalRecord] = []
    private var clips: [String] = []
    private let clipboard = ClipboardHistory()
    private var lastRefresh = Date.distantPast
    private var generation = UUID()
    private var searchTask: Task<Void, Never>?

    init() {
        let allowed = fileAccess.urls
        if let saved = UserDefaults.standard.stringArray(forKey: "indexRootPaths.v2") {
            catalogRoots = saved.map { fileAccess.resolvedIndexURL($0) }.filter { root in allowed.contains { root.path == $0.path || root.path.hasPrefix($0.path + "/") } }
        } else { catalogRoots = allowed }
        UserDefaults.standard.set(catalogRoots.map(\.path), forKey: "indexRootPaths.v2")
        clipboard.changed = { [weak self] value in
            guard let self else { return }
            self.clips.removeAll { $0 == value }
            self.clips.insert(value, at: 0)
            self.clips = Array(self.clips.prefix(50))
            if self.mode == .clipboard { self.search() }
        }
        Task {
            await loadCatalog()
            for raw in UserDefaults.standard.stringArray(forKey: "enabledSources.v1") ?? [] {
                if let source = SearchMode(rawValue: raw) { await loadSource(source) }
            }
        }
        Task.detached(priority: .utility) { _ = SearchService.searchApplications(query: "HanSearch") }
    }
    var hasBody: Bool { !query.isEmpty || mode != .all || details != nil }
    var allIDs: [String] { allQuickResults.map(\.id) + results.map(\.id) }

    func search() {
        details = nil
        onLayoutChanged?()
        searchTask?.cancel()
        let token = UUID(); generation = token
        let term = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        updateCurrency(query: term)
        if mode == .clipboard {
            quickResults = clips.enumerated().filter { term.isEmpty || ChineseSearch.matches($0.element, query: term) }.map {
                QuickResult(id: "clip:\($0.offset)", title: String($0.element.prefix(100)), subtitle: "剪貼板 · 按 Return 複製", symbol: "doc.on.clipboard", action: .copy($0.element))
            }
            results = []; selection = quickResults.first?.id; searching = false; onLayoutChanged?(); return
        }
        guard !term.isEmpty else {
            results = []; quickResults = []; selection = nil; searching = false; notice = ""; onLayoutChanged?(); return
        }
        searching = true
        let mode = mode, folder = folder, docs = documents, entries = entries, personal = personal
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            guard !Task.isCancelled else { return }
            let task = Task.detached(priority: .userInitiated) {
                let start = Date()
                var files: [SearchItem] = [], quick: [QuickResult] = []
                var warning: String?
                let utilities = [SearchMode.all, .calendar, .reminders, .alarms].contains(mode) ? QuickProvider.results(query: term) : []
                let utilityOnly = utilities.contains { $0.id == "quick:calculator" || $0.id == "quick:conversion" || $0.id == "quick:task-command" }
                if !utilityOnly && (mode == .all || mode == .names || mode == .videos) {
                    files += FileCatalog.search(entries, query: term, mode: mode)
                }
                if !utilityOnly && (mode == .all || mode == .apps) {
                    files += SearchService.searchApplications(query: term)
                }
                if mode == .contents {
                    if folder != nil { files += docs.compactMap { $0.match(query: term, mode: .contents) } }
                    else {
                        let response = SearchService.search(query: term, mode: .contents)
                        files += response.items; warning = response.warning
                    }
                }
                quick += utilities
                if !utilityOnly { quick += personal.compactMap { $0.result(query: term, mode: mode) }.prefix(50) }
                if mode == .all && (term.hasPrefix("define ") || term.hasPrefix("查 ")) {
                    let word = term.split(separator: " ", maxSplits: 1).last.map(String.init) ?? ""
                    if let definition = PersonalSources.definition(word) {
                        quick.append(QuickResult(id: "dictionary", title: word, subtitle: String(definition.prefix(140)), symbol: "character.book.closed", action: .details(definition)))
                    }
                }
                let web = mode == .all ? QuickProvider.webSearch(query: term) : nil
                return (SearchService.merge(files, query: term), quick, web, warning, Date().timeIntervalSince(start) * 1000)
            }
            let (files, quick, web, warning, elapsed) = await task.value
            guard !Task.isCancelled, self.generation == token else { return }
            self.quickResults = quick; self.results = files
            if files.isEmpty, quick.isEmpty, let web { self.quickResults = [web] }
            self.selection = self.currencyResult?.id ?? self.quickResults.first(where: { $0.id != "quick:web" })?.id ?? self.results.first?.id ?? self.quickResults.first?.id ?? self.translationResult?.id; self.milliseconds = elapsed; self.searching = false
            self.notice = warning ?? (files.count >= 200 ? "顯示前 200 筆，請增加關鍵字" : "")
            self.onLayoutChanged?()
        }
    }
    private func updateCurrency(query: String) {
        let term = mode == .all ? query : ""
        guard term != currencyQuery else { return }
        currencyQuery = term; currencyTask?.cancel(); currencyResult = nil
        guard let request = CurrencyQuery.parse(term) else { return }
        currencyResult = QuickResult(id: "currency", title: "正在取得匯率…", subtitle: "Rates by ExchangeRate-API · 每日更新", symbol: "dollarsign.circle", action: .details("正在取得公開匯率。"))
        currencyTask = Task {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            let result = await CurrencyService.shared.result(for: request)
            guard !Task.isCancelled, self.currencyQuery == term else { return }
            currencyResult = result
            if selection == nil { selection = allIDs.first }
            onLayoutChanged?()
        }
    }
    func setTranslation(_ result: QuickResult?) {
        translationResult = result
        if let selection, !allIDs.contains(selection) { self.selection = allIDs.first }
        onLayoutChanged?()
    }
    private func loadCatalog() async {
        guard !catalogRoots.isEmpty else { catalogStatus = "首次請在設定選擇搜尋資料夾"; return }
        if let cached = await Task.detached(priority: .utility, operation: { FileCatalog.load() }).value {
            entries = cached.entries.filter { entry in catalogRoots.contains { entry.path.hasPrefix($0.path + "/") } }; catalogCount = entries.count
            catalogStatus = "已載入 \(entries.count) 筆檔名，正在更新"; search()
        }
        refreshCatalog()
    }
    func refreshIfNeeded() { if Date().timeIntervalSince(lastRefresh) > 30 { refreshCatalog() } }
    func refreshCatalog() {
        guard !catalogRefreshing else { return }
        guard !catalogRoots.isEmpty else { catalogStatus = "首次請在設定選擇搜尋資料夾"; return }
        catalogRefreshing = true
        let roots = catalogRoots
        catalogStatus = "正在掃描檔名（不讀取影片內容）…"
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                FileCatalog.scan(roots: roots) { count in
                    Task { @MainActor in self.catalogStatus = "已掃描 \(count) 筆檔名…" }
                }
            }.value
            entries = snapshot.entries; catalogCount = entries.count; lastRefresh = Date(); catalogRefreshing = false
            catalogStatus = "\(entries.count.formatted()) 筆檔名 · " + lastRefresh.formatted(date: .omitted, time: .shortened)
                + (snapshot.unreadable > 0 ? " · \(snapshot.unreadable) 個位置無法讀取" : "")
                + (snapshot.capped ? " · 已達 500,000 筆上限" : "")
            let saveError = await Task.detached(priority: .utility) { () -> Bool in
                do { try FileCatalog.save(snapshot); return false } catch { return true }
            }.value
            if saveError { catalogStatus += " · 無法儲存快取" }; search()
        }
    }
    func chooseCatalogFolder() {
        guard !catalogRefreshing else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "允許搜尋"; panel.message = "可按住 ⌘ 一次選擇多個資料夾；選擇你的使用者資料夾可一次涵蓋下載、影片、文件，只索引這三處。App 會記住選擇。"
        guard panel.runModal() == .OK else { return }
        do {
            try fileAccess.add(panel.urls)
            for url in panel.urls {
                let roots = url.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL ? FileCatalog.defaultRoots : [url]
                for root in roots where !catalogRoots.contains(where: { $0.path == root.path }) { catalogRoots.append(root) }
            }
            saveCatalogRoots(); refreshCatalog()
        } catch { catalogStatus = "無法記住資料夾授權：" + error.localizedDescription }
    }
    private func saveCatalogRoots() { UserDefaults.standard.set(catalogRoots.map(\.path), forKey: "indexRootPaths.v2") }
    func removeRoot(_ url: URL) {
        guard !catalogRefreshing else { return }
        catalogRoots.removeAll { $0.path == url.path }; saveCatalogRoots()
        entries.removeAll { entry in !catalogRoots.contains { entry.path.hasPrefix($0.path + "/") } }
        catalogCount = entries.count; search(); refreshCatalog()
    }
    func forgetFolders() {
        guard !catalogRefreshing, !indexing else { return }
        fileAccess.clear(); catalogRoots = []; entries = []; documents = []; folder = nil; catalogCount = 0
        saveCatalogRoots(); try? FileManager.default.removeItem(at: FileCatalog.cacheURL)
        catalogStatus = "已忘記資料夾；可重新選擇搜尋範圍"; search()
    }
    func chooseFolder() {
        guard !indexing else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "讀取文件內容"; panel.message = "直接讀取此資料夾的 Word、文字 PDF 與純文字，供繁簡全文搜尋。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try fileAccess.add([url]); folder = url; mode = .contents; rebuildIndex() }
        catch { indexNotice = "無法保存文件資料夾授權：" + error.localizedDescription }
    }
    func rebuildIndex() {
        guard let folder, !indexing else { return }
        indexing = true; documents = []; indexNotice = "正在讀取「\(folder.lastPathComponent)」中的文件…"; search()
        Task {
            let indexed = await Task.detached(priority: .utility) { SearchService.index(folder: folder) }.value
            documents = indexed.documents; indexing = false
            indexNotice = "已讀取 \(indexed.documents.count) 個檔案" + (indexed.skippedText > 0 ? " · \(indexed.skippedText) 份內容未完整讀取" : "") + (indexed.capped ? " · 10,000 檔案上限" : ""); search()
        }
    }
    func resetScope() { guard !indexing else { return }; folder = nil; documents = []; indexNotice = ""; search() }
    func connect(_ source: SearchMode) {
        Task { await loadSource(source) }
    }
    func beginClockSetup() {
        clockSetupPending = true
        hideLauncher?()
        SystemClockService.install()
    }
    func checkClockSetupOnReturn() {
        guard clockSetupPending, !connecting.contains(.alarms) else { return }
        Task {
            if (try? await Task.detached { try SystemClockService.isConnected() }.value) == true {
                await loadSource(.alarms)
            }
        }
    }
    func setupAllSources() {
        guard !setupRunning else { return }
        setupRunning = true
        Task {
            let sources: [SearchMode] = [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts, .alarms]
            for (index, source) in sources.enumerated() {
                setupStatus = "\(index + 1)/\(sources.count) · \(source.rawValue)"
                if personalStatus[source]?.hasPrefix("已連接") != true { await loadSource(source) }
            }
            let successful = sources.filter { personalStatus[$0]?.hasPrefix("已連接") == true }.count
            setupStatus = "已連接 \(successful)/\(sources.count) 個來源；已啟用的來源會在下次啟動自動連接"
            setupRunning = false
        }
    }
    private func loadSource(_ source: SearchMode) async {
        guard !connecting.contains(source) else { return }
        connecting.insert(source); personalStatus[source] = "正在連接，請留意系統授權視窗…"
            do {
                let loaded: PersonalLoad
                if source == .alarms {
                    let connected = try await Task.detached { try SystemClockService.isConnected() }.value
                    guard connected else {
                        beginClockSetup()
                        personalStatus[source] = "請在系統視窗按「加入捷徑」，完成後回到 App 會自動檢查；只需一次。"
                        connecting.remove(source); return
                    }
                    clockSetupPending = false
                    loaded = PersonalLoad(records: [], status: "已連接 Apple 系統時鐘")
                }
                else { loaded = try await Task.detached(priority: .utility) { () async throws -> PersonalLoad in
                    switch source {
                    case .contacts: return try await PersonalSources.contacts()
                    case .calendar: return try await PersonalSources.calendar()
                    case .reminders: return try await PersonalSources.reminders()
                    case .notes: return try PersonalSources.notes()
                    case .mail: return try PersonalSources.mail()
                    case .shortcuts: return try PersonalSources.shortcuts()
                    default: throw ProcessFailure.failed("此來源不支援連接。")
                    }
                }.value }
                personal.removeAll { $0.mode == source }; personal += loaded.records; personalStatus[source] = loaded.status
                var remembered = Set(UserDefaults.standard.stringArray(forKey: "enabledSources.v1") ?? [])
                remembered.insert(source.rawValue)
                UserDefaults.standard.set(remembered.sorted(), forKey: "enabledSources.v1")
            } catch { personalStatus[source] = "連接失敗：" + error.localizedDescription + " 可檢查系統設定 → 隱私權與安全性。" }
            connecting.remove(source); search()
    }
    func disconnect(_ source: SearchMode) {
        personal.removeAll { $0.mode == source }; personalStatus[source] = nil
        let remembered = (UserDefaults.standard.stringArray(forKey: "enabledSources.v1") ?? []).filter { $0 != source.rawValue }
        UserDefaults.standard.set(remembered, forKey: "enabledSources.v1"); search()
    }
    private func updateClipboard() { if clipboardEnabled { clipboard.start() } else { clipboard.stop(); clips = [] }; search() }
    func clearClipboard() { clips = []; search() }
    func openSelection() {
        if let quick = allQuickResults.first(where: { $0.id == selection }) {
            switch quick.action {
            case .copy(let value):
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string); notice = "已複製"
            case .open(let url): NSWorkspace.shared.open(url)
            case .details(let text): details = text
            case .prepareTranslation(let source): prepareTranslation?(source)
            case .createTask(let plan):
                guard !actionInFlight else { return }
                actionInFlight = true
                searchTask?.cancel(); generation = UUID()
                let originalQuery = query
                notice = "正在建立…"
                Task {
                    do {
                        let resolved = plan.resolved(at: Date())
                        let message = resolved.kind == .alarm ? try await Task.detached { try SystemClockService.create(resolved) }.value : try await TaskService.create(resolved)
                        if query == originalQuery {
                            quickResults = [QuickResult(id: "task-created", title: message.components(separatedBy: .newlines).first ?? "已建立", subtitle: message.components(separatedBy: .newlines).dropFirst().joined(separator: " · "), symbol: "checkmark.circle", action: .details(message))]
                            results = []; selection = quickResults.first?.id; onLayoutChanged?()
                        }
                        notice = "已建立"
                    } catch {
                        notice = error.localizedDescription
                        if plan.kind == .alarm, query == originalQuery {
                            quickResults = [QuickResult(id: "check-clock", title: "請先核對系統時鐘", subtitle: error.localizedDescription, symbol: "alarm", action: .open(URL(fileURLWithPath: "/System/Applications/Clock.app")))]
                            results = []; selection = quickResults.first?.id; onLayoutChanged?()
                        }
                    }
                    actionInFlight = false
                }
            case .note(let identifier):
                Task {
                    do { try await Task.detached { try PersonalSources.openNote(identifier) }.value }
                    catch { notice = "無法開啟備忘錄，請檢查自動化授權。" }
                }
            case .shortcut(let name):
                let alert = NSAlert(); alert.messageText = "執行捷徑「\(name)」？"
                alert.informativeText = "此捷徑會執行你在捷徑 App 中設定的動作。請確認內容後執行。"
                alert.addButton(withTitle: "執行"); alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                Task {
                    do {
                        _ = try await Task.detached { try ProcessRunner.run("/usr/bin/shortcuts", ["run", name], timeout: 60) }.value; notice = "捷徑已執行"
                    } catch { notice = "捷徑未完成：" + error.localizedDescription }
                }
            }; return
        }
        guard let item = results.first(where: { $0.id == selection }) else { return }
        guard FileManager.default.fileExists(atPath: item.url.path) else { notice = "檔案已移動或刪除，請更新檔名清單"; return }
        if !NSWorkspace.shared.open(item.url) { notice = "無法開啟檔案" }
    }
    func revealSelection() {
        guard let item = results.first(where: { $0.id == selection }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
    func moveSelection(_ offset: Int) {
        let ids = allIDs; guard !ids.isEmpty else { return }
        let position = ids.firstIndex(of: selection ?? "") ?? 0
        selection = ids[min(max(position + offset, 0), ids.count - 1)]
    }
}
