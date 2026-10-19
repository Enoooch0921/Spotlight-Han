import Foundation

public struct SearchItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let source: String
    public let excerpt: String
    public let applicationIdentifier: String?
    public var isApplication: Bool { url.pathExtension.lowercased() == "app" }

    public init(url: URL, name: String? = nil, source: String, excerpt: String = "", applicationIdentifier: String? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.source = source
        self.excerpt = excerpt
        self.applicationIdentifier = applicationIdentifier
    }
}

public struct IndexedDocument: Sendable {
    public let url: URL
    public let name: String
    public let text: String
    public let normalizedName: String
    public let normalizedText: String

    public init(url: URL, text: String) {
        self.url = url
        self.name = url.lastPathComponent
        self.text = text
        self.normalizedName = ChineseSearch.normalized(name)
        self.normalizedText = ChineseSearch.normalized(text)
    }

    public func match(query: String, mode: SearchMode) -> SearchItem? {
        let terms = ChineseSearch.terms(ChineseSearch.normalized(query))
        guard !terms.isEmpty else { return nil }
        let identifier = ModelSearch.key(query) != nil
        let nameMatch = identifier ? ModelSearch.matches(name, query: query) : terms.allSatisfy { normalizedName.contains($0) }
        let textMatch = identifier ? ModelSearch.matches(text, query: query) : terms.allSatisfy { normalizedText.contains($0) }
        switch mode {
        case .apps: guard url.pathExtension == "app", nameMatch else { return nil }
        case .names: guard nameMatch else { return nil }
        case .contents: guard textMatch else { return nil }
        case .videos: guard FileCatalog.videoExtensions.contains(url.pathExtension.lowercased()), nameMatch else { return nil }
        default: guard nameMatch || textMatch else { return nil }
        }
        // Show original text, even when the hit used a different script.
        let excerpt = textMatch ? SearchHighlight.excerpt(in: text, query: query, limit: 220) : ""
        return SearchItem(url: url, source: nameMatch && mode != .contents ? "資料夾・檔名" : "資料夾・內容", excerpt: excerpt)
    }
}
