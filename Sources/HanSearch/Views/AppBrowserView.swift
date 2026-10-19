import SwiftUI
import AppKit
import HanSearchCore

struct AppBrowserView: View {
    @ObservedObject var store: SearchStore
    @ObservedObject var library: AppLibraryStore
    @FocusState.Binding var gridFocused: Bool
    @State private var draftSymbol = "folder"
    @State private var expandedSuggestions = Set<String>()
    @State private var selectedSuggestions = Set([ApplicationSuggestion.waves, .izotope, .production, .office].map(\.rawValue))
    @State private var draftName = ""
    @State private var editingID: String?
    @State private var dropTargetID: String?
    @FocusState private var nameFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { store.mode = .all; store.focusToken = UUID() } label: {
                    Image(systemName: "arrow.left").frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).help(L.text("返回搜尋"))
                Text(L.text("應用程式")).font(.headline)
                Spacer()
                Picker(L.text("顯示方式"), selection: $library.listView) {
                    Image(systemName: "square.grid.2x2").tag(false).accessibilityLabel(L.text("圖示"))
                    Image(systemName: "list.bullet").tag(true).accessibilityLabel(L.text("列表"))
                }.pickerStyle(.segmented).labelsHidden().frame(width: 76).controlSize(.small)
                Button { library.refresh(force: true) } label: { Image(systemName: "arrow.clockwise").frame(width: 28, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).disabled(library.loading).help(L.text("更新 App 清單"))
            }.padding(.horizontal, 18).padding(.vertical, 8)
            Divider().padding(.horizontal, 18)
            HStack(spacing: 0) {
                sidebar.frame(width: 152)
                Divider().padding(.vertical, 12)
                browser
            }
            Divider().padding(.horizontal, 18)
            HStack(spacing: 8) {
                if library.loading { ProgressView().controlSize(.mini) }
                Text(library.error.isEmpty ? (library.feedback.isEmpty ? L.text("拖動 App 到左側分類；分類可拖動排序，自訂分類可右鍵編輯。") : L.text(library.feedback)) : L.text(library.error))
                    .font(.system(size: 10)).foregroundStyle(library.error.isEmpty ? Color.secondary : .red).lineLimit(2)
                Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.vertical, 10)
        }
        .onAppear { library.refresh() }
        .onDisappear { library.isEditingCategory = false; library.isPreviewingSuggestions = false }
        .onChange(of: library.selectedCustomGroupID) { _, _ in library.selectFirst(query: store.query) }
        .onChange(of: library.isEditingCategory) { _, editing in if !editing { nameFocused = false } }
        .onChange(of: library.group) { _, _ in library.selectFirst(query: store.query) }
        .onChange(of: store.query) { _, _ in library.isPreviewingSuggestions = false; library.selectFirst(query: store.query) }
    }
    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 3) {
                Button { beginEditing(nil) } label: {
                    Label(L.text("新增分類"), systemImage: "folder.badge.plus").font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button { library.isPreviewingSuggestions.toggle(); library.isEditingCategory = false } label: {
                    Label(L.text("建議分類"), systemImage: "sparkles").font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider().padding(.vertical, 5)
                ForEach(library.orderedCategoryIDs, id: \.self) { id in
                    if let group = library.customGroups.first(where: { $0.id == id }) {
                        sidebarRow(id: group.id, title: group.name, symbol: group.symbol, count: library.items(query: store.query, custom: group.id).count, selected: library.selectedCustomGroupID == group.id) {
                            library.selectCustom(group.id)
                        }.contextMenu {
                            Button(L.text("編輯分類名稱與圖示")) { beginEditing(group) }
                            Button(L.text("刪除分類")) { library.deleteCategory(group.id) }
                        }
                    } else if let group = ApplicationGroup(rawValue: id) {
                        sidebarRow(id: group.rawValue, title: L.text(group.title), symbol: group.symbol, count: library.items(query: store.query, group: group).count, selected: library.selectedCustomGroupID == nil && library.group == group) { library.select(group) }
                    }
                }
            }.padding(10)
        }
    }
    private func sidebarRow(id: String, title: String, symbol: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 17)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                Text(String(count)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }.font(.system(size: 11, weight: selected ? .medium : .regular))
                .padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                .background(dropTargetID == id ? Color.accentColor.opacity(0.22) : selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).help(title)
            .overlay {
                AppLibraryDragSource(payload: "han-category:" + id, image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(), click: action,
                    acceptsDrop: { library.acceptsDrop($0, to: id) }, drop: { library.drop($0, to: id) }, targeted: { active in
                        if active { dropTargetID = id } else if dropTargetID == id { dropTargetID = nil }
                    }).accessibilityHidden(true)
            }
    }

    private func beginEditing(_ group: UserApplicationGroup?) {
        library.isPreviewingSuggestions = false; draftSymbol = group?.symbol ?? "folder"
        editingID = group?.id; draftName = group?.name ?? ""; library.clearCategoryError()
        gridFocused = false; library.isEditingCategory = true
        DispatchQueue.main.async { nameFocused = true }
    }
    private func saveCategory() {
        let saved = editingID.map { library.renameCategory($0, name: draftName, symbol: draftSymbol) } ?? (library.createCategory(draftName, symbol: draftSymbol) != nil)
        if saved { library.isEditingCategory = false; library.selectFirst(query: store.query) }
    }
    private var categoryEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L.text(editingID == nil ? "新增分類" : "重新命名分類")).font(.callout.weight(.medium))
            HStack {
                TextField(L.text("分類名稱"), text: $draftName).textFieldStyle(.roundedBorder).focused($nameFocused).onSubmit { saveCategory() }
                Button(L.text("儲存")) { saveCategory() }
                Button(L.text("取消")) { library.isEditingCategory = false }
            }
            HStack {
                Text(L.text("分類圖示")).font(.caption)
                Picker(L.text("分類圖示"), selection: $draftSymbol) {
                    ForEach(UserApplicationGroup.icons, id: \.self) { symbol in Image(systemName: symbol).tag(symbol) }
                }.labelsHidden().frame(width: 90)
                Image(systemName: draftSymbol).foregroundStyle(.secondary)
                Spacer()
            }
            if !library.categoryError.isEmpty { Text(L.text(library.categoryError)).font(.caption).foregroundStyle(.red) }
        }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 14)
    }
    private var suggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.text("依已安裝 App 建議分類")).font(.headline)
                Spacer()
                Button(L.text("返回 App")) { library.isPreviewingSuggestions = false }
            }
            Text(L.text("勾選分類，展開可查看全部 App。建立時會保留原本手動分類。" )).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ApplicationSuggestion.allCases.filter { !library.suggestedApps($0).isEmpty }) { suggestion in
                        let apps = library.suggestedApps(suggestion)
                        HStack(alignment: .top, spacing: 10) {
                            Toggle(L.text(suggestion.title), isOn: Binding(get: { selectedSuggestions.contains(suggestion.rawValue) }, set: { if $0 { selectedSuggestions.insert(suggestion.rawValue) } else { selectedSuggestions.remove(suggestion.rawValue) } }))
                                .labelsHidden().toggleStyle(.checkbox).padding(.top, 3)
                            DisclosureGroup(isExpanded: Binding(get: { expandedSuggestions.contains(suggestion.rawValue) }, set: { if $0 { expandedSuggestions.insert(suggestion.rawValue) } else { expandedSuggestions.remove(suggestion.rawValue) } })) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(apps) { app in
                                        HStack(spacing: 8) {
                                            Image(nsImage: AppIconCache.shared.icon(app.url.path)).resizable().scaledToFit().frame(width: 22, height: 22)
                                            Text(app.name).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10).padding(.top, 8)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Label(L.text(suggestion.title), systemImage: suggestion.symbol).font(.system(size: 14, weight: .medium)); Spacer(); Text(String(apps.count)).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
                                    if !expandedSuggestions.contains(suggestion.rawValue) {
                                        Text(apps.prefix(4).map(\.name).joined(separator: "、")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }.contentShape(Rectangle())
                            }
                        }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(.trailing, 4)
            }.frame(maxHeight: .infinity)
            Text(L.text("音訊外掛本體不屬於可啟動的 App；此處整理獨立程式與管理工具。" )).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(L.text("建立所選分類")) {
                library.applySuggestions(ApplicationSuggestion.allCases.filter { selectedSuggestions.contains($0.rawValue) })
                library.isPreviewingSuggestions = false
            }.buttonStyle(.borderedProminent).disabled(selectedSuggestions.isEmpty)
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var browser: some View {
        let apps = library.items(query: store.query)
        return VStack(alignment: .leading, spacing: 10) {
            if !library.isPreviewingSuggestions {
            HStack {
                Text(library.selectedTitle).font(.system(size: 12, weight: .semibold))
                Text(String(apps.count)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(L.text(library.selectedCustomGroupID == nil && library.group == .recent ? "依開啟時間排列" : !store.query.isEmpty && store.habits.enabled && !store.habits.history.entries.isEmpty ? "依相關性與開啟習慣排列" : "依名稱排列")).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 14)
            }
            if library.isEditingCategory { categoryEditor }
            if library.isPreviewingSuggestions { suggestionsPanel } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !store.appSettingsResults.isEmpty {
                            Text(L.text("系統設定")).font(.caption).foregroundStyle(.secondary)
                            ForEach(store.appSettingsResults) { item in
                                Button { store.selection = item.id; store.openSelection() } label: {
                                    HStack {
                                        Image(systemName: item.symbol).frame(width: 24)
                                        Text(L.text(item.title)).font(.callout)
                                        Spacer(); Image(systemName: "arrow.up.forward").font(.caption)
                                    }.padding(10).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        if library.loading && apps.isEmpty {
                            ProgressView(L.text("正在讀取 App 清單…")).frame(maxWidth: .infinity, minHeight: 170)
                        } else if apps.isEmpty && store.appSettingsResults.isEmpty {
                            VStack(spacing: 12) {
                                Text(L.text(library.selectedCustomGroupID != nil ? "把 App 拖到左側此分類，即可加入" : library.group == .pinned ? "右鍵 App 即可釘選常用項目" : library.group == .recent ? "從 Han 開啟 App 後會出現在這裡" : "沒有符合的 App"))
                                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                if library.selectedCustomGroupID != nil || library.group != .all { Button(L.text("查看全部 App")) { library.select(.all) } }
                                if !store.query.isEmpty { Button(L.text("清除搜尋，瀏覽全部")) { library.select(.all); store.query = "" } }
                            }.frame(maxWidth: .infinity, minHeight: 170)
                        } else if library.listView {
                            LazyVStack(spacing: 2) { ForEach(apps) { app in tile(app, list: true).id(app.id) } }
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                                ForEach(apps) { app in tile(app, list: false).id(app.id) }
                            }
                        }
                    }.padding(.horizontal, 14).padding(.bottom, 14)
                }.focusable().focused($gridFocused).focusEffectDisabled()
                    .onChange(of: library.selection) { _, id in if gridFocused, let id { proxy.scrollTo(id, anchor: .center) } }
            }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func tile(_ app: InstalledApplication, list: Bool) -> some View {
        AppLibraryTile(app: app, pinned: library.isPinned(app), selected: gridFocused && library.selection == app.id, list: list, query: store.query) {
            library.selection = app.id
            if library.open(app, query: store.query) { store.hideLauncher?() }
        }
        .contextMenu {
            Button(L.text(library.isPinned(app) ? "取消釘選" : "釘選 App")) { library.togglePin(app) }
            Menu(L.text("更改分類")) {
                ForEach(ApplicationGroup.assignable) { group in
                    Button { library.setCategory(app, group: group) } label: {
                        if library.categoryID(app) == group.rawValue { Label(L.text(group.title), systemImage: "checkmark") }
                        else { Text(L.text(group.title)) }
                    }
                }
                if !library.customGroups.isEmpty { Divider() }
                ForEach(library.customGroups) { group in
                    Button { library.setCategory(app, id: group.id) } label: {
                        if library.categoryID(app) == group.id { Label(group.name, systemImage: "checkmark") }
                        else { Text(group.name) }
                    }
                }
                Divider()
                Button(L.text("使用 App 原始分類")) { library.setCategory(app, group: nil) }
            }
            Button(L.text("在 Finder 顯示")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
    }
}

private struct AppLibraryTile: View {
    let app: InstalledApplication
    let pinned: Bool
    let selected: Bool
    let list: Bool
    let query: String
    let open: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: open) {
            Group {
                if list {
                    HStack(spacing: 12) {
                        icon.frame(width: 30, height: 30)
                        HighlightedText(text: app.name, query: query).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 10).frame(height: 44)
                } else {
                    VStack(spacing: 7) {
                        icon.frame(width: 44, height: 44)
                            .overlay(alignment: .bottomTrailing) { if pinned { Image(systemName: "pin.circle.fill").font(.system(size: 14)).symbolRenderingMode(.palette).foregroundStyle(Color.secondary, Color(nsColor: .windowBackgroundColor)) } }
                        HighlightedText(text: app.name, query: query).font(.system(size: 11)).multilineTextAlignment(.center).lineLimit(2).frame(height: 29, alignment: .top)
                    }.padding(.horizontal, 4).padding(.vertical, 9).frame(maxWidth: .infinity)
                }
            }.contentShape(Rectangle())
                .background(selected ? Color.accentColor.opacity(0.18) : hovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
            .overlay { AppLibraryDragSource(payload: "han-app:" + app.id, image: AppIconCache.shared.icon(app.url.path), click: open).accessibilityHidden(true) }
            .focusable(false).onHover { hovered = $0 }
            .help(app.name + "\n" + app.url.path).accessibilityLabel(app.name)
    }
    private var icon: some View { Image(nsImage: AppIconCache.shared.icon(app.url.path)).resizable().interpolation(.high).scaledToFit().accessibilityHidden(true) }
}

@MainActor private final class AppIconCache {
    static let shared = AppIconCache()
    private let images = NSCache<NSString, NSImage>()
    func icon(_ path: String) -> NSImage {
        if let cached = images.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path); images.setObject(icon, forKey: path as NSString); return icon
    }
}
