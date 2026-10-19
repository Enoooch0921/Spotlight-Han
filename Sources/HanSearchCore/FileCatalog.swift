import Foundation

public struct CatalogEntry: Codable, Sendable {
    public let path: String
    public let name: String
    public let foldedName: String
    public let ext: String
    public let directory: Bool

    public init(url: URL, directory: Bool = false) {
        path = url.path
        name = url.lastPathComponent
        foldedName = ChineseSearch.normalized(name)
        ext = url.pathExtension.lowercased()
        self.directory = directory
    }
}

public struct CatalogSnapshot: Codable, Sendable {
    public let roots: [String]
    public let entries: [CatalogEntry]
    public let updated: Date
    public let unreadable: Int
    public let capped: Bool
}

public enum FileCatalog {
    public static let excludedDirectoryNames: Set<String> = ["node_modules", "Pods", "DerivedData", "venv", "__pycache__"]
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm", "mts", "m2ts", "mpg", "mpeg", "wmv", "flv", "3gp", "ts", "mxf"]
    public static var defaultRoots: [URL] {
        let fm = FileManager.default
        return [FileManager.SearchPathDirectory.downloadsDirectory, .moviesDirectory, .documentDirectory].compactMap {
            fm.urls(for: $0, in: .userDomainMask).first
        }
    }
    public static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.hansearch.mac/Filenames-v1.json")
    }

    public static func load(from url: URL = cacheURL) -> CatalogSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CatalogSnapshot.self, from: data)
    }

    public static func save(_ snapshot: CatalogSnapshot, to url: URL = cacheURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    public static func scan(roots: [URL], limit: Int = 500_000, progress: @Sendable (Int) -> Void = { _ in }) -> CatalogSnapshot {
        var entries: [CatalogEntry] = []
        var seen = Set<String>()
        var failures = 0
        var capped = false
        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { failures += 1; continue }
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in failures += 1; return true }) else { failures += 1; continue }
            for case let url as URL in files {
                if Task<Never, Never>.isCancelled { break }
                if entries.count >= limit { capped = true; break }
                guard seen.insert(url.path).inserted else { continue }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { failures += 1; continue }
                if values.isDirectory == true && excludedDirectoryNames.contains(url.lastPathComponent) { files.skipDescendants() }
                if values.isRegularFile == true || values.isDirectory == true {
                    entries.append(CatalogEntry(url: url, directory: values.isDirectory == true))
                    if entries.count % 1000 == 0 { progress(entries.count) }
                }
            }
            if capped { break }
        }
        return CatalogSnapshot(roots: roots.map(\.path), entries: entries, updated: Date(), unreadable: failures, capped: capped)
    }

    public static func search(_ entries: [CatalogEntry], query: String, mode: SearchMode, folder: URL? = nil) -> [SearchItem] {
        let terms = ChineseSearch.terms(ChineseSearch.normalized(query))
        guard !terms.isEmpty else { return [] }
        let prefix = folder.map { $0.path + "/" }
        let needle = ChineseSearch.normalized(query)
        let hits = entries.filter { entry in
            if let prefix, !entry.path.hasPrefix(prefix) { return false }
            if mode == .videos && (entry.directory || !videoExtensions.contains(entry.ext)) { return false }
            return terms.allSatisfy { entry.foldedName.contains($0) }
        }
        func score(_ entry: CatalogEntry) -> Int {
            (entry.foldedName == needle ? 100 : 0) + (entry.foldedName.hasPrefix(needle) ? 20 : 0)
        }
        return hits.sorted { a, b in
            let x = score(a), y = score(b)
            return x == y ? a.path < b.path : x > y
        }.prefix(2000).map { SearchItem(url: URL(fileURLWithPath: $0.path), source: mode == .videos ? "影片" : "檔名") }
    }
}
