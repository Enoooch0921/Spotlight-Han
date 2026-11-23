import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HanSearchCore

struct ContentView: View {
    @ObservedObject var store: SearchStore
    @State private var dropTarget = false
    @State private var focused = false
    @FocusState private var appGridFocused: Bool
    @Namespace private var glassNamespace
    @State private var retainsBody = false
    @State private var bodyContentVisible = false
    @State private var surfaceGeneration = 0
    private enum Surface: Equatable { case collapsed, results, apps, composer, inspection }
    private var surface: Surface {
        store.diagnosticURL != nil ? .inspection : store.composerMode != nil ? .composer : !store.hasBody ? .collapsed : store.isAppBrowser ? .apps : .results
    }
    private let filters: [SearchMode] = [.all, .videos, .contents, .notes, .contacts, .calendar, .reminders, .alarms, .mail]
    var body: some View {
        Group {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 0) { layout }
            } else { layout }
        }
        .overlay {
            if dropTarget { Label(L.text("放開以檢查檔案"), systemImage: "doc.text.magnifyingglass").padding(12).background(.regularMaterial, in: Capsule()).allowsHitTesting(false) }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            guard store.composerMode == nil, providers.count == 1, let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { return }
                Task { @MainActor in
                    guard store.composerMode == nil else { return }
                    store.inspectFile(url)
                    store.showLauncher?()
                }
            }
            return true
        }
        .padding(40)
        .frame(width: 804, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if #available(macOS 15.0, *) { TranslationBridge(store: store) }
        }
        .onAppear { focused = true }
        .onChange(of: surface, initial: true) { _, _ in updateSurface() }
        .onChange(of: store.inputRevision) { _, _ in store.search() }
        .onChange(of: store.mode) { _, mode in
            appGridFocused = false; focused = true
            if mode == .apps { store.appLibrary.select(.all) }
        }
        .onChange(of: store.focusToken) { _, _ in
            dropTarget = false
            appGridFocused = false; focused = false
            DispatchQueue.main.async { focused = true }
        }
        .onKeyPress(.downArrow) { vertical(1) }
        .onKeyPress(.upArrow) { vertical(-1) }
        .onKeyPress(.leftArrow) { horizontal(-1) }
        .onKeyPress(.rightArrow) { horizontal(1) }
        .onKeyPress(.return) { if store.isAppBrowser && appGridFocused && !store.appLibrary.isEditingCategory && !store.appLibrary.isPreviewingSuggestions { openApp(); return .handled }; return .ignored }
        .onExitCommand { escape() }
        .environment(\.locale, store.interfaceLanguage.locale)
        .environment(\.launcherMotionEnabled, store.motionEnabled)
        .id(store.interfaceLanguage.rawValue)

    }
    private var layout: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 13) {
                    Image(systemName: store.composerMode == .event ? "calendar.badge.plus" : store.composerMode == .reminder ? "checklist" : "magnifyingglass").font(.system(size: 23, weight: .regular)).foregroundStyle(.secondary)
                        .overlay { LauncherMoveHandle().help(L.text("拖曳以移動搜尋視窗")) }
                    LauncherSearchField(text: $store.query, focused: $focused,
                        placeholder: L.text(store.composerMode == nil ? (store.isAppBrowser ? "搜尋應用程式…" : "Spotlight Han 搜尋") : "輸入時間和事項…"),
                        accessibilityLabel: L.text(store.composerMode == nil ? "Spotlight Han 繁簡搜尋" : "輸入時間和事項"),
                        enabled: !store.actionInFlight && store.composerCreated == nil,
                        inspectDroppedFile: store.composerMode == nil ? { url in
                            store.inspectFile(url)
                            store.showLauncher?()
                        } : nil,
                        submit: {
                            guard store.diagnosticURL == nil else { return }
                            if store.isAppBrowser {
                                if let quick = store.appSettingsResults.first { store.selection = quick.id; store.openSelection() }
                                else { openApp() }
                            } else { store.openSelection() }
                        }, tab: { store.enterComposer() }, move: { vertical($0) == .handled }, escape: escape)
                        .frame(height: 34)
                    if store.composerMode == nil && !store.query.isEmpty {
                        Button { store.query = ""; focused = true } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                .frame(width: 24, height: 32).contentShape(Rectangle())
                        }.buttonStyle(LauncherButtonStyle()).help(L.text("清除搜尋"))
                            .accessibilityLabel(L.text("清除搜尋"))
                    }
                    if store.actionInFlight || store.composerParsing { ProgressView().controlSize(.small) }
                    if store.composerMode != nil {
                        Button { store.cancelComposer() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 28, height: 32).contentShape(Rectangle()) }
                            .buttonStyle(LauncherButtonStyle()).disabled(store.actionInFlight).help(L.text("返回搜尋"))
                    }
                }.padding(.horizontal, 20).frame(height: 60).spotlightGlass(Capsule())
                    .launcherGlassIdentity("search-field", in: glassNamespace)
                if store.composerMode == nil {
                    category(.apps, symbol: "square.grid.2x2", hint: "應用程式 ⌘1")
                    category(.names, symbol: "folder", hint: "檔案 ⌘2")
                    category(.shortcuts, symbol: "square.stack.3d.up", hint: "捷徑 ⌘3")
                    category(.clipboard, symbol: "doc.on.clipboard", hint: "剪貼板 ⌘4")
                }
            }
            AppUpdateBanner(updater: store.appUpdater)
            if store.composerMode == nil, let command = TaskComposerMode.command(store.query) {
                Button { store.enterComposer() } label: {
                    HStack {
                        Label(L.text(command == .event ? "按 Tab 新增行事曆行程" : "按 Tab 新增提醒事項"), systemImage: command == .event ? "calendar.badge.plus" : "checklist")
                        Spacer(); Text("Tab ⇥").font(.caption.monospaced())
                    }.padding(.horizontal, 20).padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).spotlightGlass(Capsule())
            }
            if surface != .collapsed || retainsBody {
                VStack(spacing: 0) {
                    if let url = store.diagnosticURL { FileInspectionView(store: store, url: url).id(url) }
                    else if store.composerMode != nil { TaskComposerView(store: store).transition(.opacity) }
                    else if store.isAppBrowser { AppBrowserView(store: store, library: store.appLibrary, gridFocused: $appGridFocused).transition(.opacity) }
                    else { resultPanel.transition(.opacity) }
                }
                .animation(LauncherMotion.structure(enabled: store.motionEnabled), value: surface)
                .opacity(bodyContentVisible ? 1 : 0)
                .spotlightGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .launcherGlassIdentity("body", in: glassNamespace)
                .transition(.identity)
            }
        }
    }
    private func updateSurface() {
        surfaceGeneration += 1
        let generation = surfaceGeneration
        if surface != .collapsed { retainsBody = true }
        // Animate content inside the material, never an opacity group containing
        // the glass. Keep the same surface alive while the window contracts.
        withAnimation(LauncherMotion.structure(enabled: store.motionEnabled), completionCriteria: .logicallyComplete) {
            bodyContentVisible = surface != .collapsed
        } completion: {
            guard generation == surfaceGeneration, surface == .collapsed else { return }
            retainsBody = false
        }
    }
    private func category(_ mode: SearchMode, symbol: String, hint: String) -> some View {
        Button {
            store.mode = store.mode == mode ? .all : mode; focused = true
        } label: {
            Image(systemName: symbol).font(.system(size: 21, weight: .regular))
                .foregroundStyle(store.mode == mode ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 54, height: 60)
                .background(store.mode == mode ? Color.primary.opacity(0.08) : .clear, in: Circle())
                .spotlightGlass(Circle())
                .launcherGlassIdentity("category-" + mode.rawValue, in: glassNamespace)
                .contentShape(.interaction, Circle())
        }.buttonStyle(LauncherButtonStyle(shape: AnyShape(Circle()))).help(L.text(hint)).accessibilityLabel(L.text(hint))
            .accessibilityAddTraits(store.mode == mode ? .isSelected : [])
            .animation(LauncherMotion.animation(enabled: store.motionEnabled), value: store.mode == mode)
    }
    private var resultPanel: some View {
        let visibleIDs = store.primaryResultIDs
        let quickByID = Dictionary(store.allQuickResults.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fileByID = Dictionary(store.results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { mode in
                        Button { store.mode = mode; focused = true } label: {
                            Text(L.text(mode.rawValue)).font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 7)
                                .contentShape(Capsule())
                        }.buttonStyle(LauncherButtonStyle())
                            .accessibilityAddTraits(store.mode == mode ? .isSelected : [])
                            .launcherSelectionAnchor(mode.rawValue)
                    }
                }
                .launcherSelectionBackground(store.mode.rawValue, cornerRadius: 20)
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
            Divider().padding(.horizontal, 18)
            FileFilterBar(store: store)
            if store.canSortFileResults {
                HStack(spacing: 10) {
                    Picker(L.text("檔案排序"), selection: $store.fileSort) {
                        ForEach(FileResultSort.allCases, id: \.self) { order in Text(L.text(order.title)).tag(order) }
                    }.fixedSize()
                    if store.readingFileDates {
                        ProgressView().controlSize(.mini)
                        Text(L.text("正在讀取建立日期…")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.controlSize(.small).padding(.horizontal, 18).padding(.vertical, 8)
            }
            if store.mode == .calendar || (store.mode == .all && store.allQuickResults.contains(where: { $0.id.hasPrefix("quick:event:") })) {
                Picker(L.text("行事曆排序"), selection: $store.calendarSort) {
                    ForEach(CalendarResultSort.allCases, id: \.self) { order in Text(L.text(order.title)).tag(order) }
                }.controlSize(.small).padding(.horizontal, 18).padding(.vertical, 8)
            }
            if !store.hotkeyError.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Label(L.text(store.hotkeyError), systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    SettingsEntryButton(store: store) { Text(L.text("前往設定")) }.controlSize(.small)
                }.padding(.horizontal, 18).padding(.vertical, 10)
            }
            if let details = store.details {
                VStack(alignment: .leading, spacing: 16) {
                    ScrollView { HighlightedText(text: details, query: store.allQuickResults.first(where: { $0.id == store.selection })?.supplement?.query ?? store.query).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Button(L.text("複製內容")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(details, forType: .string) }
                        Spacer(); Button(L.text("返回搜尋")) { store.details = nil; focused = true }
                    }
                }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.mode == .alarms && store.allQuickResults.isEmpty {
                AlarmListView { store.connect(.alarms) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.searching && visibleIDs.isEmpty {
                // The footer shows progress for slower searches. Keep the results
                // area quiet during the debounce instead of flashing setup actions.
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleIDs.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(visibleIDs, id: \.self) { id in
                                if let item = quickByID[id] { quickRow(item).id(id) }
                                else if let item = fileByID[id] { fileRow(item).id(id) }
                            }
                        }.padding(10)
                    }
                    .onChange(of: store.selection) { _, selected in if let selected, visibleIDs.contains(selected) { proxy.scrollTo(selected) } }
                }
            }
            if store.otherIndexedResultCount > 0 {
                HStack {
                    Button { store.toggleOtherIndexedResults() } label: {
                        Label(L.format(store.showOtherIndexedResults ? "收起其他系統索引結果（%@）" : "其他系統索引結果（%@）", String(store.otherIndexedResultCount)), systemImage: store.showOtherIndexedResults ? "chevron.up" : "chevron.down")
                    }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                        .help(L.text("尚未確認完整內文命中，可能只有檔名、中繼資料或系統分詞符合；預設收起。"))
                    Spacer()
                }.padding(.horizontal, 18).padding(.vertical, 8)
            }
            if !store.parsedFileQuery.active { SearchSourceHealthBanner(store: store) }
            if let translation = store.translationResult, store.details == nil {
                Divider().padding(.horizontal, 18)
                SearchTranslationAccessory(store: store, item: translation)
            }
            if store.showsSearchProgress {
                Divider().padding(.horizontal, 18)
                SearchActivityView(store: store)
            }
            Divider().padding(.horizontal, 18)
            HStack(spacing: 8) {
                if store.catalogRefreshing || store.indexing { ProgressView().controlSize(.mini) }
                Text(L.text(statusText)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                if store.documentIndexRoots.isEmpty && store.fullTextInAll && [.all, .contents].contains(store.mode) {
                    Button(L.text("加入文件資料夾…")) { store.chooseFolder() }.controlSize(.small)
                } else if store.catalogRoots.isEmpty && [.all, .names, .videos].contains(store.mode) {
                    Button(L.text("選擇資料夾…")) { store.chooseCatalogFolder() }.controlSize(.small)
                }
                Button { store.refreshCatalog() } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24).contentShape(Rectangle()) }.buttonStyle(LauncherButtonStyle()).disabled(store.catalogRefreshing || store.catalogRoots.isEmpty).help(L.text("更新檔名清單"))
                SettingsEntryButton(store: store) { Image(systemName: "gearshape").frame(width: 24, height: 24).contentShape(Rectangle()) }.buttonStyle(LauncherButtonStyle()).help(L.text("設定與資料來源"))
                if store.selectedPreviewItem != nil {
                    Button(L.text(store.previewSelectionArmed ? "空白鍵 預覽" : "快速預覽")) { if let item = store.selectedPreviewItem { store.previewFile(item) } }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                        .help(L.text("先選取檔案，再按空白鍵預覽；輸入搜尋詞時仍可打空格。"))
                }
                if let id = store.rankingUndo {
                    Button(L.text("復原降序")) { store.setLowered(false, fileID: id) }.controlSize(.small)
                }
                if store.actionFile != nil {
                    Button(L.text("操作 ⌘K")) { store.showFileActions?() }.controlSize(.small)
                }
                Text(L.text("↵ 開啟")).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
    }
    private func fileRow(_ item: SearchItem) -> some View {
        ResultRow(item: item, query: store.matchText, preview: store.documentPreviews[item.id])
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(store.selection == item.id ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.selection = item.id; store.openSelection() }
            .onTapGesture { store.selection = item.id; store.previewSelectionArmed = true }
            .background { ResultDragRegion(payload: .url(item.url)) }
            .contextMenu {
                if !item.isApplication {
                    Button(L.text("快速預覽")) { store.previewFile(item) }
                    Button(L.text("檢查這個檔案")) { store.inspectFile(item.url) }
                    let lowered = store.habits.history.loweredFiles(query: store.query, ids: [item.id]).contains(item.id)
                    Button(L.text(lowered ? "恢復這筆的搜尋順位" : "只在這個搜尋詞降低順位")) {
                        store.setLowered(!lowered, fileID: item.id)
                    }
                }
                Button(L.text("自訂搜尋縮寫…")) { store.editAliases(identity: store.habitCandidate(item).identity, title: item.name) }
                Button(L.text("開啟")) { store.selection = item.id; store.openSelection() }
                Button(L.text("在 Finder 顯示")) { store.selection = item.id; store.revealSelection() }
            }
    }
    private func openApp() {
        if let app = store.appLibrary.selected(query: store.query), store.appLibrary.open(app, query: store.query) { store.hideLauncher?() }
    }
    private func escape() {
        store.escapeLauncherLayer()
    }
    private func vertical(_ direction: Int) -> KeyPress.Result {
        guard store.diagnosticURL == nil, !store.appLibrary.isEditingCategory, !store.appLibrary.isPreviewingSuggestions else { return .ignored }
        guard store.isAppBrowser else { store.moveSelection(direction); return .handled }
        if !appGridFocused {
            guard direction > 0 else { return .ignored }
            focused = false; appGridFocused = true; store.appLibrary.selectFirst(query: store.query)
        } else {
            let apps = store.appLibrary.items(query: store.query)
            let index = apps.firstIndex { $0.id == store.appLibrary.selection } ?? 0
            let columns = store.appLibrary.listView ? 1 : 5
            if direction < 0 && index < columns { appGridFocused = false; focused = true }
            else { store.appLibrary.move(direction * columns, query: store.query) }
        }
        return .handled
    }
    private func horizontal(_ direction: Int) -> KeyPress.Result {
        guard store.isAppBrowser, appGridFocused, !store.appLibrary.isEditingCategory, !store.appLibrary.isPreviewingSuggestions else { return .ignored }
        store.appLibrary.move(direction, query: store.query); return .handled
    }
    private var statusText: String {
        if let activity = store.activityDescription { return activity }
        if !store.notice.isEmpty { return store.notice }
        if store.mode == .contents { return store.documentIndexRoots.isEmpty ? "加入文件資料夾以建立 Han 全文索引" : store.indexNotice }
        if store.mode == .notes || store.mode == .contacts || store.mode == .calendar || store.mode == .reminders || store.mode == .mail || store.mode == .shortcuts {
            return store.personalStatus[store.mode] ?? "尚未連接 · 前往設定啟用"
        }
        let summary = store.mode == .all && store.fullTextInAll && store.catalogRoots.isEmpty ? L.text(store.spotlightSupplement ? "Han 文件索引＋Spotlight 補充" : store.documentIndexRoots.isEmpty ? "尚未建立 Han 文件索引" : "Han 文件索引・已選資料夾") : L.text(store.catalogStatus)
        return summary + (store.query.isEmpty ? "" : String(format: L.text(" · 比對 %.1f ms"), store.milliseconds))
    }
    private func quickRow(_ item: QuickResult) -> some View {
        HStack(spacing: 13) {
            SourceAppIcon(app: item.sourceApp, symbol: item.symbol, showsPaneSymbol: item.id.hasPrefix("quick:system-settings:")).frame(width: 30, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HighlightedText(text: quickTitle(item), query: item.supplement?.query ?? store.query).font(.system(size: item.id == "quick:calculator" ? 25 : 14, weight: .medium)).lineLimit(item.id == "quick:translation" ? 2 : 1)
                HighlightedText(text: quickSubtitle(item), query: item.supplement?.query ?? store.query).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                if let match = item.supplement { SearchSupplementLabel(match: match) }
                if item.id.hasPrefix("quick:currency:") {
                    Link("Rates by ExchangeRate-API", destination: URL(string: "https://www.exchangerate-api.com")!).font(.system(size: 10))
                }
            }
            Spacer()
            if let start = item.startDate {
                Text(L.text((item.endDate ?? start) < Date() ? "已過去" : start <= Date() ? "進行中" : "即將到來"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if case .note = item.action {
                let titleOnly = item.noteText?.isEmpty != false
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(.secondary).font(.caption)
                    .help(L.text(titleOnly ? "目前只有備忘錄標題可拖出" : "拖到文字欄位可插入備忘錄文字，拖到 Finder 可存成文字檔"))
            }
            if store.selection == item.id { Image(systemName: "return").font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 12).padding(.vertical, 10)
            .background(store.selection == item.id ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.selection = item.id; store.openSelection() }
            .onTapGesture { store.selection = item.id }
            .background {
                if let payload = SearchResultDrag(item) { ResultDragRegion(payload: payload) }
            }
            .contextMenu {
                if let candidate = store.habitCandidate(item) {
                    Button(L.text("自訂搜尋縮寫…")) { store.editAliases(identity: candidate.identity, title: item.title) }
                }
            }
    }
    private func quickTitle(_ item: QuickResult) -> String {
        // Personal names, clipboard text and actual translations are content, not UI labels.
        if case .prepareTranslation = item.action { return L.text(item.title) }
        if ["quick:settings", "quick:task-command", "quick:task-created", "quick:web", "quick:check-clock"].contains(item.id) || item.id.hasPrefix("quick:currency:") || item.id.hasPrefix("quick:system-settings:") { return L.text(item.title) }
        return item.title
    }
    private func quickSubtitle(_ item: QuickResult) -> String {
        if item.id.hasPrefix("quick:currency:"), let code = item.id.split(separator: ":").last.map(String.init),
           CurrencyQuery.supportedCodes.contains(code), let name = store.interfaceLanguage.locale.localizedString(forCurrencyCode: code) {
            return name + " · " + L.text(item.subtitle)
        }
        if ["quick:note:", "quick:contact:", "quick:event:", "quick:reminder:", "quick:mail:", "quick:dictionary"].contains(where: { item.id.hasPrefix($0) }) { return item.subtitle }
        return L.text(item.subtitle)
    }
    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(emptyTitle).font(.system(size: 15, weight: .medium))
            if !emptyDescription.isEmpty {
                Text(L.text(emptyDescription)).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if store.catalogRoots.isEmpty && [.all, .names, .videos].contains(store.mode) {
                Button(L.text("選擇搜尋資料夾…")) { store.chooseCatalogFolder() }.buttonStyle(.bordered)
            }
            if [.all, .contents].contains(store.mode) && store.documentIndexRoots.isEmpty {
                Button(L.text("加入文件資料夾…")) { store.chooseFolder() }.buttonStyle(.bordered)
            }
            if store.mode == .clipboard && store.hasClipboardHistory && !store.query.isEmpty {
                Button(L.text("清除搜尋")) { store.query = ""; focused = true }.buttonStyle(.bordered)
            } else if [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts, .clipboard].contains(store.mode) {
                SettingsEntryButton(store: store) { Text(L.text("設定資料來源")) }.buttonStyle(.bordered)
            }
        }.padding(24)
    }
    private var emptyTitle: String {
        if store.mode == .clipboard && store.hasClipboardHistory && !store.query.isEmpty { return L.text("找不到符合的項目") }
        if store.mode == .clipboard { return L.text(store.clipboardEnabled ? "尚無剪貼板記錄" : "啟用剪貼板記錄") }
        if [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts].contains(store.mode) && store.personalStatus[store.mode] == nil { return L.format("連接%@", L.text(store.mode.rawValue)) }
        if store.query.isEmpty { return L.format("搜尋%@", L.text(store.mode.rawValue)) }
        return L.text(store.searching || store.verifyingDocumentContents ? "正在搜尋…" : "找不到符合的項目")
    }
    private var emptyDescription: String {
        if store.parsedFileQuery.active { return "可移除上方條件，或檢查檔案所在資料夾是否已加入搜尋。" }
        if store.mode == .clipboard && store.hasClipboardHistory && !store.query.isEmpty { return "" }
        if store.mode == .clipboard { return "記錄預設關閉；啟用後只保留本次執行期間的文字。" }
        if [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts].contains(store.mode) { return store.personalStatus[store.mode] ?? "在設定中啟用，並依系統提示授權。" }
        if store.query.isEmpty { return "輸入關鍵字，繁體與簡體一起比對。" }
        if store.verifyingDocumentContents { return "正在核對文件內文，已確認的結果會先顯示…" }
        if store.otherIndexedResultCount > 0 { return "尚未找到完整字詞命中；其他系統索引結果已收起，可展開查看。" }
        if store.mode == .all && store.fullTextInAll {
            return store.searching ? "正在搜尋 Han 文件索引與已連接資料…" : "已搜尋 Han 收錄的文件與已連接資料；可增加搜尋資料夾。Spotlight 補充可在設定另行啟用；掃描 PDF 尚需 OCR。"
        }
        return store.catalogRoots.isEmpty ? "先選擇搜尋範圍，之後會記住資料夾授權。App、計算與換算仍可使用。" : "請縮短關鍵字，或在設定中加入檔案所在資料夾。"
    }
}

extension View {
    @ViewBuilder func spotlightGlass<S: Shape>(_ shape: S) -> some View {
        // A hierarchical style lets glass supply a vibrant foreground as its backdrop changes.
        if #available(macOS 26, *) { self.foregroundStyle(.primary).glassEffect(.regular, in: shape) }
        else { self.background(.ultraThinMaterial, in: shape) }
    }
}
