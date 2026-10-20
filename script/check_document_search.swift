import Foundation
import HanSearchCore

private final class VerificationFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0, peak = 0
    private var oldStarted = false, oldFinished = false
    var maximumConcurrency: Int { lock.lock(); defer { lock.unlock() }; return peak }
    var startedOld: Bool { lock.lock(); defer { lock.unlock() }; return oldStarted }
    var finishedOld: Bool { lock.lock(); defer { lock.unlock() }; return oldFinished }
    private func begin(_ query: String) { lock.lock(); active += 1; peak = max(peak, active); if query == "舊摘要" { oldStarted = true }; lock.unlock() }
    private func end(_ query: String) { lock.lock(); active -= 1; if query == "舊摘要" { oldFinished = true }; lock.unlock() }
    private func slowResponse() { Thread.sleep(forTimeInterval: 0.35) }
    func read(_ url: URL, query: String) async -> DocumentPreview {
        begin(query); defer { end(query) }
        if query == "舊摘要" {
            await Task.detached { self.slowResponse() }.value
            return .match("舊摘要不該蓋掉新查詢")
        }
        do { try await Task.sleep(for: .milliseconds(10)) } catch { return .cancelled }
        return url.lastPathComponent == "z-real.docx" ? .match("如果只能用這份真正有內文的文件") : .noLiteralMatch
    }
}

private final class IndexFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private var oldDone = false
    let local: URL
    init(local: URL) { self.local = local }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls.count }
    func started(_ query: String) -> Bool { lock.lock(); defer { lock.unlock() }; return calls.contains(query) }
    var oldFinished: Bool { lock.lock(); defer { lock.unlock() }; return oldDone }
    func search(_ query: String, _ cancellation: ProcessCancellation) -> SearchResponse {
        lock.lock(); calls.append(query); lock.unlock()
        if query == "舊查詢" {
            // A late provider response must be ignored even if it does not cooperate with cancellation.
            Thread.sleep(forTimeInterval: 0.6)
            lock.lock(); oldDone = true; lock.unlock()
            return SearchResponse(items: [SearchItem(url: URL(fileURLWithPath: "/fixture/old.docx"), source: "fixture")])
        }
        if query.contains("失敗") { return SearchResponse(items: [], warning: "fixture-index-failure") }
        if query == "內文測試詞" {
            for _ in 0..<20 { if cancellation.isCancelled { return SearchResponse(items: []) }; Thread.sleep(forTimeInterval: 0.02) }
            return SearchResponse(items: [SearchItem(url: local, source: "文件內容・系統索引"), SearchItem(url: URL(fileURLWithPath: "/fixture/global.pptx"), source: "文件內容・系統索引")])
        }
        return SearchResponse(items: [SearchItem(url: URL(fileURLWithPath: "/fixture/new.pdf"), source: "文件內容・系統索引")])
    }
}

