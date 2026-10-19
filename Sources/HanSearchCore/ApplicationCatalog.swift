import Foundation

public enum ApplicationGroup: String, CaseIterable, Sendable, Identifiable {
    case all, pinned, recent, system, work, creative, network, development, utilities, games, other
    public var id: String { rawValue }
    public static var assignable: [Self] { [.work, .creative, .network, .development, .utilities, .games, .other] }
    public var title: String {
        switch self {
        case .all: return "全部 App"
        case .pinned: return "已釘選"
        case .recent: return "最近開啟"
        case .system: return "系統內建 App"
        case .work: return "工作與學習"
        case .creative: return "影音與設計"
        case .network: return "通訊與網路"
        case .development: return "開發工具"
        case .utilities: return "系統與工具"
        case .games: return "遊戲"
        case .other: return "其他"
        }
    }
    public var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .pinned: return "pin"
        case .recent: return "clock"
        case .system: return "apple.logo"
        case .work: return "doc.text"
        case .creative: return "photo.on.rectangle"
        case .network: return "network"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .utilities: return "wrench.and.screwdriver"
        case .games: return "gamecontroller"
        case .other: return "square.dashed"
        }
    }
    public static func declared(_ category: String?) -> Self {
        let value = category?.lowercased() ?? ""
        if value.hasPrefix("public.app-category."), value == "public.app-category.games" || value.hasSuffix("-games") { return .games }
        switch value {
        case "public.app-category.business", "public.app-category.productivity", "public.app-category.education", "public.app-category.reference", "public.app-category.finance": return .work
        case "public.app-category.graphics-design", "public.app-category.photography", "public.app-category.video", "public.app-category.music", "public.app-category.entertainment": return .creative
        case "public.app-category.social-networking", "public.app-category.news": return .network
        case "public.app-category.developer-tools": return .development
        case "public.app-category.utilities", "public.app-category.weather": return .utilities
        default: return .other
        }
    }
}

public struct InstalledApplication: Identifiable, Sendable, Hashable {
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let declaredCategory: String?
    public var id: String { url.path }
    public var isSystemApplication: Bool { url.path.hasPrefix("/System/Applications/") || bundleID == "com.apple.Safari" }
    public var preferenceID: String { if let bundleID, !bundleID.isEmpty { return bundleID }; return id }
    public var group: ApplicationGroup { ApplicationGroup.declared(declaredCategory) }
    private let folded: String
    public init(url: URL, name: String, bundleID: String? = nil, declaredCategory: String? = nil) {
        self.url = url; self.name = name; self.bundleID = bundleID; self.declaredCategory = declaredCategory
        folded = ChineseSearch.normalized(name + " " + url.lastPathComponent + " " + (bundleID ?? ""))
    }
    public func matches(_ query: String) -> Bool {
        matches(terms: ChineseSearch.terms(ChineseSearch.normalized(query)))
    }
    public func matches(terms: [String]) -> Bool { terms.allSatisfy { folded.contains($0) } }
    public var searchItem: SearchItem { SearchItem(url: url, name: name, source: "App・繁簡比對") }
}

public enum ApplicationCatalog {
    /// Only conventional application folders. Packages are not traversed, so helper
    /// apps embedded in a main app do not clutter the browsing list.
    public static func scan(roots: [URL]? = nil) -> [InstalledApplication] {
        let roots = roots ?? [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var apps: [String: InstalledApplication] = [:]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url) else { continue }
                var name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.localizedInfoDictionary?["CFBundleName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                if name == "AudioPluginHost", bundle.bundleIdentifier?.lowercased().hasPrefix("com.wavesaudio.") == true {
                    name = url.deletingPathExtension().lastPathComponent
                }
                let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
                apps[resolved] = InstalledApplication(url: URL(fileURLWithPath: resolved), name: name, bundleID: bundle.bundleIdentifier, declaredCategory: bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String)
            }
        }
        return apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
