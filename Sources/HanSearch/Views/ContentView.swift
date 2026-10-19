import SwiftUI
import AppKit
import HanSearchCore

struct ContentView: View {
    @ObservedObject var store: SearchStore
    @FocusState private var focused: Bool
    private let filters: [SearchMode] = [.all, .videos, .contents, .notes, .contacts, .calendar, .reminders, .alarms, .mail]
    var body: some View {
        Group {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 0) { layout }
            } else { layout }
        }
        .padding(40)
        .frame(width: 804, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if #available(macOS 15.0, *) { TranslationBridge(store: store) }
        }
        .onAppear { focused = true }
        .onChange(of: store.query) { _, _ in store.search() }
        .onChange(of: store.mode) { _, _ in store.search() }
        .onChange(of: store.focusToken) { _, _ in
            focused = false
            DispatchQueue.main.async { focused = true }
        }
        .onKeyPress(.downArrow) { store.moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { store.moveSelection(-1); return .handled }
        .onExitCommand { store.hideLauncher?() }
        .environment(\.locale, store.interfaceLanguage.locale)
        .id(store.interfaceLanguage.rawValue)

    }
    private var layout: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 13) {
                    Image(systemName: "magnifyingglass").font(.system(size: 23, weight: .regular)).foregroundStyle(.secondary)
                    TextField(L.text("Spotlight Han 搜尋"), text: $store.query)
                        .font(.system(size: 25, weight: .regular)).textFieldStyle(.plain)
                        .focused($focused).onSubmit { store.openSelection() }
                        .accessibilityLabel(L.text("Spotlight Han 繁簡搜尋"))
                    if store.searching || store.actionInFlight { ProgressView().controlSize(.small) }
                }.padding(.horizontal, 20).frame(height: 60).spotlightGlass(Capsule())
                category(.apps, symbol: "square.grid.2x2", hint: "應用程式 ⌘1")
                category(.names, symbol: "folder", hint: "檔案 ⌘2")
                category(.shortcuts, symbol: "square.stack.3d.up", hint: "捷徑 ⌘3")
                category(.clipboard, symbol: "doc.on.clipboard", hint: "剪貼板 ⌘4")
            }
            if store.hasBody { resultPanel.transition(.opacity) }
        }
        .animation(LauncherMotion.animation(enabled: store.motionEnabled), value: store.hasBody)
    }
    private func category(_ mode: SearchMode, symbol: String, hint: String) -> some View {
        Button {
            store.mode = store.mode == mode ? .all : mode; focused = true
        } label: {
            Image(systemName: symbol).font(.system(size: 21, weight: .regular))
                .foregroundStyle(store.mode == mode ? Color.primary : Color.secondary)
                .frame(width: 54, height: 60)
                .background(store.mode == mode ? Color.primary.opacity(0.08) : .clear, in: Circle())
                .spotlightGlass(Circle())
                .contentShape(.interaction, Circle())
        }.buttonStyle(.plain).help(L.text(hint)).accessibilityLabel(L.text(hint))
            .animation(LauncherMotion.animation(enabled: store.motionEnabled), value: store.mode == mode)
    }
    private var resultPanel: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { mode in
                        Button(L.text(mode.rawValue)) { store.mode = mode; focused = true }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(store.mode == mode ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                            .animation(LauncherMotion.animation(enabled: store.motionEnabled), value: store.mode == mode)
                    }
                }.padding(.horizontal, 14).padding(.vertical, 9)
            }
            Divider().padding(.horizontal, 18)
            if !store.hotkeyError.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Label(L.text(store.hotkeyError), systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    SettingsLink { Text(L.text("前往設定")) }.controlSize(.small)
                }.padding(.horizontal, 18).padding(.vertical, 10)
            }
            Group {
                if let activity = store.activityDescription {
                    ProgressView().progressViewStyle(.linear).controlSize(.small).accessibilityLabel(L.text(activity))
                } else { Color.clear.accessibilityHidden(true) }
            }.frame(height: 3).padding(.horizontal, 18)
            if let details = store.details {
                VStack(alignment: .leading, spacing: 16) {
                    ScrollView { HighlightedText(text: details, query: store.query).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Button(L.text("複製內容")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(details, forType: .string) }
                        Spacer(); Button(L.text("返回搜尋")) { store.details = nil; focused = true }
                    }
                }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.mode == .alarms && store.allQuickResults.isEmpty {
                AlarmListView { store.connect(.alarms) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.allIDs.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(store.allQuickResults) { item in quickRow(item).id(item.id) }
                            ForEach(store.results) { item in
                                ResultRow(item: item, query: store.query)
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background(store.selection == item.id ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 13))
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { store.selection = item.id; store.openSelection() }
                                    .onTapGesture { store.selection = item.id }
                                    .contextMenu {
                                        Button(L.text("開啟")) { store.selection = item.id; store.openSelection() }
                                        Button(L.text("在 Finder 顯示")) { store.selection = item.id; store.revealSelection() }
                                    }.id(item.id)
                            }
                        }.padding(10)
                    }
                    .onChange(of: store.selection) { _, selected in if let selected { proxy.scrollTo(selected) } }
                }
            }
            Divider().padding(.horizontal, 18)
            HStack(spacing: 8) {
                if store.catalogRefreshing || store.indexing { ProgressView().controlSize(.mini) }
                Text(L.text(statusText)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                if store.catalogRoots.isEmpty && [.all, .names, .videos].contains(store.mode) {
                    Button(L.text("選擇資料夾…")) { store.chooseCatalogFolder() }.controlSize(.small)
                }
                Button { store.refreshCatalog() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(store.catalogRefreshing || store.catalogRoots.isEmpty).help(L.text("更新檔名清單"))
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).help(L.text("設定與資料來源"))
                Text(L.text("↵ 開啟")).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .spotlightGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
    private var statusText: String {
        if let activity = store.activityDescription { return activity }
        if !store.notice.isEmpty { return store.notice }
        if store.mode == .contents { return store.folder == nil ? "系統文件索引 · 可在設定加入資料夾加強全文比對" : store.indexNotice }
        if store.mode == .notes || store.mode == .contacts || store.mode == .calendar || store.mode == .reminders || store.mode == .mail || store.mode == .shortcuts {
            return store.personalStatus[store.mode] ?? "尚未連接 · 前往設定啟用"
        }
        return L.text(store.catalogStatus) + (store.query.isEmpty ? "" : String(format: L.text(" · 比對 %.1f ms"), store.milliseconds))
    }
    private func quickRow(_ item: QuickResult) -> some View {
        HStack(spacing: 13) {
            Image(systemName: item.symbol).font(.system(size: 22)).foregroundStyle(.secondary).frame(width: 30, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HighlightedText(text: quickTitle(item), query: store.query).font(.system(size: item.id == "quick:calculator" ? 25 : 14, weight: .medium)).lineLimit(item.id == "quick:translation" ? 2 : 1)
                HighlightedText(text: quickSubtitle(item), query: store.query).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                if item.id.hasPrefix("quick:currency:") {
                    Link("Rates by ExchangeRate-API", destination: URL(string: "https://www.exchangerate-api.com")!).font(.system(size: 10))
                }
            }
            Spacer()
            if store.selection == item.id { Image(systemName: "return").font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 12).padding(.vertical, 10)
            .background(store.selection == item.id ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.selection = item.id; store.openSelection() }
            .onTapGesture { store.selection = item.id }
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
            Text(L.text(emptyDescription)).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if store.catalogRoots.isEmpty && [.all, .names, .videos].contains(store.mode) {
                Button(L.text("選擇搜尋資料夾…")) { store.chooseCatalogFolder() }.buttonStyle(.bordered)
            }
            if [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts, .clipboard].contains(store.mode) {
                SettingsLink { Text(L.text("設定資料來源")) }.buttonStyle(.bordered)
            }
        }.padding(24)
    }
    private var emptyTitle: String {
        if store.mode == .clipboard { return L.text(store.clipboardEnabled ? "尚無剪貼板記錄" : "啟用剪貼板記錄") }
        if [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts].contains(store.mode) && store.personalStatus[store.mode] == nil { return L.format("連接%@", L.text(store.mode.rawValue)) }
        if store.query.isEmpty { return L.format("搜尋%@", L.text(store.mode.rawValue)) }
        return L.text(store.searching ? "正在搜尋…" : "找不到符合的項目")
    }
    private var emptyDescription: String {
        if store.mode == .clipboard { return "記錄預設關閉；啟用後只保留本次執行期間的文字。" }
        if [.notes, .contacts, .calendar, .reminders, .mail, .shortcuts].contains(store.mode) { return store.personalStatus[store.mode] ?? "在設定中啟用，並依系統提示授權。" }
        if store.query.isEmpty { return "輸入關鍵字，繁體與簡體一起比對。" }
        return store.catalogRoots.isEmpty ? "先選擇搜尋範圍，之後會記住資料夾授權。App、計算與換算仍可使用。" : "請縮短關鍵字，或在設定中加入檔案所在資料夾。"
    }
}

private extension View {
    @ViewBuilder func spotlightGlass<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26, *) { self.glassEffect(.regular, in: shape) }
        else { self.background(.ultraThinMaterial, in: shape) }
    }
}