@main struct DocumentSearchChecks {
    @MainActor static func main() async throws {
        let suite = "HanDocumentChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "spotlightSupplement.v1")
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let written = root.appendingPathComponent("unrelated-name.txt")
        try "内文测试词。失败时保留本机结果。".write(to: written, atomically: true, encoding: .utf8)
        // Directory enumeration may expose /private/var where temporaryDirectory uses /var.
        let local = SearchService.index(folder: root).documents.first!.url
        let expectedCreation = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedModification = expectedCreation.addingTimeInterval(86_400)
        try FileManager.default.setAttributes([.creationDate: expectedCreation, .modificationDate: expectedModification], ofItemAtPath: written.path)
        let dates = FileCreationDateStore()
        let readCreation = await dates.date(for: written)
        precondition(readCreation.map { abs($0.timeIntervalSince(expectedCreation)) < 1 } == true, "Show the filesystem creation date, never substitute modification date")
        let missingDate = await dates.date(for: root.appendingPathComponent("missing.txt"))
        precondition(missingDate == nil, "Unavailable metadata must not invent a date")
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let fixture = IndexFixture(local: local)
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults, contentSearcher: { fixture.search($0, $1) }, documentIndexURL: root.appendingPathComponent("Index/test.sqlite"))
        func wait(line: UInt = #line, _ condition: @escaping @MainActor () -> Bool) async throws {
            for _ in 0..<500 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Document wait at line \(line): searching=\(store.searching), indexing=\(store.indexing), results=\(store.results.count), calls=\(fixture.count)")
        }
        store.folder = root; store.rebuildIndex(); try await wait { !store.indexing }
        store.query = "內文測試詞"; store.search()
        try await wait { store.results.contains { $0.id == local.path } && store.searching }
        store.selection = local.path
        try await wait { !store.searching }
        precondition(store.results.count == 2 && store.results.contains { $0.url.pathExtension == "pptx" })
        precondition(store.results.first { $0.id == local.path }?.excerpt.contains("内文测试词") == true)
        precondition(store.selection == local.path, "Late full-text matches must preserve keyboard selection")
        let beforeQuiet = fixture.count
        store.details = "keep details"; store.refreshSearchResults()
        try await Task.sleep(for: .milliseconds(350))
        precondition(fixture.count == beforeQuiet && store.results.count == 2 && store.details == "keep details" && store.selection == local.path && !store.showSearchActivity)
        store.query = "舊查詢"; store.search(); try await wait { fixture.started("舊查詢") }
        store.query = "新查詢"; store.search(); try await wait { !store.searching }
        try await wait { fixture.oldFinished }
        try await Task.sleep(for: .milliseconds(50))
        precondition(store.results.map(\.id) == ["/fixture/new.pdf"])
        store.query = "內文測試詞 失敗"; store.search(); try await wait { !store.searching }
        precondition(store.results.contains { $0.id == local.path } && store.notice == "fixture-index-failure")
        let beforeCalculator = fixture.count
        store.query = "2+3"; store.search(); try await wait { !store.searching }
        precondition(fixture.count == beforeCalculator && store.quickResults.contains { $0.id == "quick:calculator" })
        store.fullTextInAll = false; store.query = "內文測試詞"; store.search(); try await wait { !store.searching }
        precondition(fixture.count == beforeCalculator && !store.results.contains { $0.id == local.path })
        precondition(defaults.object(forKey: "fullTextInAll.v1") as? Bool == false)
        store.mode = .contents; store.search(); try await wait { !store.searching }
        precondition(store.results.contains { $0.id == local.path } && fixture.count == beforeCalculator)
        store.folder = nil; store.query = "新查詢"; store.search(); try await wait { !store.searching }
        precondition(store.results.map(\.id) == ["/fixture/new.pdf"] && fixture.count == beforeCalculator + 1)
        store.mode = .names; store.search(); try await wait { !store.searching }
        precondition(fixture.count == beforeCalculator + 1)
        let previews = DocumentPreviewStore()
        let cancelledPreview = Task { await previews.preview(url: written, query: "內文測試詞") }
        cancelledPreview.cancel()
        let cancelledValue = await cancelledPreview.value
        precondition(cancelledValue == .cancelled)
        let snippet = await previews.preview(url: written, query: "內文測試詞")
        guard case let .match(text) = snippet else { preconditionFailure("Missing document preview") }
        precondition(text.contains("内文测试词") && !SearchHighlight.ranges(in: text, query: "內文測試詞").isEmpty)
        try "Changed fixture".write(to: written, atomically: true, encoding: .utf8)
        let cachedPreview = await previews.preview(url: written, query: "內文測試詞")
        precondition(cachedPreview == snippet)
        precondition(DocumentPreview.read(written, query: "內文測試詞", cancellation: ProcessCancellation()) == .noLiteralMatch)
        let verifier = VerificationFixture()
        let candidates = (0..<24).map { SearchItem(url: URL(fileURLWithPath: "/fixture/noise-\($0).txt"), source: "文件・系統索引") } + [SearchItem(url: URL(fileURLWithPath: "/fixture/z-real.docx"), source: "文件・系統索引")]
        let ranked = SearchStore(loadSources: false, taskPreferences: defaults, sourcePreferences: defaults,
                                 contentSearcher: { term, _ in SearchResponse(items: term == "舊摘要" ? [SearchItem(url: URL(fileURLWithPath: "/fixture/old.pdf"), source: "文件・系統索引")] : candidates) },
                                 documentPreviewLoader: { await verifier.read($0, query: $1) })
        ranked.fullTextInAll = true
        ranked.query = "如果只能用"; ranked.search()
        try await wait { ranked.verifyingDocumentContents && !ranked.searching && ranked.documentVerificationCompleted > 0 }
        precondition(ranked.showsSearchProgress && ranked.documentVerificationTotal == 25 && ranked.documentVerificationCompleted <= 25, "Progress must cover verification after the native search finishes")
        let completedDuringRead = ranked.documentVerificationCompleted
        try await wait { !ranked.searching && !ranked.verifyingDocumentContents && ranked.results.count == 25 }
        precondition(!ranked.showsSearchProgress && ranked.documentVerificationCompleted == 25 && ranked.documentVerificationCompleted >= completedDuringRead)
        ranked.refreshSearchResults(); try await Task.sleep(for: .milliseconds(250))
        precondition(!ranked.showsSearchProgress && ranked.documentVerificationCompleted == 25, "Quiet refresh must not replay progress")
        precondition(ranked.allIDs == ["/fixture/z-real.docx"] && ranked.otherIndexedResultCount == 24, "Unverified native matches must not bury a later literal hit")
        precondition(verifier.maximumConcurrency <= 2, "Verification must bound concurrent reads")
        for _ in 0..<20 { ranked.habits.record(query: ranked.query, identity: "file:/fixture/noise-0.txt", kind: .file) }
        ranked.toggleOtherIndexedResults()
        precondition(ranked.allIDs.first == "/fixture/z-real.docx" && ranked.allIDs.count == 25, "Habits must not promote unrelated index candidates above confirmed matches")
        ranked.selection = "/fixture/z-real.docx"; ranked.toggleOtherIndexedResults()
        precondition(ranked.selection == "/fixture/z-real.docx")
        ranked.query = "舊摘要"; ranked.search(); try await wait { verifier.startedOld }
        ranked.query = "如果只能用"; ranked.search()
        try await wait { verifier.finishedOld && !ranked.searching && !ranked.verifyingDocumentContents }
        precondition(ranked.documentPreviews["/fixture/old.pdf"] == nil && ranked.allIDs == ["/fixture/z-real.docx"] && !ranked.showOtherIndexedResults, "Late old snippets must not leak into a new query")
        precondition(ranked.documentVerificationTotal == 25 && ranked.documentVerificationCompleted == 25, "A cancelled old query must not advance the new progress")
        let modelName = SearchItem(url: URL(fileURLWithPath: "/fixture/z-DL32-manual.pdf"), source: "文件・系統索引")
        let modelBody = SearchItem(url: URL(fileURLWithPath: "/fixture/b-inventory.xlsx"), source: "文件・系統索引")
        let modelNoise = SearchItem(url: URL(fileURLWithPath: "/fixture/a-noise.pdf"), source: "文件・系統索引")
        let models = SearchStore(loadSources: false, taskPreferences: defaults, sourcePreferences: defaults,
                                 contentSearcher: { _, _ in SearchResponse(items: [modelNoise, modelBody, modelName]) },
                                 documentPreviewLoader: { url, _ in url == modelBody.url ? .match("音控清單!B3　DL32") : .noLiteralMatch })
        models.fullTextInAll = true
        for _ in 0..<20 { models.habits.record(query: "dl32", identity: "file:" + modelBody.id, kind: .file) }
        models.query = "dl32"; models.search()
        try await wait { !models.searching && !models.verifyingDocumentContents && models.documentVerificationTotal == 3 }
        precondition(models.allIDs == [modelName.id, modelBody.id] && models.otherIndexedResultCount == 1, "Model filenames must outrank generic body mentions and habits; unrelated index hits stay collapsed")
        models.toggleOtherIndexedResults()
        precondition(models.allIDs == [modelName.id, modelBody.id, modelNoise.id])
        let oldest = SearchItem(url: URL(fileURLWithPath: "/fixture/old-dl32.pdf"), source: "檔名")
        let newest = SearchItem(url: URL(fileURLWithPath: "/fixture/new-dl32.xlsx"), source: "資料夾・內容", excerpt: "DL32")
        let unknown = SearchItem(url: URL(fileURLWithPath: "/fixture/missing-dl32.txt"), source: "檔名")
        let app = SearchItem(url: URL(fileURLWithPath: "/fixture/DL32.app"), source: "App")
        let dated = SearchStore(loadSources: false, taskPreferences: defaults, sourcePreferences: defaults,
                                fileCreationDateLoader: { url in
                                    if url == newest.url { try? await Task.sleep(for: .milliseconds(30)); return expectedCreation.addingTimeInterval(100) }
                                    return url == oldest.url ? expectedCreation : nil
                                })
        dated.query = "dl32"; dated.mode = .contents; dated.results = [oldest, newest, unknown]
        dated.selection = oldest.id
        precondition(dated.fileSort == .relevance && !dated.readingFileDates)
        dated.fileSort = .createdNewest
        try await wait { !dated.readingFileDates }
        precondition(dated.allIDs == [newest.id, oldest.id, unknown.id] && dated.selection == oldest.id)
        dated.fileSort = .createdOldest
        try await wait { !dated.readingFileDates }
        precondition(dated.allIDs == [oldest.id, newest.id, unknown.id])
        dated.mode = .all; dated.results = [oldest, app, newest, unknown]
        try await wait { !dated.readingFileDates }
        let withApp = dated.allIDs
        dated.fileSort = .createdNewest
        try await wait { !dated.readingFileDates }
        precondition(dated.allIDs.firstIndex(of: app.id) == withApp.firstIndex(of: app.id), "Date sorting must keep apps in their existing All slots")
        precondition(dated.allIDs.filter { $0 != app.id } == [newest.id, oldest.id, unknown.id])
        dated.results = [newest]; dated.results = [oldest]
        try await wait { !dated.readingFileDates }
        try await Task.sleep(for: .milliseconds(50))
        precondition(dated.fileDates.keys.sorted() == [oldest.id], "A late metadata response must not restore replaced results")
        let restoredSort = SearchStore(loadSources: false, taskPreferences: defaults, sourcePreferences: defaults)
        precondition(restoredSort.fileSort == .createdNewest)
        dated.fileSort = .relevance
        precondition(!dated.readingFileDates && defaults.string(forKey: "fileResultSort.v1") == "relevance")
        print("PASS: file creation-date ordering in both directions, missing dates last, App slots, stable selection, stale metadata rejection and sort preference persistence")
        let ownDefaults = UserDefaults(suiteName: suite + ".independent")!
        defer { ownDefaults.removePersistentDomain(forName: suite + ".independent") }
        let proof = root.appendingPathComponent("local-proof.txt")
        try "索引重启验证词：只在 Han 自建索引里。".write(to: proof, atomically: true, encoding: .utf8)
        let noSystem = IndexFixture(local: proof)
        let ownURL = root.appendingPathComponent("Index/persistent-proof.sqlite")
        let independent = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: ownDefaults), taskPreferences: ownDefaults, sourcePreferences: ownDefaults, contentSearcher: { noSystem.search($0, $1) }, documentIndexURL: ownURL)
        independent.autoRefreshEnabled = false
        try independent.addDocumentRoots([root]); try await wait { !independent.indexing }
        independent.query = "索引重啟驗證詞"; independent.search(); try await wait { !independent.searching }
        precondition(independent.results.contains { $0.url == proof && $0.excerpt.contains("重启验证") } && noSystem.count == 0 && !independent.spotlightSupplement)
        let resumed = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: ownDefaults), taskPreferences: ownDefaults, sourcePreferences: ownDefaults, contentSearcher: { noSystem.search($0, $1) }, documentIndexURL: ownURL)
        precondition(resumed.documentRoots.map(\.path) == [root.path] && !resumed.spotlightSupplement)
        resumed.query = "索引重啟驗證詞"; resumed.search(); try await wait { !resumed.searching }
        precondition(resumed.results.contains { $0.url == proof } && noSystem.count == 0, "A new Store must query persisted content without scanning or calling Spotlight")
        resumed.removeDocumentRoot(root); try await wait { !resumed.indexing && !resumed.searching }
        precondition(resumed.results.isEmpty && resumed.documentRoots.isEmpty)
        let removed = try resumed.documentIndex.statistics(roots: [root])
        precondition(removed.files == 0, "Removing a scope must delete its persistent text")
        print("PASS: All searches independent persistent contents, restores authorized roots across Store restarts, makes no native index calls, and removes scoped text on request")
        print("PASS: model filename/body evidence and history stay in relevance tiers; Excel participates in All with cell excerpts")
        print("PASS: literal content evidence outranks unrelated index matches and habits, candidates verified without scrolling, collapsed fallback, bounded concurrency and late-preview rejection")
        print("PASS: bounded document previews, cancellation, ephemeral cache and original-text highlighting; All includes system-wide and local contents, fast partial results, selection preservation, deduplication/snippets, quiet cache reuse, stale-response rejection, visible failure with local results, utility/mode isolation and persisted opt-out; fixture index and temporary files only")
    }
}
