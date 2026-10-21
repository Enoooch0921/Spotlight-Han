import Foundation

public struct DocumentIndexSnapshot: Sendable {
    public var files = 0, searchable = 0, examined = 0, extracted = 0, reused = 0, unsupported = 0
    public var issues: [DocumentReadIssue] = []
    public var unfinished = 0, capped = false
    public var ocrPages = 0, ocrFiles = 0, pendingOCR = 0, deferredOCR = 0
    public var currentFile = "", currentPage = 0, totalPages = 0
    public var recognizing = false
    public var bytes: Int64 = 0
    public var updated: Date?
    public init() {}
}

/// Persistent local full-text search. Does not call mdfind, mdls or Spotlight importers.
public struct PersistentDocumentIndex: Sendable {
    public let databaseURL: URL
    public let limitBytes: Int64
    public let ocrEnabled: Bool
    public let ocrScheduler: OCRWorkScheduler?
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spotlight Han/Index/Documents-v1.sqlite")
    }
    public init(databaseURL: URL = Self.defaultURL, limitBytes: Int64 = 500_000_000, ocrEnabled: Bool = true, ocrScheduler: OCRWorkScheduler? = nil) {
        self.databaseURL = databaseURL; self.limitBytes = max(131_072, limitBytes); self.ocrEnabled = ocrEnabled; self.ocrScheduler = ocrScheduler
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
        result.pendingOCR = Int(try db.rows("SELECT count(*) FROM documents WHERE (\(scope)) AND reason=?", bindings + [DocumentReadReason.ocrPending.rawValue])[0][0]) ?? 0
        result.deferredOCR = Int(try db.rows("SELECT count(*) FROM documents WHERE (\(scope)) AND reason=?", bindings + [DocumentReadReason.ocrDeferred.rawValue])[0][0]) ?? 0
        if try db.rows("PRAGMA user_version")[0][0] == "2" {
            let counts = try db.rows("SELECT count(*),count(DISTINCT path) FROM document_pages WHERE ocr=1 AND (\(scope))", bindings)[0]
            result.ocrPages = Int(counts[0]) ?? 0; result.ocrFiles = Int(counts[1]) ?? 0
        }
        result.bytes = diskBytes
        return result
    }
    public var diskBytes: Int64 {
        ["", "-wal", "-shm"].reduce(0) { value, suffix in
            value + ((try? FileManager.default.attributesOfItem(atPath: databaseURL.path + suffix)[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }
    public func search(query: String, roots: [URL], mode: SearchMode = .all, cancellation: ProcessCancellation? = nil, limit: Int = 200) throws -> SearchResponse {
        guard limit > 0 else { return SearchResponse(items: []) }
        let primary = try literalSearch(query: query, roots: roots, mode: mode, cancellation: cancellation, limit: limit)
        var items = primary.items, truncated = primary.truncated, seen = Set(primary.items.map(\.id))
        for alternative in TaiwanVocabulary.alternatives(for: query) {
            if cancellation?.isCancelled == true { throw CancellationError() }
            // Primary results always get the entire cap first.
            guard items.count < limit else { break }
            let response = try literalSearch(query: alternative.query, roots: roots, mode: mode, cancellation: cancellation, limit: limit)
            truncated = truncated || response.truncated
            for item in response.items where seen.insert(item.id).inserted {
                if items.count == limit { truncated = true; break }
                items.append(item.supplemented(by: alternative))
            }
        }
        return SearchResponse(items: items, truncated: truncated)
    }
    private func literalSearch(query: String, roots: [URL], mode: SearchMode, cancellation: ProcessCancellation?, limit: Int) throws -> SearchResponse {
        guard !roots.isEmpty, FileManager.default.fileExists(atPath: databaseURL.path), let expression = DocumentIndexTerms.expression(String(query.prefix(200))) else { return SearchResponse(items: []) }
        let db = try IndexDatabase(url: databaseURL, limit: limitBytes, readOnly: true)
        let (scope, bindings) = predicate(roots)
        let hasPages = try db.rows("PRAGMA user_version")[0][0] == "2"
        // Stream through candidate pages. False gram intersections must not consume the result cap.
        var found: [SearchItem] = [], offset = 0
        while true {
            if cancellation?.isCancelled == true { throw CancellationError() }
            let rows = try db.rows("SELECT path, body FROM documents WHERE rowid IN (SELECT rowid FROM document_terms WHERE document_terms MATCH ?) AND (\(scope)) ORDER BY path LIMIT 8 OFFSET ?", [expression] + bindings + [String(offset)])
            if rows.isEmpty { break }
            for row in rows {
                if cancellation?.isCancelled == true { throw CancellationError() }
                let url = URL(fileURLWithPath: row[0])
                guard FileManager.default.isReadableFile(atPath: url.path), let item = IndexedDocument(url: url, text: row[1]).match(query: query, mode: mode, allowVocabulary: false) else { continue }
                let pages = hasPages && !item.excerpt.isEmpty ? try loadPages(db, path: url.path) : []
                let matching = pages.filter { IndexedDocument(url: url, text: $0.text).match(query: query, mode: .contents, allowVocabulary: false) != nil }
                let locations = matching.isEmpty ? pages.filter { !SearchHighlight.ranges(in: $0.text, query: query).isEmpty } : matching
                let first = matching.first
                let snippet = first.map { SearchHighlight.excerpt(in: $0.text, query: query, limit: 220) } ?? item.excerpt
                let ocr = locations.contains(where: \.isOCR)
                found.append(SearchItem(url: url, source: item.excerpt.isEmpty ? "Han 索引・檔名" : ocr ? "Han 索引・OCR" : "Han 索引・內文", excerpt: snippet,
                    matchPages: url.pathExtension.lowercased() == "pdf" ? Array(locations.filter { $0.number > 0 }.prefix(5).map(\.number)) : [], isOCR: ocr))
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
                guard SearchService.documentExtensions.contains(url.pathExtension.lowercased()) || VisionTextRecognizer.imageExtensions.contains(url.pathExtension.lowercased()) else { report.unsupported += 1; continue }
                let old = try db.rows("SELECT rowid, modified, size, reason, name, body, extraction FROM documents WHERE path=?", [path]).first
                let modified = v.contentModificationDate?.timeIntervalSince1970
                let visual = url.pathExtension.lowercased() == "pdf" || VisionTextRecognizer.imageExtensions.contains(url.pathExtension.lowercased())
                let extractionVersion = visual ? (ocrEnabled ? 2 : 1) : 0
                let sameFile = old != nil && modified != nil && abs((Double(old![1]) ?? 0) - modified!) < 0.00001 && old![2] == String(v.fileSize ?? 0) && old![6] == String(extractionVersion)
                let local = !CloudFileAvailability.needsDownload(isUbiquitous: v.isUbiquitousItem == true, status: v.ubiquitousItemDownloadingStatus)
                let unchanged = sameFile && local && (old![3].isEmpty || [DocumentReadReason.noText.rawValue, DocumentReadReason.ocrDisabled.rawValue].contains(old![3]))
                if unchanged {
                    try db.execute("UPDATE documents SET generation=? WHERE path=?", [generation, path]); report.reused += 1
                } else {
                    var body = "", reason: DocumentReadReason?
                    var pages: [IndexedPage] = []
                    if (v.fileSize ?? 0) > (visual && ocrEnabled ? 100_000_000 : 20_000_000) { reason = visual && ocrEnabled ? .ocrFileTooLarge : .tooLarge }
                    else if !local { reason = .cloudOnly }
                    else {
                        do {
                            let cached = sameFile && [DocumentReadReason.ocrPending.rawValue, DocumentReadReason.ocrDeferred.rawValue].contains(old?[3] ?? "") ? try loadPages(db, path: path) : []
                            let extraction = try DocumentExtraction.read(url, cached: cached, ocrEnabled: ocrEnabled, scheduler: ocrScheduler, cancellation: cancellation) { page, count, recognizing in
                                report.currentFile = url.lastPathComponent; report.currentPage = page; report.totalPages = count; report.recognizing = recognizing
                                if recognizing || page == 1 || page == count || page % 20 == 0 { progress(report) }
                            }
                            pages = extraction.pages; body = extraction.text; reason = extraction.reason
                            if body.utf8.count > 8_000_000 { body = ""; pages = []; reason = .indexFileTextLimit }
                            else if reason == nil && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !pages.contains(where: \.isOCR) { reason = .noText }
                        } catch is CancellationError { throw CancellationError() }
                        catch { reason = error as? DocumentReadReason ?? .readFailed }
                    }
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    let tokens = DocumentIndexTerms.tokens(name: url.lastPathComponent, body: body, cancellation: cancellation)
                    guard !cancellation.isCancelled else { throw CancellationError() }
                    let free = (try? fm.attributesOfFileSystem(forPath: databaseURL.deletingLastPathComponent().path)[.systemFreeSize] as? NSNumber)?.int64Value ?? Int64.max
                    // Include WAL headroom; the SQLite page limit is the final hard guard.
                    if diskBytes + Int64(tokens.utf8.count * 2 + body.utf8.count * 2 + pages.count * 200 + 65_536) > limitBytes || free < 128_000_000 { report.capped = true; break }
                    do {
                        try db.transaction {
                            if let old { try eraseTerms(db, row: old, idIndex: 0, nameIndex: 4, bodyIndex: 5) }
                            try db.execute("INSERT INTO documents(path,name,body,modified,created,size,reason,generation,extraction) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET name=excluded.name,body=excluded.body,modified=excluded.modified,created=excluded.created,size=excluded.size,reason=excluded.reason,generation=excluded.generation,extraction=excluded.extraction", [path,url.lastPathComponent,body,modified.map { String($0) },v.creationDate?.timeIntervalSince1970.description,String(v.fileSize ?? 0),reason?.rawValue,generation,String(extractionVersion)])
                            try db.execute("DELETE FROM document_pages WHERE path=?", [path])
                            for page in pages where visual { try db.execute("INSERT INTO document_pages(path,page,body,ocr,reason) VALUES(?,?,?,?,?)", [path,String(page.number),page.text,page.isOCR ? "1" : "0",page.issue?.rawValue]) }
                            let id = try db.rows("SELECT rowid FROM documents WHERE path=?", [path])[0][0]
                            try db.execute("INSERT INTO document_terms(rowid,tokens) VALUES(?,?)", [id,tokens])
                        }
                    } catch IndexDatabaseError.capacity { report.capped = true; break }
                    report.extracted += 1
                }
                report.currentFile = ""; report.currentPage = 0; report.totalPages = 0; report.recognizing = false
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
                        for row in stale { try eraseTerms(db, row: row); try db.execute("DELETE FROM document_pages WHERE path=(SELECT path FROM documents WHERE rowid=?)", [row[0]]); try db.execute("DELETE FROM documents WHERE rowid=?", [row[0]]) }
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
    private func loadPages(_ db: IndexDatabase, path: String) throws -> [IndexedPage] {
        try db.rows("SELECT page,body,ocr,reason FROM document_pages WHERE path=? ORDER BY page", [path]).map {
            IndexedPage(number: Int($0[0]) ?? 0, text: $0[1], isOCR: $0[2] == "1", issue: DocumentReadReason(rawValue: $0[3]))
        }
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
                for row in batch { try eraseTerms(db, row: row); try db.execute("DELETE FROM document_pages WHERE path=(SELECT path FROM documents WHERE rowid=?)", [row[0]]); try db.execute("DELETE FROM documents WHERE rowid=?", [row[0]]) }
            }
            for row in try db.rows("SELECT root FROM scans") where !roots.contains(where: { $0.resolvingSymlinksInPath().path == row[0] }) { try db.execute("DELETE FROM scans WHERE root=?", [row[0]]) }
            for row in try db.rows("SELECT root FROM scan_state") where !roots.contains(where: { $0.resolvingSymlinksInPath().path == row[0] }) { try db.execute("DELETE FROM scan_state WHERE root=?", [row[0]]) }
        }
        try db.execute("INSERT INTO document_terms(document_terms) VALUES('optimize')")
        try db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try db.execute("VACUUM")
    }
}
