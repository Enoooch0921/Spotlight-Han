import Foundation

/// File-picker grants are persisted as security-scoped bookmarks, never inferred by probing protected folders.
@MainActor
final class FileAccessBookmarks {
    private let defaults: UserDefaults
    private var renamed: [String: String] = [:]
    private let key = "folderAccessBookmarks.v1"
    private var bookmarks: [String: Data] = [:]
    private var active: [String: URL] = [:]
    private var scoped = Set<String>()
    var urls: [URL] { Array(active.values).sorted { $0.path < $1.path } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key), let stored = try? JSONDecoder().decode([String: Data].self, from: data) else { return }
        for (oldPath, bookmark) in stored {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            if url.startAccessingSecurityScopedResource() { scoped.insert(url.path) }
            active[url.path] = url
            renamed[URL(fileURLWithPath: oldPath).resolvingSymlinksInPath().path] = url.path
            bookmarks[url.path] = stale ? ((try? Self.bookmark(url)) ?? bookmark) : bookmark
        }
        persist()
    }
    func resolvedIndexURL(_ originalPath: String) -> URL {
        let path = URL(fileURLWithPath: originalPath).resolvingSymlinksInPath().path
        let match = renamed.keys.sorted { $0.count > $1.count }.first { path == $0 || path.hasPrefix($0 + "/") }
        guard let match, let replacement = renamed[match] else { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: replacement + String(path.dropFirst(match.count)))
    }
    func add(_ urls: [URL]) throws {
        for url in urls {
            let data = try Self.bookmark(url)
            if active[url.path] == nil, url.startAccessingSecurityScopedResource() { scoped.insert(url.path) }
            active[url.path] = url; bookmarks[url.path] = data
        }
        persist()
    }
    private static func bookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func clear() {
        for path in scoped { active[path]?.stopAccessingSecurityScopedResource() }
        active = [:]; scoped = []; bookmarks = [:]; renamed = [:]; defaults.removeObject(forKey: key)
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(bookmarks) { defaults.set(data, forKey: key) }
    }
}
