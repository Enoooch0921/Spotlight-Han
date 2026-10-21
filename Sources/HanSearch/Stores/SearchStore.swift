import AppKit
import SwiftUI
import HanSearchCore
import EventKit
import Combine

@MainActor
final class SearchStore: ObservableObject {
    @Published var query = ""
    @Published var mode: SearchMode = .all
    @Published var reopenBehavior: SearchReopenBehavior = .timed {
        didSet { taskPreferences.set(reopenBehavior.rawValue, forKey: "searchReopenBehavior.v1") }
    }
    @Published var reopenRetention: TimeInterval = 180 {
        didSet { taskPreferences.set(reopenRetention, forKey: "searchReopenRetention.v1") }
    }
    @Published var defaultSearchMode: SearchMode = .all {
        didSet { taskPreferences.set(defaultSearchMode.rawValue, forKey: "defaultSearchMode.v1") }
    }
    var launcherSessionOpen = false
    var launcherLastDismissed: Date?
    @Published var results: [SearchItem] = [] { didSet { cacheDocumentFilenameMatches(); refreshFileDates() } }
    @Published var fileSort: FileResultSort = .relevance {
        didSet { taskPreferences.set(fileSort.rawValue, forKey: "fileResultSort.v1"); refreshFileDates(); onLayoutChanged?() }
    }
    @Published var fileDates: [String: Date] = [:]
    @Published var readingFileDates = false
    var fileDatesTask: Task<Void, Never>?
    var fileDatesGeneration = UUID()
    var documentFilenameMatches = Set<String>()
    @Published var documentPreviews: [String: DocumentPreview] = [:]
    @Published var verifyingDocumentContents = false
    @Published var documentVerificationCompleted = 0
    @Published var documentVerificationTotal = 0
    @Published var showOtherIndexedResults = false
    var documentVerificationTask: Task<Void, Never>?
    var documentVerificationGeneration = UUID()
    var documentVerificationQuery = ""
    var documentVerificationStarted = Date.distantPast
    @Published var quickResults: [QuickResult] = []
    @Published var translationResult: QuickResult?
    @Published var currencyResults: [QuickResult] = []
    @Published var temperaturePreference: TemperaturePreference = .system {
        didSet { taskPreferences.set(temperaturePreference.rawValue, forKey: "temperaturePreference.v1"); search() }
    }
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
    @Published var showSearchActivity = false
    @Published var searchPhase = ""
    @Published var indexing = false
    @Published var folder: URL?
    @Published var notice = ""
    @Published var indexNotice = ""
    @Published var documentRoots: [URL] = []
    @Published var unavailableDocumentRoots: [URL] = []
    @Published var indexSnapshot = DocumentIndexSnapshot()
    @Published var indexPaused = false
    @Published var indexStorageMB = 500 {
        didSet { taskPreferences.set(indexStorageMB, forKey: "documentIndexStorageMB.v1") }
    }
    @Published var spotlightSupplement = false {
        didSet { taskPreferences.set(spotlightSupplement, forKey: "spotlightSupplement.v1"); cachedGlobalQuery = nil; cachedGlobalContents = []; search() }
    }
    let documentIndexURL: URL
    var documentIndex: PersistentDocumentIndex { PersistentDocumentIndex(databaseURL: documentIndexURL, limitBytes: Int64(indexStorageMB) * 1_000_000) }
    var documentIndexRoots: [URL] { documentRoots.isEmpty ? folder.map { [$0] } ?? [] : documentRoots }
    let documentWatcher = DocumentIndexWatcher()
    var documentIndexTask: Task<Void, Never>?
    var documentIndexCancellation: ProcessCancellation?
    var documentIndexGeneration = UUID()
    var documentChangeTask: Task<Void, Never>?
    var documentChangePending = false
    @Published var documentIssues: [DocumentReadIssue] = []
    @Published var documentIndexCapped = false
    @Published var fullTextInAll = true {
        didSet { taskPreferences.set(fullTextInAll, forKey: "fullTextInAll.v1"); search() }
    }
    @Published var hotkeyNotice = "⌃⌥Space"
    @Published var hotkeyError = "" { didSet { onLayoutChanged?() } }
    let loginItem = LoginItemService()
    let appLibrary = AppLibraryStore()
    let habits: SearchHabitStore
    let aliases: SearchAliasStore
    private var habitsObservation: AnyCancellable?
    private var aliasesObservation: AnyCancellable?
    let appUpdater = AppUpdateService()
    let onboarding: OnboardingProgress
    var showOnboarding: (() -> Void)?
    @Published var settingsPage: SettingsPage = .general
    var onboardingPresented = false
    @Published var interfaceLanguage = L.language {
        didSet { UserDefaults.standard.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage.v1") }
    }
    @Published var translationSource = UserDefaults.standard.string(forKey: "translationSource.v1") ?? "auto" {
        didSet { UserDefaults.standard.set(translationSource, forKey: "translationSource.v1") }
    }
    @Published var translationTarget = UserDefaults.standard.string(forKey: "translationTarget.v1") ?? "zh-Hant" {
        didSet { UserDefaults.standard.set(translationTarget, forKey: "translationTarget.v1") }
    }
    @Published var motionEnabled = UserDefaults.standard.object(forKey: "launcherMotion.v1") as? Bool ?? true {
        didSet { UserDefaults.standard.set(motionEnabled, forKey: "launcherMotion.v1") }
    }
    var changeHotkey: ((ShortcutBinding) -> Void)?
    @Published var focusToken = UUID()
    @Published var catalogStatus = "準備檔名清單…"
    @Published var catalogRefreshing = false
    @Published var catalogCount = 0
    @Published var catalogRoots: [URL] = []
    @Published private(set) var unavailableCatalogRoots: [URL] = []
    var unavailableFolderCount: Int { Set(unavailableCatalogRoots.map(\.path) + fileAccess.unavailablePaths).count }
    @Published var milliseconds: Double = 0
    @Published var personalStatus: [SearchMode: String] = [:]
    @Published var sourceHealth: [SearchMode: SourceHealth] = [:]
    @Published var calendarSort = CalendarResultSort(rawValue: UserDefaults.standard.string(forKey: "calendarResultSort.v1") ?? "") ?? .upcoming {
        didSet { UserDefaults.standard.set(calendarSort.rawValue, forKey: "calendarResultSort.v1"); refreshSearchResults() }
    }
    private var eventChangeStore: EKEventStore?
    private var eventChangeObserver: AnyCancellable?
    private var activationObserver: AnyCancellable?
    private var localeObserver: AnyCancellable?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    @Published var autoRefreshEnabled = true {
        didSet { sourcePreferences.set(autoRefreshEnabled, forKey: "autoRefreshSources.v1"); configureDocumentWatcher(); if autoRefreshEnabled && !indexPaused { rebuildIndex() } }
    }
    @Published var connecting = Set<SearchMode>()
    @Published var authorizationInFlight = false
    @Published var setupRunning = false
    @Published var setupStatus = ""
    @Published var details: String? { didSet { onLayoutChanged?() } }
    @Published var clockSetupPending = false
    @Published var actionInFlight = false
    @Published var composerMode: TaskComposerMode?
    @Published var composerDraft: TaskDraft?
    @Published var composerReviewing = false
    @Published var composerParsing = false
    @Published var composerError = ""
    @Published var composerCreated: String?
    var composerTask: Task<Void, Never>?
    var composerGeneration = UUID()
    var composerWantsReview = false
    var composerInput: String?
    let naturalTaskParser = NaturalTaskParser()
    var showLauncher: (() -> Void)?
    let taskWriter: (@MainActor (TaskPlan) async throws -> String)?
    let taskPreferences: UserDefaults
    let eventCalendarLoader: @MainActor () -> [TaskCalendarChoice]
    @Published var defaultEventCalendarID = "" {
        didSet { taskPreferences.set(defaultEventCalendarID, forKey: "defaultEventCalendarID.v1") }
    }
    @Published var eventCalendarChoices: [TaskCalendarChoice] = []
    @Published var calendarSelectionBusy = false
    @Published var calendarSelectionError = ""
    var settingsPresented = false
    var helpPresented = false
    @Published var clipboardEnabled = false { didSet { updateClipboard() } }
    var onLayoutChanged: (() -> Void)?
    var hideLauncher: (() -> Void)?
    var prepareSystemAuthorization: (() -> Void)?
    var settingsVisibilityChanged: ((Bool) -> Void)?
    private var sourceQueue = SourceConnectionQueue()
    private var sourceTask: Task<Void, Never>?
    private var connectionGeneration = UUID()
    private var sourceReading = false
    private var sourceOwnsAuthorization = false
    private var batchSources: [SearchMode] = []
    private var notesReadState: NotesReadState?
    private var eventWorkers: [SearchMode: Task<Void, Never>] = [:]
    private var eventWorkerTokens: [SearchMode: UUID] = [:]
    private let resultOpener: (URL) -> Bool
    private let noteOpener: @Sendable (String) async throws -> Void
    private let contentSearcher: @Sendable (String, ProcessCancellation) -> SearchResponse
    let documentPreviewLoader: @Sendable (URL, String) async -> DocumentPreview
    let fileCreationDateLoader: @Sendable (URL) async -> Date?
    var cachedGlobalQuery: String?
    var cachedGlobalContents: [SearchItem] = []
    private let sourcePreferences: UserDefaults
    private let sourceAccessCheck: @MainActor (SearchMode) -> Bool
    private let eventSourceLoader: @MainActor (SearchMode) async throws -> PersonalLoad
    let fileAccess: FileAccessBookmarks
    private var entries: [CatalogEntry] = []
    private var personal: [PersonalRecord] = []
    private var clips: [String] = []
    private let clipboard = ClipboardHistory()
    private var lastRefresh = Date.distantPast
    private var generation = UUID()
    private var searchTask: Task<Void, Never>?
    private var searchActivityTask: Task<Void, Never>?
    private var resultRefreshTask: Task<Void, Never>?
    private var pendingResultsRefresh = false
    private var completedQuery: String?
    private var completedMode: SearchMode?

    init(loadSources: Bool = true, fileAccess: FileAccessBookmarks? = nil,
         taskPreferences: UserDefaults = .standard, sourcePreferences: UserDefaults = .standard,
         sourceAccessCheck: @escaping @MainActor (SearchMode) -> Bool = { PersonalSources.isAuthorized($0) },
         eventSourceLoader: @escaping @MainActor (SearchMode) async throws -> PersonalLoad = { source in
             source == .calendar ? try await PersonalSources.calendar() : try await PersonalSources.reminders()
         },
         eventCalendarLoader: @escaping @MainActor () -> [TaskCalendarChoice] = { TaskService.eventCalendars() },
         resultOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
         noteOpener: @escaping @Sendable (String) async throws -> Void = { id in try await Task.detached { try PersonalSources.openNote(id) }.value },
         contentSearcher: @escaping @Sendable (String, ProcessCancellation) -> SearchResponse = { query, cancellation in SearchService.searchDocumentContents(query: query, cancellation: cancellation) },
         documentPreviewLoader: @escaping @Sendable (URL, String) async -> DocumentPreview = { url, query in await DocumentPreviewStore.shared.preview(url: url, query: query) },
         fileCreationDateLoader: @escaping @Sendable (URL) async -> Date? = { await FileCreationDateStore.shared.date(for: $0) },
         documentIndexURL: URL = PersistentDocumentIndex.defaultURL,
         taskWriter: (@MainActor (TaskPlan) async throws -> String)? = nil) {
        self.resultOpener = resultOpener; self.noteOpener = noteOpener
        self.contentSearcher = contentSearcher
        self.documentPreviewLoader = documentPreviewLoader
        self.documentIndexURL = documentIndexURL
        self.fileCreationDateLoader = fileCreationDateLoader
        self.fullTextInAll = taskPreferences.object(forKey: "fullTextInAll.v1") as? Bool ?? true
        self.habits = SearchHabitStore(defaults: taskPreferences)
        self.onboarding = OnboardingProgress(defaults: taskPreferences)
        self.aliases = SearchAliasStore(defaults: taskPreferences)
        self.fileAccess = fileAccess ?? FileAccessBookmarks()
        self.taskWriter = taskWriter
        self.sourcePreferences = sourcePreferences; self.sourceAccessCheck = sourceAccessCheck; self.eventSourceLoader = eventSourceLoader
        self.autoRefreshEnabled = sourcePreferences.object(forKey: "autoRefreshSources.v1") as? Bool ?? true
        self.taskPreferences = taskPreferences; self.eventCalendarLoader = eventCalendarLoader
        self.temperaturePreference = TemperaturePreference(rawValue: taskPreferences.string(forKey: "temperaturePreference.v1") ?? "") ?? .system
        self.reopenBehavior = SearchReopenBehavior(rawValue: taskPreferences.string(forKey: "searchReopenBehavior.v1") ?? "") ?? .timed
        let retention = taskPreferences.double(forKey: "searchReopenRetention.v1")
        self.reopenRetention = retention.isFinite && retention >= 1 ? retention : 180
        self.defaultSearchMode = SearchMode(rawValue: taskPreferences.string(forKey: "defaultSearchMode.v1") ?? "") ?? .all
        self.indexStorageMB = [100, 500, 1000, 2000].contains(taskPreferences.integer(forKey: "documentIndexStorageMB.v1")) ? taskPreferences.integer(forKey: "documentIndexStorageMB.v1") : 500
        self.spotlightSupplement = taskPreferences.object(forKey: "spotlightSupplement.v1") as? Bool ?? false
        self.fileSort = FileResultSort(rawValue: taskPreferences.string(forKey: "fileResultSort.v1") ?? "") ?? .relevance
        self.defaultEventCalendarID = taskPreferences.string(forKey: "defaultEventCalendarID.v1") ?? ""
        appLibrary.onOpened = { [weak self] app, query in
            self?.habits.record(query: query, identity: "app:" + app.preferenceID, kind: .app)
        }
        appLibrary.customAliases = { [weak self] app in self?.aliases.aliases(for: "app:" + app.preferenceID) ?? [] }
        appLibrary.rankSearch = { [weak self] apps, query in
            guard let self else { return apps }
            let candidates = apps.map { HabitCandidate(id: $0.id, identity: "app:" + $0.preferenceID, title: $0.name, kind: .app, aliases: $0.aliases + self.aliases.aliases(for: "app:" + $0.preferenceID)) }
            let order = self.habits.ordered(candidates, query: query)
            let byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return order.compactMap { byID[$0] }
        }
        habitsObservation = habits.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
        aliasesObservation = aliases.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send(); self?.appLibrary.objectWillChange.send() }
        }
        let restoredDocuments = self.fileAccess.restoreIndexRoots(taskPreferences.stringArray(forKey: "documentIndexRoots.v1") ?? [])
        documentRoots = restoredDocuments.available; unavailableDocumentRoots = restoredDocuments.unavailable
        folder = documentRoots.first
        guard loadSources else { return }
        activationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            Task { @MainActor in
                self?.reconcileSourcePermissions()
                if self?.temperaturePreference == .system { self?.search(silent: true) }
            }
        }
        localeObserver = NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification).sink { [weak self] _ in
            Task { @MainActor in
                if self?.temperaturePreference == .system { self?.search(silent: true) }
            }
        }
        eventChangeStore = EventKitAccess.store
        eventChangeObserver = NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventChangeStore).receive(on: DispatchQueue.main).sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.eventSourcesDidChange()
            }
        }
        backgroundRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.refreshAuthorizedSources()
            }
        }
        if let saved = sourcePreferences.stringArray(forKey: "enabledSources.v1") {
            let renamed = saved.map { $0 == "動作" ? SearchMode.shortcuts.rawValue : $0 }
            if renamed != saved { sourcePreferences.set(renamed, forKey: "enabledSources.v1") }
        }
        let allowed = self.fileAccess.urls
        if let saved = UserDefaults.standard.stringArray(forKey: "indexRootPaths.v2") {
            let restored = self.fileAccess.restoreIndexRoots(saved)
            catalogRoots = restored.available; unavailableCatalogRoots = restored.unavailable
        } else { catalogRoots = allowed }
        saveCatalogRoots()
        clipboard.changed = { [weak self] value in
            guard let self else { return }
            self.clips.removeAll { $0 == value }
            self.clips.insert(value, at: 0)
            self.clips = Array(self.clips.prefix(50))
            if self.mode == .clipboard { self.refreshSearchResults() }
        }
        Task {
            await loadPersistentDocumentIndex()
            await loadCatalog()
            let enabled = Set(sourcePreferences.stringArray(forKey: "enabledSources.v1") ?? [])
            for source: SearchMode in [.contacts, .calendar, .reminders, .shortcuts, .notes, .mail, .alarms] {
                if enabled.contains(source.rawValue) { enqueueSource(source, allowPrompt: false) }
            }
        }
        Task.detached(priority: .utility) { _ = SearchService.searchApplications(query: "HanSearch") }
    }
    var hasBody: Bool { composerMode != nil || !query.isEmpty || mode != .all || details != nil || !hotkeyError.isEmpty }
    var isAppBrowser: Bool { mode == .apps && composerMode == nil && details == nil }
    var appSettingsResults: [QuickResult] {
        let term = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return completedMode == .apps && completedQuery == term ? quickResults : []
    }
    var allIDs: [String] { orderedSearchIDs }
    var primaryResultIDs: [String] { allIDs.filter { $0 != translationResult?.id } }
    var showsSearchProgress: Bool { showSearchActivity || verifyingDocumentContents }
    var activityDescription: String? {
        if showSearchActivity { return searchPhase.isEmpty ? "正在搜尋…" : searchPhase }
        if verifyingDocumentContents { return "正在核對文件內文，已確認的結果會先顯示…" }
        if indexing { return indexNotice.isEmpty ? "正在讀取文件內容…" : indexNotice }
        if catalogRefreshing { return catalogStatus }
        if currencyResults.first?.id == "currency:loading" { return "正在取得每日參考匯率…" }
        return nil
    }

    /// Source snapshots refresh results quietly; only query/mode changes start a
    /// visible search. Never interrupt a user query just because another batch arrived.
    func refreshSearchResults() {
        guard composerMode == nil, mode == .clipboard || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pendingResultsRefresh = true
        guard !searching, resultRefreshTask == nil else { return }
        resultRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            self.resultRefreshTask = nil
            guard self.pendingResultsRefresh else { return }
            self.pendingResultsRefresh = false
            self.search(silent: true)
        }
    }
    func search(silent: Bool = false) {
        if silent && searching { pendingResultsRefresh = true; return }
        let term = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if silent && (composerMode != nil || completedQuery != term || completedMode != mode) { return }
        if !silent {
            resetDocumentVerificationIfNeeded(query: term)
            details = nil; notice = ""; resultRefreshTask?.cancel(); resultRefreshTask = nil; pendingResultsRefresh = false
            searchActivityTask?.cancel(); showSearchActivity = false
        }
        onLayoutChanged?()
        searchTask?.cancel()
        let token = UUID(); generation = token
        if composerMode != nil {
            currencyTask?.cancel(); currencyQuery = ""; currencyResults = []; translationResult = nil
            results = []; quickResults = []; selection = nil; searching = false
            updateComposerPreview()
            return
        }
        if !silent { updateCurrency(query: term) }
        if mode == .clipboard {
            quickResults = clips.enumerated().filter { term.isEmpty || ChineseSearch.matches($0.element, query: term) }.map {
                QuickResult(id: "clip:\($0.offset)", title: String($0.element.prefix(100)), subtitle: "剪貼板 · 按 Return 複製", symbol: "doc.on.clipboard", action: .copy($0.element))
            }
            results = []; if !silent || !allIDs.contains(selection ?? "") { selection = quickResults.first?.id }
            completedQuery = term; completedMode = mode; searching = false; onLayoutChanged?(); return
        }
        guard !term.isEmpty else {
            results = []; quickResults = []; selection = nil; searching = false; notice = ""; onLayoutChanged?(); return
        }
        if !silent {
            searching = true; searchPhase = "正在比對\(mode == .all ? "App、檔名與已連接資料" : mode.rawValue)…"
            searchActivityTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                guard let self, self.generation == token, self.searching else { return }
                self.showSearchActivity = true
            }
        }
        let mode = mode, folder = folder, localIndex = documentIndex, localRoots = documentIndexRoots, entries = entries, personal = personal, calendarSort = calendarSort
        let spotlightSupplement = spotlightSupplement
        let cachedContents = cachedGlobalQuery == term ? cachedGlobalContents : []
        let fullTextInAll = fullTextInAll, contentSearcher = contentSearcher
        let temperatureScale = temperaturePreference.resolved()
        let aliasTargets = aliases.matchingTargets(term)
        let aliasPaths = Set(aliasTargets.filter { $0.hasPrefix("file:") }.map { String($0.dropFirst(5)) })
        let processCancellation = ProcessCancellation()
        searchTask = Task {
            if !silent { do { try await Task.sleep(for: .milliseconds(60)) } catch { return } }
            guard !Task.isCancelled else { return }
            let task = Task.detached(priority: silent ? .utility : .userInitiated) {
                let start = Date()
                var files: [SearchItem] = [], quick: [QuickResult] = []
                var localWarning: String?
                let utilities = mode == .apps ? SystemSettingsCatalog.results(query: term) : ([SearchMode.all, .calendar, .reminders, .alarms].contains(mode) ? QuickProvider.results(query: term, defaultTemperatureScale: temperatureScale).filter { mode == .all || (!$0.id.hasPrefix("quick:system-settings:") && $0.id != "quick:settings") } : [])
                let utilityOnly = utilities.contains { $0.id == "quick:calculator" || $0.id == "quick:conversion" || $0.id == "quick:task-command" }
                if !utilityOnly && (mode == .all || mode == .names || mode == .videos) {
                    files += FileCatalog.search(entries, query: term, mode: mode, aliasPaths: aliasPaths)
                }
                if !utilityOnly && (mode == .all || mode == .apps) {
                    files += SearchService.searchApplications(query: term, aliasTargets: aliasTargets)
                }
                if !utilityOnly && (mode == .contents || mode == .all || mode == .names) {
                    let documentMode: SearchMode = mode == .contents ? .contents : mode == .names ? .names : fullTextInAll ? .all : .names
                    do {
                        let response = try localIndex.search(query: term, roots: localRoots, mode: documentMode, cancellation: processCancellation)
                        files += response.items
                        if response.truncated { localWarning = "Han 內文符合超過 200 筆，請增加關鍵字" }
                    } catch is CancellationError {}
                    catch { localWarning = error.localizedDescription }
                }
                let lookup = spotlightSupplement && !utilityOnly && (mode == .all && fullTextInAll || mode == .contents && folder == nil)
                let base = files
                if lookup { files += cachedContents }
                quick += utilities
                if !utilityOnly {
                    let matches = calendarSort.sorted(personal).compactMap { $0.result(query: term, mode: mode, aliasMatch: aliasTargets.contains("quick:" + $0.id)) }
                    quick += (matches.filter { $0.supplement == nil } + matches.filter { $0.supplement != nil }).prefix(50)
                }
                if mode == .all && (term.hasPrefix("define ") || term.hasPrefix("查 ")) {
                    let word = term.split(separator: " ", maxSplits: 1).last.map(String.init) ?? ""
                    if let definition = PersonalSources.definition(word) {
                        quick.append(QuickResult(id: "dictionary", title: word, subtitle: String(definition.prefix(140)), symbol: "character.book.closed", action: .details(definition)))
                    }
                }
                let web = mode == .all ? QuickProvider.webSearch(query: term) : nil
                return (SearchService.merge(files, query: term), quick, web, lookup && !silent, base, Date().timeIntervalSince(start) * 1000, localWarning)
            }
            let (files, quick, web, lookup, base, elapsed, localWarning) = await withTaskCancellationHandler {
                await task.value
            } onCancel: { processCancellation.cancel(); task.cancel() }
            guard !Task.isCancelled, self.generation == token else { return }
            self.quickResults = quick; self.results = files
            if files.isEmpty, quick.isEmpty, let web { self.quickResults = [web] }
            if !silent || !self.allIDs.contains(self.selection ?? "") {
                self.selection = self.allIDs.first(where: { $0 != "quick:web" }) ?? self.allIDs.first
            }
            self.onLayoutChanged?()
            var finalFiles = files, warning = localWarning, totalElapsed = elapsed
            if lookup {
                let contentStarted = Date()
                self.searchPhase = "正在搜尋整台 Mac 的文件內文…"
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard !Task.isCancelled, self.generation == token else { return }
                let contentTask = Task.detached(priority: .userInitiated) { contentSearcher(term, processCancellation) }
                let response = await withTaskCancellationHandler { await contentTask.value } onCancel: { processCancellation.cancel(); contentTask.cancel() }
                guard !Task.isCancelled, self.generation == token else { return }
                totalElapsed += Date().timeIntervalSince(contentStarted) * 1000
                warning = [localWarning, response.warning].compactMap { $0 }.joined(separator: " · ")
                if warning?.isEmpty == true { warning = nil }
                if response.warning == nil {
                    self.cachedGlobalQuery = term; self.cachedGlobalContents = response.items
                }
                // Keep already-visible local matches when the system index fails.
                finalFiles = SearchService.merge(base + (response.warning == nil ? response.items : cachedContents), query: term)
                self.results = finalFiles; self.quickResults = quick
                if finalFiles.isEmpty, quick.isEmpty, let web { self.quickResults = [web] }
                if !self.allIDs.contains(self.selection ?? "") { self.selection = self.allIDs.first(where: { $0 != "quick:web" }) ?? self.allIDs.first }
                if response.truncated && warning == nil { warning = "文件內文符合超過 2,000 筆，請增加關鍵字。" }
                self.verifyDocumentContents(query: term)
            }
            if !silent {
                self.milliseconds = totalElapsed; self.searching = false
                self.searchActivityTask?.cancel(); self.showSearchActivity = false
                self.notice = warning ?? (finalFiles.count >= 200 ? "顯示前 200 筆，請增加關鍵字" : "")
                self.completedQuery = term; self.completedMode = mode
            }
            self.onLayoutChanged?()
            if self.pendingResultsRefresh { self.refreshSearchResults() }
        }
    }
    func pauseSearchForComposer() {
        resetDocumentVerification()
        searchActivityTask?.cancel(); resultRefreshTask?.cancel(); resultRefreshTask = nil
        showSearchActivity = false; pendingResultsRefresh = false
        searchTask?.cancel(); generation = UUID(); currencyTask?.cancel(); currencyQuery = ""
        results = []; quickResults = []; translationResult = nil; currencyResults = []; selection = nil; searching = false
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
            sourceHealth[.names] = SourceHealth(phase: .ready, lastSuccess: cached.updated, invalidated: cached.unreadable > 0 || cached.capped)
            catalogStatus = "已載入 \(entries.count) 筆檔名，正在更新"; refreshSearchResults()
        }
        refreshCatalog()
    }
    func refreshIfNeeded() {
        if Date().timeIntervalSince(lastRefresh) > 30 { refreshCatalog() }
        refreshAuthorizedSources()
    }
    func refreshCatalog() {
        guard !catalogRefreshing else { return }
        guard !catalogRoots.isEmpty else { catalogStatus = "首次請在設定選擇搜尋資料夾"; return }
        catalogRefreshing = true
        sourceHealth[.names, default: SourceHealth()].phase = .loading
        sourceHealth[.names, default: SourceHealth()].lastAttempt = Date()
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
            if snapshot.unreadable > 0 || snapshot.capped || saveError {
                sourceHealth[.names, default: SourceHealth()].phase = .incomplete
                sourceHealth[.names, default: SourceHealth()].partialUpdate = snapshot.updated
                sourceHealth[.names, default: SourceHealth()].lastAttempt = Date()
            } else { sourceHealth[.names, default: SourceHealth()].succeeded(at: snapshot.updated) }
            if saveError { catalogStatus += " · 無法儲存快取" }; refreshSearchResults()
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
            let recovered = fileAccess.restoreIndexRoots(unavailableCatalogRoots.map(\.path))
            unavailableCatalogRoots = recovered.unavailable
            for root in recovered.available where !catalogRoots.contains(where: { $0.path == root.path }) { catalogRoots.append(root) }
            for url in panel.urls {
                let roots = url.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL ? FileCatalog.defaultRoots : [url]
                for root in roots where !catalogRoots.contains(where: { $0.path == root.path }) { catalogRoots.append(root) }
            }
            saveCatalogRoots(); refreshCatalog()
        } catch { catalogStatus = "無法記住資料夾授權：" + error.localizedDescription }
    }
    private func saveCatalogRoots() { UserDefaults.standard.set(Array(Set((catalogRoots + unavailableCatalogRoots).map(\.path))).sorted(), forKey: "indexRootPaths.v2") }
    func removeRoot(_ url: URL) {
        guard !catalogRefreshing else { return }
        catalogRoots.removeAll { $0.path == url.path }; saveCatalogRoots()
        entries.removeAll { entry in !catalogRoots.contains { entry.path.hasPrefix($0.path + "/") } }
        if catalogRoots.isEmpty { sourceHealth[.names] = nil }
        catalogCount = entries.count; search(); refreshCatalog()
    }
    func forgetFolders() {
        guard !catalogRefreshing, !indexing else { return }
        clearDocumentScopes()
        fileAccess.clear(); catalogRoots = []; unavailableCatalogRoots = []; entries = []; documentIssues = []; documentIndexCapped = false; folder = nil; catalogCount = 0
        sourceHealth[.names] = nil; sourceHealth[.contents] = nil
        saveCatalogRoots(); try? FileManager.default.removeItem(at: FileCatalog.cacheURL)
        catalogStatus = "已忘記資料夾；可重新選擇搜尋範圍"; search()
    }
    func openSourcePrivacy(_ source: SearchMode) {
        let anchor: String
        switch source {
        case .calendar: anchor = "Privacy_Calendars"
        case .reminders: anchor = "Privacy_Reminders"
        case .contacts: anchor = "Privacy_Contacts"
        case .notes, .mail: anchor = "Privacy_Automation"
        default: anchor = ""
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) else { return }
        NSWorkspace.shared.open(url)
    }
    func shouldOfferSourcePrivacy(_ source: SearchMode) -> Bool {
        guard sourceHealth[source]?.phase == .needsPermission, !sourceAccessCheck(source) else { return false }
        let current = PersonalSources.permissionFailure(source)
        return SourceHealth(phase: .needsPermission, permissionStatus: current.status).offersPrivacySettings
    }
    func reconcileSourcePermissions() {
        guard !authorizationInFlight, !actionInFlight else { return }
        for source in [SearchMode.contacts, .calendar, .reminders, .notes, .mail] where sourceHealth[source]?.phase == .needsPermission && !connecting.contains(source) {
            if sourceAccessCheck(source) { enqueueSource(source, allowPrompt: false) }
            else { sourceHealth[source]?.permissionStatus = PersonalSources.permissionFailure(source).status }
        }
    }
    func refreshSource(_ source: SearchMode) {
        if source == .names { refreshCatalog() }
        else if source == .contents { rebuildIndex() }
        else { connect(source) }
    }
    func connect(_ source: SearchMode) {
        guard eventWorkers[source] == nil else { return }
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
        guard !setupRunning, connecting.isEmpty, !authorizationInFlight, !actionInFlight else { return }
        setupRunning = true
        batchSources = [.contacts, .calendar, .reminders, .shortcuts, .notes, .mail, .alarms]
        // Request the short native permissions before potentially slow Notes/Mail indexing.
        for source in batchSources {
            enqueueSource(source, allowPrompt: true)
        }
        finishSetupIfIdle()
    }
    var refreshableSources: [SearchMode] {
        let enabled = Set(sourcePreferences.stringArray(forKey: "enabledSources.v1") ?? [])
        return [.contacts, .calendar, .reminders, .shortcuts, .notes, .mail, .alarms].filter {
            enabled.contains($0.rawValue) || sourceHealth[$0] != nil
        }
    }
    func refreshAllConnectedSources() {
        guard !setupRunning, connecting.isEmpty, !authorizationInFlight, !actionInFlight else { return }
        batchSources = refreshableSources
        guard !batchSources.isEmpty else { return }
        setupRunning = true
        // A manual bulk refresh ignores age/backoff, but never opens a consent dialog.
        for source in batchSources { enqueueSource(source, allowPrompt: false) }
        finishSetupIfIdle()
    }
    func refreshAuthorizedSources(changedOnly: Bool = false) {
        guard autoRefreshEnabled, !authorizationInFlight, !actionInFlight, NSApp?.modalWindow == nil else { return }
        let now = Date(), enabled = Set(sourcePreferences.stringArray(forKey: "enabledSources.v1") ?? [])
        for source: SearchMode in [.calendar, .reminders, .contacts, .shortcuts, .notes, .mail, .alarms] {
            guard enabled.contains(source.rawValue), !connecting.contains(source), let health = sourceHealth[source] else { continue }
            let isEventSource = source == .calendar || source == .reminders
            if setupRunning && !isEventSource { continue }
            if changedOnly && (source != .calendar && source != .reminders || !health.invalidated) { continue }
            let interval: TimeInterval = source == .calendar || source == .reminders ? 300 : 900
            guard health.shouldRefresh(at: now, interval: interval, force: health.invalidated) else { continue }
            guard sourceAccessCheck(source) else {
                sourceHealth[source]?.phase = .needsPermission
                sourceHealth[source]?.permissionStatus = PersonalSources.permissionFailure(source).status
                personalStatus[source] = "需要重新授權；背景更新已暫停，請主動按連接。"
                continue
            }
            if isEventSource { startEventRefresh(source) }
            else { enqueueSource(source, allowPrompt: false) }
        }
        if !changedOnly && !setupRunning {
            if !catalogRoots.isEmpty, sourceHealth[.names]?.shouldRefresh(at: now, interval: 900) == true { refreshCatalog() }
            if !documentIndexRoots.isEmpty, !indexPaused, sourceHealth[.contents]?.shouldRefresh(at: now, interval: 900) == true { rebuildIndex() }
        }
    }
    func eventSourcesDidChange() {
        for source: SearchMode in [.calendar, .reminders] where sourceHealth[source]?.hasSnapshot == true {
            sourceHealth[source]?.markChanged()
        }
        refreshEventCalendars()
        scheduleEventSourceRefresh()
    }
    /// Authorised EventKit refreshes have a separate lane from slow Notes / Mail
    /// scripting. The shared store remains main-actor isolated and never asks consent.
    private func startEventRefresh(_ source: SearchMode) {
        guard eventWorkers[source] == nil, !connecting.contains(source), sourceAccessCheck(source) else { return }
        let token = UUID(), revision = sourceHealth[source]?.changeRevision
        eventWorkerTokens[source] = token
        connecting.insert(source)
        sourceHealth[source, default: SourceHealth()].phase = .loading
        sourceHealth[source]?.lastAttempt = Date()
        personalStatus[source] = "正在背景更新\(source.rawValue)…"
        eventWorkers[source] = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await self.eventSourceLoader(source)
                try Task.checkCancellation()
                guard self.eventWorkerTokens[source] == token else { return }
                self.personal.removeAll { $0.mode == source }; self.personal += loaded.records
                self.personalStatus[source] = loaded.status
                self.sourceHealth[source, default: SourceHealth()].completed(at: Date(), complete: loaded.complete, observedRevision: revision)
            } catch is CancellationError { return }
            catch {
                guard self.eventWorkerTokens[source] == token else { return }
                self.sourceHealth[source, default: SourceHealth()].recordFailure(error, at: Date())
                self.personalStatus[source] = error is SourceAccessFailure ? error.localizedDescription : "連接失敗：" + error.localizedDescription
            }
            guard self.eventWorkerTokens[source] == token else { return }
            self.eventWorkers[source] = nil; self.eventWorkerTokens[source] = nil; self.connecting.remove(source)
            self.refreshSearchResults(); self.finishSetupIfIdle(); self.scheduleEventSourceRefresh()
        }
    }
    private func scheduleEventSourceRefresh() {
        guard eventRefreshTask == nil, autoRefreshEnabled else { return }
        eventRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self else { return }
            self.eventRefreshTask = nil
            self.refreshAuthorizedSources(changedOnly: true)
            // Permission dialogs / task writes may temporarily prevent a refresh. Keep
            // the dirty request until it can be queued instead of losing the notification.
            if [.calendar, .reminders].contains(where: { self.sourceHealth[$0]?.phase == .ready && self.sourceHealth[$0]?.invalidated == true }) {
                self.scheduleEventSourceRefresh()
            }
        }
    }
    private func enqueueSource(_ source: SearchMode, allowPrompt: Bool, priority: Bool = false) {
        if sourceQueue.enqueue(source, allowPrompt: allowPrompt, priority: priority) {
            connecting.insert(source)
            if source == .notes, let scan = notesReadState, scan.hasMore { personalStatus[source] = NotesReader.progressStatus(scan) }
            else { personalStatus[source] = "等待前一個來源完成…" }
            sourceHealth[source, default: SourceHealth()].phase = .queued
            sourceHealth[source, default: SourceHealth()].lastAttempt = Date()
        }
        startNextSource()
    }
    func startNextSource() {
        guard !authorizationInFlight, !actionInFlight, sourceTask == nil, let request = sourceQueue.next() else { return }
        connectionGeneration = UUID()
        let token = connectionGeneration
        sourceTask = Task {
            await loadSource(request.source, allowPrompt: request.allowPrompt, token: token)
            guard token == connectionGeneration else { return }
            connecting.remove(request.source); sourceQueue.finish(); sourceTask = nil
            // Changes received during a Notes slice run in the separate EventKit lane;
            // the next Notes worker resumes the same scan without asking permission.
            refreshAuthorizedSources(changedOnly: true)
            if request.source == .notes, notesReadState?.hasMore == true, sourceHealth[.notes]?.phase == .loading {
                enqueueSource(.notes, allowPrompt: false, priority: true)
            }
            startNextSource(); finishSetupIfIdle()
        }
    }
    private func finishSetupIfIdle() {
        guard setupRunning, sourceTask == nil, sourceQueue.pending.isEmpty, batchSources.allSatisfy({ !connecting.contains($0) }) else { return }
        let successful = batchSources.filter { sourceHealth[$0]?.phase == .ready }.count
        let partial = batchSources.filter { sourceHealth[$0]?.phase == .incomplete }.count
        let attention = batchSources.count - successful
        setupStatus = L.format("已完成 %@/%@ 個來源；%@ 個需注意（其中 %@ 個部分讀取），詳見下方狀態。", String(successful), String(batchSources.count), String(attention), String(partial))
        batchSources = []
        setupRunning = false
    }
    func cancelConnections() {
        for worker in eventWorkers.values { worker.cancel() }
        eventWorkers.removeAll(); eventWorkerTokens.removeAll()
        connectionGeneration = UUID(); sourceTask?.cancel(); sourceTask = nil
        sourceQueue.cancelAll()
        sourceReading = false
        for source in connecting {
            personalStatus[source] = "已停止連接；已載入的結果仍可搜尋。系統授權視窗若仍開著，請自行處理或關閉。"
            sourceHealth[source, default: SourceHealth()].phase = .stopped
            sourceHealth[source, default: SourceHealth()].lastAttempt = Date()
        }
        connecting.removeAll(); setupRunning = false; batchSources = []
        if sourceOwnsAuthorization { authorizationInFlight = false; sourceOwnsAuthorization = false }
        setupStatus = "已停止，可稍後逐一重新連接。"; search()
    }
    private func loadSource(_ source: SearchMode, allowPrompt: Bool, token: UUID) async {
        personalStatus[source] = "正在檢查授權…"
        if setupRunning {
            setupStatus = L.format("正在處理 %@（%@/%@）；可隨時停止", L.text(source.rawValue), String((batchSources.firstIndex(of: source) ?? 0) + 1), String(batchSources.count))
        }
        let cancellation = ProcessCancellation()
        var ownsAuthorization = false
        defer { if token == connectionGeneration {
            if ownsAuthorization { authorizationInFlight = false; sourceOwnsAuthorization = false }
            sourceReading = false
        } }
        do {
            if !sourceAccessCheck(source) {
                guard allowPrompt else {
                    personalStatus[source] = PersonalSources.permissionFailure(source).localizedDescription
                    sourceHealth[source, default: SourceHealth()].phase = .needsPermission
                    sourceHealth[source]?.permissionStatus = PersonalSources.permissionFailure(source).status; return
                }
                sourceHealth[source, default: SourceHealth()].phase = .authorizing
                ownsAuthorization = true; sourceOwnsAuthorization = true
                authorizationInFlight = true; prepareSystemAuthorization?()
                personalStatus[source] = "等待系統授權；請在系統視窗選擇允許或不允許…"
                await Task.yield()
                try await PersonalSources.authorize(source)
            }
            try Task.checkCancellation()
            // Once consent is valid, remember the source even if its first data read
            // fails. Background retry should not require another manual Connect click.
            var remembered = Set(sourcePreferences.stringArray(forKey: "enabledSources.v1") ?? [])
            remembered.insert(source.rawValue)
            sourcePreferences.set(remembered.sorted(), forKey: "enabledSources.v1")
            sourceReading = true
            sourceHealth[source, default: SourceHealth()].phase = .loading
            let observedRevision = sourceHealth[source]?.changeRevision
            if ownsAuthorization { authorizationInFlight = false; sourceOwnsAuthorization = false; ownsAuthorization = false }
            personalStatus[source] = "正在讀取\(source.rawValue)…"
            let loaded: PersonalLoad
            if source == .alarms {
                let connected = try await Task.detached { try SystemClockService.isConnected() }.value
                guard connected else {
                    guard allowPrompt else { personalStatus[source] = "系統時鐘捷徑尚未連接，請按「檢查連接」。"; sourceHealth[source, default: SourceHealth()].phase = .needsPermission; return }
                    sourceHealth[source, default: SourceHealth()].phase = .needsPermission
                    beginClockSetup()
                    personalStatus[source] = "請在系統視窗按「加入捷徑」，完成後回到 App 會自動檢查；只需一次。"
                    return
                }
                clockSetupPending = false
                loaded = PersonalLoad(records: [], status: "已連接 Apple 系統時鐘")
            }
            else {
                let notesCheckpoint = notesReadState
                let worker = Task.detached(priority: .utility) { () async throws -> PersonalLoad in
                switch source {
                case .contacts: return try await PersonalSources.contacts()
                case .calendar: return try await PersonalSources.calendar()
                case .reminders: return try await PersonalSources.reminders()
                case .notes: return try PersonalSources.notes(checkpoint: notesCheckpoint, cancellation: cancellation) { [weak self] update in
                    Task { @MainActor in
                        guard let self, token == self.connectionGeneration, self.sourceReading, self.sourceQueue.active?.source == .notes else { return }
                        if !update.records.isEmpty {
                            self.mergeNotes(update.records, keepExisting: update.notesCheckpoint != nil)
                            self.sourceHealth[.notes, default: SourceHealth()].partialUpdate = Date()
                        }
                        self.notesReadState = update.notesCheckpoint
                        self.personalStatus[.notes] = update.status; self.refreshSearchResults()
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
            if source == .notes { mergeNotes(loaded.records, keepExisting: loaded.notesCheckpoint != nil) }
            else { personal.removeAll { $0.mode == source }; personal += loaded.records }
            personalStatus[source] = loaded.status
            if source == .notes { notesReadState = loaded.notesCheckpoint }
            if loaded.notesCheckpoint?.hasMore == true {
                sourceHealth[source, default: SourceHealth()].phase = .loading
                if !loaded.records.isEmpty { sourceHealth[source]?.partialUpdate = Date() }
            } else {
                sourceHealth[source, default: SourceHealth()].completed(at: Date(), complete: loaded.complete, observedRevision: observedRevision)
            }
        } catch is CancellationError { return }
        catch {
            guard token == connectionGeneration else { return }
            // A completed denial can proceed to the next source. An unresolved native
            // prompt (timeout/error) must stop the queue to avoid stacking dialogs.
            if ownsAuthorization && !(error is SourceAccessFailure) {
                for request in sourceQueue.discardPending() {
                    connecting.remove(request.source)
                    sourceHealth[request.source, default: SourceHealth()].phase = .stopped
                    personalStatus[request.source] = "已暫停排隊，請先處理前一個來源的授權，再重新連接。"
                }
                setupRunning = false
                setupStatus = "授權未完成，已停止後續連接，避免繼續疊加系統提示。"
            }
            sourceHealth[source, default: SourceHealth()].recordFailure(error, at: Date())
            personalStatus[source] = error is SourceAccessFailure ? error.localizedDescription : "連接失敗：" + error.localizedDescription
        }
        if token == connectionGeneration { refreshSearchResults() }
    }

    private func mergeNotes(_ records: [PersonalRecord], keepExisting: Bool) {
        let replaced = Set(records.map(\.id))
        personal.removeAll { $0.mode == .notes && (!keepExisting || replaced.contains($0.id)) }
        personal += records
    }

    func disconnect(_ source: SearchMode) {
        if source == .notes { notesReadState = nil }
        personal.removeAll { $0.mode == source }; personalStatus[source] = nil; sourceHealth[source] = nil
        let remembered = (sourcePreferences.stringArray(forKey: "enabledSources.v1") ?? []).filter { $0 != source.rawValue }
        sourcePreferences.set(remembered, forKey: "enabledSources.v1"); search()
    }
    private func updateClipboard() { if clipboardEnabled { clipboard.start() } else { clipboard.stop(); clips = [] }; search() }
    func clearClipboard() { clips = []; search() }
    func openSelection() {
        if composerMode != nil { reviewComposer(); return }
        if let quick = allQuickResults.first(where: { $0.id == selection }) {
            let chosenQuery = query, candidate = habitCandidate(quick)
            switch quick.action {
            case .copy(let value):
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string); notice = "已複製"
            case .open(let url):
                if resultOpener(url) { recordHabit(candidate, query: chosenQuery) }
                else { notice = "無法開啟項目" }
            case .details(let text): details = text; recordHabit(candidate, query: chosenQuery)
            case .prepareTranslation(let source): prepareTranslation?(source)
            case .createTask(let plan):
                if plan.kind != .alarm { previewTask(plan); return }
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
                    actionInFlight = false; startNextSource()
                }
            case .note(let identifier):
                Task {
                    do { try await noteOpener(identifier); recordHabit(candidate, query: chosenQuery) }
                    catch { notice = "無法開啟備忘錄，請檢查自動化授權。" }
                }
            case .shortcut(let name):
                let alert = NSAlert(); alert.messageText = L.format("執行捷徑「%@」？", name)
                alert.informativeText = L.text("此捷徑會執行你在捷徑 App 中設定的動作。請確認內容後執行。")
                alert.addButton(withTitle: L.text("執行")); alert.addButton(withTitle: L.text("取消"))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                Task {
                    do {
                        _ = try await Task.detached { try ProcessRunner.run("/usr/bin/shortcuts", ["run", name], timeout: 60) }.value; notice = "捷徑已執行"; recordHabit(candidate, query: chosenQuery)
                    } catch { notice = "捷徑未完成：" + error.localizedDescription }
                }
            }; return
        }
        guard let item = results.first(where: { $0.id == selection }) else { return }
        guard FileManager.default.fileExists(atPath: item.url.path) else { notice = "檔案已移動或刪除，請更新檔名清單"; return }
        if !resultOpener(item.url) { notice = "無法開啟檔案" }
        else {
            recordHabit(habitCandidate(item), query: query)
            if item.isApplication { appLibrary.recordOpened(InstalledApplication(url: item.url, name: item.name, bundleID: Bundle(url: item.url)?.bundleIdentifier)) }
        }
    }
    func revealSelection() {
        if isAppBrowser, let app = appLibrary.selected(query: query) { NSWorkspace.shared.activateFileViewerSelecting([app.url]); return }
        guard let item = results.first(where: { $0.id == selection }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
    func moveSelection(_ offset: Int) {
        let ids = allIDs; guard !ids.isEmpty else { return }
        let position = ids.firstIndex(of: selection ?? "") ?? 0
        selection = ids[min(max(position + offset, 0), ids.count - 1)]
    }
}
