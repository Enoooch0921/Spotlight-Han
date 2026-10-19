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
    @Published var currencyResults: [QuickResult] = []
    @Published var currencyTargets: [String] = {
        let saved = CurrencyQuery.cleanTargets(UserDefaults.standard.stringArray(forKey: "currencyTargets.v1") ?? CurrencyQuery.defaultTargets)
        return saved.isEmpty ? CurrencyQuery.defaultTargets : saved
    }()
    @Published var translationEnabled = UserDefaults.standard.object(forKey: "translationEnabled.v1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(translationEnabled, forKey: "translationEnabled.v1") }
    }
    var prepareTranslation: ((String) -> Void)?
    var allQuickResults: [QuickResult] { currencyResults + [translationResult].compactMap { $0 } + quickResults }
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
    @Published var motionEnabled = UserDefaults.standard.object(forKey: "launcherMotion.v1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(motionEnabled, forKey: "launcherMotion.v1") }
    }
    var changeHotkey: ((ShortcutBinding) -> Void)?
    @Published var focusToken = UUID()
    @Published var catalogStatus = "準備檔名清單…"
    @Published var catalogRefreshing = false
    @Published var catalogCount = 0
    @Published var catalogRoots: [URL] = []
    @Published var milliseconds: Double = 0
    @Published var personalStatus: [SearchMode: String] = [:]
    @Published var connecting = Set<SearchMode>()
    @Published var authorizationInFlight = false
    @Published var setupRunning = false
    @Published var setupStatus = ""
    @Published var details: String? { didSet { onLayoutChanged?() } }
    @Published var clockSetupPending = false
    @Published var actionInFlight = false
    @Published var clipboardEnabled = false { didSet { updateClipboard() } }
    var onLayoutChanged: (() -> Void)?
    var hideLauncher: (() -> Void)?
    var prepareSystemAuthorization: (() -> Void)?
    var settingsVisibilityChanged: ((Bool) -> Void)?
    private var sourceQueue = SourceConnectionQueue()
    private var sourceTask: Task<Void, Never>?
    private var connectionGeneration = UUID()
    private var sourceReading = false
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
            let enabled = Set(UserDefaults.standard.stringArray(forKey: "enabledSources.v1") ?? [])
            for source: SearchMode in [.contacts, .calendar, .reminders, .shortcuts, .notes, .mail, .alarms] {
                if enabled.contains(source.rawValue) { enqueueSource(source, allowPrompt: false) }
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
            self.selection = self.currencyResults.first?.id ?? self.quickResults.first(where: { $0.id != "quick:web" })?.id ?? self.results.first?.id ?? self.quickResults.first?.id ?? self.translationResult?.id; self.milliseconds = elapsed; self.searching = false
            self.notice = warning ?? (files.count >= 200 ? "顯示前 200 筆，請增加關鍵字" : "")
            self.onLayoutChanged?()
        }
    }
    private func updateCurrency(query: String) {
        let term = mode == .all ? query : ""
        guard term != currencyQuery else { return }
        currencyQuery = term; currencyTask?.cancel(); currencyResults = []
        let requests = CurrencyQuery.requests(term, defaultTargets: currencyTargets)
        guard !requests.isEmpty else { return }
        currencyResults = [QuickResult(id: "currency:loading", title: "正在取得匯率…", subtitle: "Rates by ExchangeRate-API · 每日更新", symbol: "dollarsign.circle", action: .details("正在取得公開匯率。"))]
        currencyTask = Task {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            let results = await CurrencyService.shared.results(for: requests)
            guard !Task.isCancelled, self.currencyQuery == term else { return }
            currencyResults = results
            if !allIDs.contains(selection ?? "") { selection = currencyResults.first?.id ?? allIDs.first }
            onLayoutChanged?()
        }
    }
    func setCurrencyTarget(_ code: String, enabled: Bool) {
        var targets = currencyTargets
        if enabled, !targets.contains(code) { targets.append(code) }
        if !enabled { targets.removeAll { $0 == code } }
        targets = CurrencyQuery.cleanTargets(targets)
        guard !targets.isEmpty else { return }
        currencyTargets = targets
        UserDefaults.standard.set(targets, forKey: "currencyTargets.v1")
        currencyQuery = ""; search()
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
        enqueueSource(source, allowPrompt: true)
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
                connect(.alarms)
            }
        }
    }
    func setupAllSources() {
        guard !setupRunning else { return }
        setupRunning = true
        // Request the short native permissions before potentially slow Notes/Mail indexing.
        for source: SearchMode in [.contacts, .calendar, .reminders, .shortcuts, .notes, .mail, .alarms] {
            if personalStatus[source]?.hasPrefix("已連接") != true { enqueueSource(source, allowPrompt: true) }
        }
        finishSetupIfIdle()
    }
    private func enqueueSource(_ source: SearchMode, allowPrompt: Bool) {
        if sourceQueue.enqueue(source, allowPrompt: allowPrompt) {
            connecting.insert(source); personalStatus[source] = "等待前一個來源完成…"
        }
        startNextSource()
    }
    private func startNextSource() {
        guard sourceTask == nil, let request = sourceQueue.next() else { return }
        connectionGeneration = UUID()
        let token = connectionGeneration
        sourceTask = Task {
            await loadSource(request.source, allowPrompt: request.allowPrompt, token: token)
            guard token == connectionGeneration else { return }
            connecting.remove(request.source); sourceQueue.finish(); sourceTask = nil
            startNextSource(); finishSetupIfIdle()
        }
    }
    private func finishSetupIfIdle() {
        guard setupRunning, sourceTask == nil, sourceQueue.pending.isEmpty else { return }
        let successful = personalStatus.values.filter { $0.hasPrefix("已連接") }.count
        setupStatus = "已連接 \(successful)/7 個來源；已啟用的來源會在下次啟動自動連接"
        setupRunning = false
    }
    func cancelConnections() {
        connectionGeneration = UUID(); sourceTask?.cancel(); sourceTask = nil
        sourceQueue.cancelAll()
        sourceReading = false
        for source in connecting { personalStatus[source] = "已停止連接；已載入的結果仍可搜尋。系統授權視窗若仍開著，請自行處理或關閉。" }
        connecting.removeAll(); setupRunning = false; authorizationInFlight = false
        setupStatus = "已停止，可稍後逐一重新連接。"; search()
    }
    private func loadSource(_ source: SearchMode, allowPrompt: Bool, token: UUID) async {
        personalStatus[source] = "正在檢查授權…"
        if setupRunning { setupStatus = "正在連接\(source.rawValue)；可隨時停止" }
        let cancellation = ProcessCancellation()
        defer { if token == connectionGeneration { authorizationInFlight = false; sourceReading = false } }
        do {
            if !PersonalSources.isAuthorized(source) {
                guard allowPrompt else {
                    personalStatus[source] = "需要重新授權，請按「重新讀取」；啟動時不會自動彈出授權視窗。"; return
                }
                authorizationInFlight = true; prepareSystemAuthorization?()
                personalStatus[source] = "等待系統授權；請在系統視窗選擇允許或不允許…"
                await Task.yield()
                try await PersonalSources.authorize(source)
            }
            try Task.checkCancellation()
            sourceReading = true
            if source != .notes && source != .mail { authorizationInFlight = false }
            personalStatus[source] = "正在讀取\(source.rawValue)…"
            let loaded: PersonalLoad
            if source == .alarms {
                let connected = try await Task.detached { try SystemClockService.isConnected() }.value
                guard connected else {
                    guard allowPrompt else { personalStatus[source] = "系統時鐘捷徑尚未連接，請按「檢查連接」。"; return }
                    beginClockSetup()
                    personalStatus[source] = "請在系統視窗按「加入捷徑」，完成後回到 App 會自動檢查；只需一次。"
                    return
                }
                clockSetupPending = false
                loaded = PersonalLoad(records: [], status: "已連接 Apple 系統時鐘")
            }
            else {
                let worker = Task.detached(priority: .utility) { () async throws -> PersonalLoad in
                switch source {
                case .contacts: return try await PersonalSources.contacts()
                case .calendar: return try await PersonalSources.calendar()
                case .reminders: return try await PersonalSources.reminders()
                case .notes: return try PersonalSources.notes(cancellation: cancellation) { [weak self] update in
                    Task { @MainActor in
                        guard let self, token == self.connectionGeneration, self.sourceReading, self.sourceQueue.active?.source == .notes else { return }
                        self.authorizationInFlight = false
                        if !update.records.isEmpty {
                            self.personal.removeAll { $0.mode == .notes }; self.personal += update.records
                        }
                        self.personalStatus[.notes] = update.status; self.search()
                    }
                }
                case .mail: return try PersonalSources.mail(cancellation: cancellation)
                case .shortcuts: return try PersonalSources.shortcuts()
                default: throw ProcessFailure.failed("此來源不支援連接。")
                }
                }
                loaded = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { cancellation.cancel(); worker.cancel() }
            }
            try Task.checkCancellation()
            guard token == connectionGeneration else { return }
            personal.removeAll { $0.mode == source }; personal += loaded.records; personalStatus[source] = loaded.status
            var remembered = Set(UserDefaults.standard.stringArray(forKey: "enabledSources.v1") ?? [])
            remembered.insert(source.rawValue)
            UserDefaults.standard.set(remembered.sorted(), forKey: "enabledSources.v1")
        } catch is CancellationError { return }
        catch {
            guard token == connectionGeneration else { return }
            if authorizationInFlight {
                for request in sourceQueue.discardPending() {
                    connecting.remove(request.source)
                    personalStatus[request.source] = "已暫停排隊，請先處理前一個來源的授權，再重新連接。"
                }
                setupRunning = false
                setupStatus = "授權未完成，已停止後續連接，避免繼續疊加系統提示。"
            }
            personalStatus[source] = "連接失敗：" + error.localizedDescription + " 可檢查系統設定 → 隱私權與安全性。"
        }
        if token == connectionGeneration { search() }
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
