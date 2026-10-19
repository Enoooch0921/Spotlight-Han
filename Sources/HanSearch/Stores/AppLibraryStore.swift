import Foundation
import AppKit
import Combine
import HanSearchCore

struct UserApplicationGroup: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var symbol: String
    init(id: String, name: String, symbol: String = "folder") { self.id = id; self.name = name; self.symbol = symbol }
    enum CodingKeys: String, CodingKey { case id, name, symbol }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id); name = try container.decode(String.self, forKey: .name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "folder"
    }
    static let icons = ["folder", "star", "heart", "briefcase", "doc.text", "film", "music.note", "waveform", "slider.horizontal.3", "mic", "camera", "paintbrush", "globe", "bubble.left.and.bubble.right", "cloud", "hammer", "gamecontroller", "book", "graduationcap", "house", "cross", "play.rectangle"]
}

@MainActor
final class AppLibraryStore: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []
    @Published var group: ApplicationGroup = .all
    @Published var selection: String?
    @Published var selectedCustomGroupID: String?
    @Published var isEditingCategory = false
    @Published var isPreviewingSuggestions = false
    @Published private(set) var customGroups: [UserApplicationGroup]
    @Published private(set) var categoryError = ""
    @Published private(set) var feedback = ""
    @Published private(set) var sidebarOrder: [String]
    @Published var listView: Bool { didSet { defaults.set(listView, forKey: "appLibrary.list.v1") } }
    @Published private(set) var loading = false
    @Published private(set) var error = ""
    @Published private(set) var pinned: Set<String>
    @Published private(set) var recent: [String]
    @Published private(set) var overrides: [String: String]
    private let defaults: UserDefaults
    private let loader: @Sendable () -> [InstalledApplication]
    var onOpened: ((InstalledApplication, String) -> Void)?
    var rankSearch: (([InstalledApplication], String) -> [InstalledApplication])?
    private let opener: (URL) -> Bool
    private var updated: Date?
    init(defaults: UserDefaults = .standard, loader: @escaping @Sendable () -> [InstalledApplication] = { ApplicationCatalog.scan() }, opener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.defaults = defaults; self.loader = loader; self.opener = opener
        pinned = Set(defaults.stringArray(forKey: "appLibrary.pinned.v1") ?? [])
        recent = defaults.stringArray(forKey: "appLibrary.recent.v1") ?? []
        overrides = defaults.dictionary(forKey: "appLibrary.groups.v1") as? [String: String] ?? [:]
        var seen = Set<String>()
        customGroups = (defaults.data(forKey: "appLibrary.customGroups.v1").flatMap { try? JSONDecoder().decode([UserApplicationGroup].self, from: $0) } ?? [])
            .filter { $0.id.hasPrefix("custom:") && !$0.name.isEmpty && seen.insert($0.id).inserted }
        sidebarOrder = defaults.stringArray(forKey: "appLibrary.sidebarOrder.v1") ?? []
        listView = defaults.bool(forKey: "appLibrary.list.v1")
    }
    func refresh(force: Bool = false) {
        guard !loading, force || updated == nil || Date().timeIntervalSince(updated!) > 30 else { return }
        loading = true
        let loader = loader
        Task {
            let apps = await Task.detached(priority: .utility, operation: loader).value
            applications = apps; updated = Date(); loading = false
            if !apps.contains(where: { $0.id == selection }) { selection = items(query: "").first?.id }
        }
    }
    func category(_ app: InstalledApplication) -> ApplicationGroup {
        if let group = ApplicationGroup(rawValue: categoryID(app)) { return group }
        return app.group
    }
    func categoryID(_ app: InstalledApplication) -> String {
        if let id = overrides[app.preferenceID], canAssign(id) { return id }
        return app.group.rawValue
    }
    var selectedTitle: String { customGroups.first { $0.id == selectedCustomGroupID }?.name ?? L.text(group.title) }
    func select(_ group: ApplicationGroup) { selectedCustomGroupID = nil; self.group = group }
    func selectCustom(_ id: String) { guard customGroups.contains(where: { $0.id == id }) else { return }; group = .all; selectedCustomGroupID = id }
    func isPinned(_ app: InstalledApplication) -> Bool { pinned.contains(app.preferenceID) }
    func items(query: String, group requested: ApplicationGroup? = nil, custom: String? = nil) -> [InstalledApplication] {
        let scope = requested ?? group
        let customID = custom ?? (requested == nil ? selectedCustomGroupID : nil)
        let terms = ChineseSearch.terms(ChineseSearch.normalized(query))
        let matches = applications.filter { app in
            guard app.matches(terms: terms) else { return false }
            if let customID { return categoryID(app) == customID }
            switch scope {
            case .all: return true
            case .pinned: return isPinned(app)
            case .recent: return recent.contains(app.preferenceID)
            case .system: return app.isSystemApplication
            default: return categoryID(app) == scope.rawValue
            }
        }
        let sorted = matches.sorted { a, b in
            if customID == nil && scope == .recent {
                let x = recent.firstIndex(of: a.preferenceID) ?? Int.max, y = recent.firstIndex(of: b.preferenceID) ?? Int.max
                if x != y { return x < y }
            }
            if !terms.isEmpty, customID != nil || scope != .recent {
                func relevance(_ app: InstalledApplication) -> Int {
                    let name = ChineseSearch.applicationKey(app.name), needle = ChineseSearch.applicationKey(query)
                    return name == needle ? 4 : ApplicationAliases.matches(query, aliases: app.aliases) ? 3 : name.hasPrefix(needle) ? 2 : name.contains(needle) ? 1 : 0
                }
                let x = relevance(a), y = relevance(b)
                if x != y { return x > y }
            }
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, customID != nil || scope != .recent { return rankSearch?(sorted, query) ?? sorted }
        return sorted
    }
    func setCategory(_ app: InstalledApplication, group: ApplicationGroup?) {
        if let group, ApplicationGroup.assignable.contains(group) { overrides[app.preferenceID] = group.rawValue }
        else { overrides[app.preferenceID] = nil }
        defaults.set(overrides, forKey: "appLibrary.groups.v1")
    }
    func setCategory(_ app: InstalledApplication, id: String) {
        guard canAssign(id) else { return }
        overrides[app.preferenceID] = id
        defaults.set(overrides, forKey: "appLibrary.groups.v1")
    }
    private func canAssign(_ id: String) -> Bool {
        ApplicationGroup.assignable.contains { $0.rawValue == id } || customGroups.contains { $0.id == id }
    }
    var orderedCategoryIDs: [String] {
        let available = customGroups.map(\.id) + ApplicationGroup.allCases.map(\.rawValue)
        var seen = Set<String>()
        return (sidebarOrder + available).filter { available.contains($0) && seen.insert($0).inserted }
    }
    func canDrop(to id: String) -> Bool { orderedCategoryIDs.contains(id) }
    func acceptsDrop(_ values: [String], to id: String) -> Bool {
        if values.count == 1, let value = values.first, value.hasPrefix("han-category:") {
            return orderedCategoryIDs.contains(String(value.dropFirst("han-category:".count))) && orderedCategoryIDs.contains(id)
        }
        return (id == ApplicationGroup.pinned.rawValue || canAssign(id)) && values.contains { value in
            value.hasPrefix("han-app:") && applications.contains { $0.id == String(value.dropFirst("han-app:".count)) }
        }
    }
    @discardableResult func drop(_ values: [String], to id: String) -> Bool {
        if let value = values.first, values.count == 1, value.hasPrefix("han-category:") {
            let sourceID = String(value.dropFirst("han-category:".count))
            var order = orderedCategoryIDs
            guard let source = order.firstIndex(of: sourceID), let target = order.firstIndex(of: id) else { return false }
            guard source != target else { return true }
            order.insert(order.remove(at: source), at: target)
            sidebarOrder = order; defaults.set(order, forKey: "appLibrary.sidebarOrder.v1")
            feedback = "已調整分類順序"; return true
        }
        guard id == ApplicationGroup.pinned.rawValue || canAssign(id) else { return false }
        let ids = Set(values.filter { $0.hasPrefix("han-app:") }.map { String($0.dropFirst("han-app:".count)) })
        let apps = applications.filter { ids.contains($0.id) }
        guard !apps.isEmpty else { return false }
        for app in apps {
            if id == ApplicationGroup.pinned.rawValue { pinned.insert(app.preferenceID) }
            else { overrides[app.preferenceID] = id }
        }
        defaults.set(pinned.sorted(), forKey: "appLibrary.pinned.v1")
        defaults.set(overrides, forKey: "appLibrary.groups.v1")
        let title = customGroups.first { $0.id == id }?.name ?? L.text(ApplicationGroup(rawValue: id)?.title ?? "其他")
        feedback = L.format("已移至「%@」", title); return true
    }
    @discardableResult func createCategory(_ name: String, symbol: String = "folder") -> UserApplicationGroup? {
        guard let name = validatedName(name, excluding: nil) else { return nil }
        let value = UserApplicationGroup(id: "custom:" + UUID().uuidString, name: name, symbol: UserApplicationGroup.icons.contains(symbol) ? symbol : "folder")
        customGroups.append(value); saveCustomGroups(); selectCustom(value.id); return value
    }
    @discardableResult func renameCategory(_ id: String, name: String, symbol: String? = nil) -> Bool {
        guard let index = customGroups.firstIndex(where: { $0.id == id }), let name = validatedName(name, excluding: id) else { return false }
        customGroups[index].name = name
        if let symbol, UserApplicationGroup.icons.contains(symbol) { customGroups[index].symbol = symbol }
        saveCustomGroups(); return true
    }
    func deleteCategory(_ id: String) {
        guard customGroups.contains(where: { $0.id == id }) else { return }
        customGroups.removeAll { $0.id == id }; sidebarOrder.removeAll { $0 == id }
        defaults.set(sidebarOrder, forKey: "appLibrary.sidebarOrder.v1")
        overrides = overrides.filter { $0.value != id }
        defaults.set(overrides, forKey: "appLibrary.groups.v1"); saveCustomGroups()
        if selectedCustomGroupID == id { select(.all) }
        feedback = "已刪除分類；App 已回到原始分類"
    }
    func suggestedApps(_ suggestion: ApplicationSuggestion) -> [InstalledApplication] { applications.filter { suggestion.matches($0) } }
    @discardableResult func applySuggestions(_ suggestions: [ApplicationSuggestion]) -> Int {
        var count = 0
        for suggestion in suggestions {
            let apps = suggestedApps(suggestion)
            guard !apps.isEmpty else { continue }
            let id = "custom:suggested." + suggestion.rawValue
            if !customGroups.contains(where: { $0.id == id }) {
                let base = L.text(suggestion.title)
                var name = base, suffix = 2
                while customGroups.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) { name = base + " (\(suffix))"; suffix += 1 }
                customGroups.append(UserApplicationGroup(id: id, name: name, symbol: suggestion.symbol))
            }
            for app in apps where overrides[app.preferenceID] == nil {
                overrides[app.preferenceID] = id; count += 1
            }
        }
        saveCustomGroups(); defaults.set(overrides, forKey: "appLibrary.groups.v1")
        feedback = L.format("已整理 %@ 個 App；保留原本手動分類", String(count))
        return count
    }
    func clearCategoryError() { categoryError = "" }
    private func validatedName(_ input: String, excluding: String?) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 30 else { categoryError = "分類名稱需為 1–30 個字"; return nil }
        let names = customGroups.filter { $0.id != excluding }.map(\.name) + ApplicationGroup.allCases.flatMap { [$0.title, L.text($0.title)] }
        guard !names.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { categoryError = "已有同名分類，請換個名稱"; return nil }
        categoryError = ""; return name
    }
    private func saveCustomGroups() { if let data = try? JSONEncoder().encode(customGroups) { defaults.set(data, forKey: "appLibrary.customGroups.v1") } }
    func togglePin(_ app: InstalledApplication) {
        if !pinned.insert(app.preferenceID).inserted { pinned.remove(app.preferenceID) }
        defaults.set(pinned.sorted(), forKey: "appLibrary.pinned.v1")
    }
    @discardableResult func open(_ app: InstalledApplication, query: String = "") -> Bool {
        guard opener(app.url) else { error = "無法開啟 App；可能已移動或刪除，請更新清單。"; return false }
        recordOpened(app); onOpened?(app, query)
        return true
    }
    func recordOpened(_ app: InstalledApplication) {
        error = ""; recent.removeAll { $0 == app.preferenceID }; recent.insert(app.preferenceID, at: 0)
        recent = Array(recent.prefix(20)); defaults.set(recent, forKey: "appLibrary.recent.v1")
    }
    func selectFirst(query: String) { selection = items(query: query).first?.id }
    func move(_ offset: Int, query: String) {
        let apps = items(query: query); guard !apps.isEmpty else { selection = nil; return }
        let index = apps.firstIndex { $0.id == selection } ?? (offset > 0 ? -offset : 0)
        selection = apps[min(max(index + offset, 0), apps.count - 1)].id
    }
    func selected(query: String) -> InstalledApplication? {
        let apps = items(query: query)
        return apps.first { $0.id == selection } ?? apps.first
    }
}
