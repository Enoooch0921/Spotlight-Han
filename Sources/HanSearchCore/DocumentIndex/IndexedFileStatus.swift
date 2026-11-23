import Foundation

public enum IndexedFileStatus: Sendable, Equatable {
    case outside, excluded, unsupported, missing
    case recorded(hasText: Bool, reason: DocumentReadReason?, pagesRead: Int, changed: Bool)
}

extension PersistentDocumentIndex {
    public func status(of input: URL, roots: [URL]) throws -> IndexedFileStatus {
        let url = input.standardizedFileURL.resolvingSymlinksInPath()
        let ext = url.pathExtension.lowercased()
        guard SearchService.documentExtensions.contains(ext) || VisionTextRecognizer.imageExtensions.contains(ext) else { return .unsupported }
        let matchingRoots = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }.filter { url.path.hasPrefix($0.path + "/") }
        guard !matchingRoots.isEmpty else { return .outside }
        let eligible = matchingRoots.contains { root in
            let parts = url.path.dropFirst(root.path.count + 1).split(separator: "/").map(String.init)
            return !parts.contains(where: { $0.hasPrefix(".") }) && Self.excludedDirectories.isDisjoint(with: parts.dropLast())
        }
        guard eligible else { return .excluded }
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return .missing }
        let db = try IndexDatabase(url: databaseURL, limit: limitBytes, readOnly: true)
        guard let row = try db.rows("SELECT length(body)>0, reason, modified, size FROM documents WHERE path=?", [url.path]).first else { return .missing }
        var pages = 0
        if try db.rows("PRAGMA user_version").first?.first == "2" {
            pages = Int(try db.rows("SELECT count(*) FROM document_pages WHERE path=? AND page>0", [url.path])[0][0]) ?? 0
        }
        let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let changed = attributes?.contentModificationDate.flatMap { date in Double(row[2]).map { abs($0 - date.timeIntervalSince1970) > 0.001 } } == true
            || attributes?.fileSize.map { String($0) != row[3] } == true
        return .recorded(hasText: row[0] == "1", reason: DocumentReadReason(rawValue: row[1]), pagesRead: pages, changed: changed)
    }
}
