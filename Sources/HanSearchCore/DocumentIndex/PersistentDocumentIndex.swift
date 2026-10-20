import Foundation

public struct DocumentIndexSnapshot: Sendable {
    public var files = 0, searchable = 0, examined = 0, extracted = 0, reused = 0, unsupported = 0
    public var issues: [DocumentReadIssue] = []
    public var unfinished = 0, capped = false
    public var bytes: Int64 = 0
    public var updated: Date?
    public init() {}
}

/// Persistent local full-text search. Does not call mdfind, mdls or Spotlight importers.
public struct PersistentDocumentIndex: Sendable {
    public let databaseURL: URL
    public let limitBytes: Int64
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spotlight Han/Index/Documents-v1.sqlite")
    }
    public init(databaseURL: URL = Self.defaultURL, limitBytes: Int64 = 500_000_000) {
        self.databaseURL = databaseURL; self.limitBytes = max(131_072, limitBytes)
    }
    public static let excludedDirectories: Set<String> = ["Library", "Caches", "node_modules", "Pods", "DerivedData", "venv", "__pycache__", "build"]
    public func contains(_ path: String, roots: [URL]) -> Bool {
        roots.contains { path.hasPrefix($0.path + "/") }
    }
    public func statistics(roots: [URL]) throws -> DocumentIndexSnapshot {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return DocumentIndexSnapshot() }
        return try snapshot(IndexDatabase(url: databaseURL, limit: limitBytes, readOnly: true), roots: roots)
    }
    private func predicate(_ roots: [URL]) -> (String, [String?]) {
        let paths = Array(Set(roots.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })).sorted()
        return (paths.isEmpty ? "0" : paths.map { _ in "instr(path, ?) = 1" }.joined(separator: " OR "), paths.map { $0 + "/" })
    }
    private func snapshot(_ db: IndexDatabase, roots: [URL]) throws -> DocumentIndexSnapshot {
        let (scope, bindings) = predicate(roots)
        var result = DocumentIndexSnapshot()
        let counts = try db.rows("SELECT count(*), coalesce(sum(length(body)>0),0), coalesce(sum(reason IS NOT NULL),0) FROM documents WHERE \(scope)", bindings).first!
        result.files = Int(counts[0]) ?? 0; result.searchable = Int(counts[1]) ?? 0; result.unfinished = Int(counts[2]) ?? 0
        result.issues = try db.rows("SELECT path, reason FROM documents WHERE (\(scope)) AND reason IS NOT NULL ORDER BY path LIMIT 200", bindings).compactMap {
            guard let reason = DocumentReadReason(rawValue: $0[1]) else { return nil }
            return DocumentReadIssue(url: URL(fileURLWithPath: $0[0]), reason: reason)
        }
        let roots = Set(roots.map { $0.resolvingSymlinksInPath().path })
        let completed = try db.rows("SELECT root, completed FROM scans").filter { roots.contains($0[0]) }
        result.capped = try db.rows("SELECT root FROM scan_state WHERE incomplete=1").contains { roots.contains($0[0]) }
        if completed.count == roots.count, let oldest = completed.compactMap({ Double($0[1]) }).min() { result.updated = Date(timeIntervalSince1970: oldest) }
        result.bytes = diskBytes
        return result
    }
    public var diskBytes: Int64 {
        ["", "-wal", "-shm"].reduce(0) { value, suffix in
            value + ((try? FileManager.default.attributesOfItem(atPath: databaseURL.path + suffix)[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }
    public func search(query: String, roots: [URL], mode: SearchMode = .all, cancellation: ProcessCancellation? = nil, limit: Int = 200) throws -> SearchResponse {
        guard !roots.isEmpty, FileManager.default.fileExists(atPath: databaseURL.path), let expression = DocumentIndexTerms.expression(String(query.prefix(200))) else { return SearchResponse(items: []) }
        let db = try IndexDatabase(url: databaseURL, limit: limitBytes, readOnly: true)
        let (scope, bindings) = predicate(roots)
        // Stream through candidate pages. False gram intersections must not consume the result cap.
        var found: [SearchItem] = [], offset = 0
        while true {
            if cancellation?.isCancelled == true { throw CancellationError() }
            let rows = try db.rows("SELECT path, body FROM documents WHERE rowid IN (SELECT rowid FROM document_terms WHERE document_terms MATCH ?) AND (\(scope)) ORDER BY path LIMIT 8 OFFSET ?", [expression] + bindings + [String(offset)])
            if rows.isEmpty { break }
            for row in rows {
                if cancellation?.isCancelled == true { throw CancellationError() }
                let url = URL(fileURLWithPath: row[0])
                guard FileManager.default.isReadableFile(atPath: url.path), let item = IndexedDocument(url: url, text: row[1]).match(query: query, mode: mode) else { continue }
                found.append(SearchItem(url: url, source: item.excerpt.isEmpty ? "Han 索引・檔名" : "Han 索引・內文", excerpt: item.excerpt))
                if found.count > limit { return SearchResponse(items: Array(found.prefix(limit)), truncated: true) }
            }
            offset += rows.count
        }
        return SearchResponse(items: found)
    }
    /// Incremental extraction, bounded writes and per-file transactions survive interruption.
    public func synchronize(roots: [URL], cancellation: ProcessCancellation = ProcessCancellation(),
                            progress: @Sendable (DocumentIndexSnapshot) -> Void = { _ in }) throws -> DocumentIndexSnapshot {
        let writeLock = try IndexWriteLock(url: databaseURL)
        defer { _fixLifetime(writeLock) }
        let db = try IndexDatabase(url: databaseURL, limit: limitBytes)
        let fm = FileManager.default
        var report = DocumentIndexSnapshot()
        var seen = Set<String>()
        let generation = UUID().uuidString
        let indexPath = databaseURL.deletingLastPathComponent().resolvingSymlinksInPath().path
        for original in roots {
            let root = original.resolvingSymlinksInPath()
            guard !cancellation.isCancelled else { throw CancellationError() }
            try db.execute("INSERT OR REPLACE INTO scan_state(root,incomplete) VALUES(?,1)", [root.path])
            var failedEnumeration = false
            guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in failedEnumeration = true; return true }) else { throw IndexDatabaseError.message("無法讀取已選的文件資料夾") }
            for case let url as URL in files {
                guard !cancellation.isCancelled else { throw CancellationError() }
                let observedPath = url.resolvingSymlinksInPath().path
                if observedPath == indexPath || observedPath.hasPrefix(indexPath + "/") { files.skipDescendants(); continue }
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) else { failedEnumeration = true; continue }
                if v.isSymbolicLink == true { files.skipDescendants(); continue }
                if v.isDirectory == true { if Self.excludedDirectories.contains(url.lastPathComponent) { files.skipDescendants() }; continue }
                let url = url.standardizedFileURL.resolvingSymlinksInPath()
                let path = url.path
                guard v.isRegularFile == true, seen.insert(path).inserted else { continue }
                report.examined += 1
                if report.examined > 100_000 { report.capped = true; break }
                guard SearchService.documentExtensions.contains(url.pathExtension.lowercased()) else { report.unsupported += 1; continue }
                let old = try db.rows("SELECT rowid, modified, size, reason, name, body FROM documents WHERE path=?", [path]).first
                let modified = v.contentModificationDate?.timeIntervalSince1970
                let unchanged = old != nil && modified != nil && abs((Double(old![1]) ?? 0) - modified!) < 0.00001 && old![2] == String(v.fileSize ?? 0) && old![3].isEmpty
                if unchanged {
                    try db.execute("UPDATE documents SET generation=? WHERE path=?", [generation, path]); report.reused += 1
                } else {
                    var body = "", reason: DocumentReadReason?
                    if (v.fileSize ?? 0) > 20_000_000 { reason = .tooLarge }
                    else if v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus == .notDownloaded { reason = .cloudOnly }
                    else {
                        do {
                            body = try IndexedDocumentText.read(url, cancellation: cancellation)
                            if body.utf8.count > 8_000_000 { body = ""; reason = .indexFileTextLimit }
                            else if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reason = .noText }
                        } catch is CancellationError { throw CancellationError() }
                        catch { reason = error as? DocumentReadReason ?? .readFailed }
                    }
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    let tokens = DocumentIndexTerms.tokens(name: url.lastPathComponent, body: body, cancellation: cancellation)
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    let free = (try? fm.attributesOfFileSystem(forPath: databaseURL.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? Int64.max
                    // Include WAL headroom; the SQLite page limit is the final hard guard.
                    if diskBytes + Int64(tokens.utf8.count * 2 + body.utf8.count + 65_536) > limitBytes || free < 128_000_000 { report.capped = true; break }
                    do {
                        try db.transaction {
                            if let old { try eraseTerms(db, row: old, idIndex: 0, nameIndex: 4, bodyIndex: 5) }
                            try db.execute("INSERT INTO documents(path,name,body,modified,created,size,reason,generation) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET name=excluded.name,body=excluded.body,modified=excluded.modified,created=excluded.created,size=excluded.size,reason=excluded.reason,generation=excluded.generation", [path,url.lastPathComponent,body,modified.map { String($0) },v.creationDate?.timeIntervalSince1970.description,String(v.fileSize ?? 0),reason?.rawValue,generation])
                            let id = try db.rows("SELECT rowid FROM documents WHERE path=?", [path])[0][0]
                            try db.execute("INSERT INTO document_terms(rowid,tokens) VALUES(?,?)", [id,tokens])
                        }
                    } catch IndexDatabaseError.capacity { report.capped = true; break }
                    report.extracted += 1
                }
                if (report.extracted + report.reused) % 20 == 0 { try db.execute("PRAGMA wal_checkpoint(PASSIVE)"); progress(report) }
            }
            guard !cancellation.isCancelled else { throw CancellationError() }
            // No deletion sweep after an incomplete walk: unreadable subtrees may still exist.
            if !failedEnumeration && !report.capped {
                while true {
                    if cancellation.isCancelled { throw CancellationError() }
                    let stale = try db.rows("SELECT rowid,name,body FROM documents WHERE instr(path,?)=1 AND generation<>? LIMIT 8", [root.path + "/", generation])
                    if stale.isEmpty { break }
                    try db.transaction {
                        for row in stale { try eraseTerms(db, row: row); try db.execute("DELETE FROM documents WHERE rowid=?", [row[0]]) }
                    }
                }
                try db.transaction {
                    try db.execute("INSERT OR REPLACE INTO scans(root,completed) VALUES(?,?)", [root.path,String(Date().timeIntervalSince1970)])
                    try db.execute("INSERT OR REPLACE INTO scan_state(root,incomplete) VALUES(?,0)", [root.path])
                }
            } else { report.capped = true }
            if report.capped { break }
        }
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        var final = try snapshot(db, roots: roots)
        final.examined = report.examined; final.extracted = report.extracted; final.reused = report.reused
        final.unsupported = report.unsupported; final.capped = report.capped
        progress(final)
        return final
    }
    private func eraseTerms(_ db: IndexDatabase, row: [String], idIndex: Int = 0, nameIndex: Int = 1, bodyIndex: Int = 2) throws {
        try db.execute("INSERT INTO document_terms(document_terms,rowid,tokens) VALUES('delete',?,?)", [row[idIndex], DocumentIndexTerms.tokens(name: row[nameIndex], body: row[bodyIndex])])
    }
    /// Keep only explicitly configured roots. Called after user removes a scope.
    public func retain(roots: [URL]) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
        let writeLock = try IndexWriteLock(url: databaseURL)
        defer { _fixLifetime(writeLock) }
        if roots.isEmpty {
            for suffix in ["-wal", "-shm", ""] {
                let url = URL(fileURLWithPath: databaseURL.path + suffix)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            return
        }
        let db = try IndexDatabase(url: databaseURL, limit: limitBytes)
        let (scope, bindings) = predicate(roots)
        try db.transaction {
            while true {
                let batch = try db.rows("SELECT rowid,name,body FROM documents WHERE NOT (\(scope)) LIMIT 8", bindings)
                if batch.isEmpty { break }
                for row in batch { try eraseTerms(db, row: row); try db.execute("DELETE FROM documents WHERE rowid=?", [row[0]]) }
            }
            for row in try db.rows("SELECT root FROM scans") where !roots.contains(where: { $0.resolvingSymlinksInPath().path == row[0] }) { try db.execute("DELETE FROM scans WHERE root=?", [row[0]]) }
            for row in try db.rows("SELECT root FROM scan_state") where !roots.contains(where: { $0.resolvingSymlinksInPath().path == row[0] }) { try db.execute("DELETE FROM scan_state WHERE root=?", [row[0]]) }
        }
        try db.execute("INSERT INTO document_terms(document_terms) VALUES('optimize')")
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try db.execute("VACUUM")
    }
}
