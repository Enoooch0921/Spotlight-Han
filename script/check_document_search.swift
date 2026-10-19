import Foundation
import HanSearchCore

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
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let written = root.appendingPathComponent("unrelated-name.txt")
        try "内文测试词。失败时保留本机结果。".write(to: written, atomically: true, encoding: .utf8)
        // Directory enumeration may expose /private/var where temporaryDirectory uses /var.
        let local = SearchService.index(folder: root).documents.first!.url
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let fixture = IndexFixture(local: local)
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults, contentSearcher: { fixture.search($0, $1) })
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
        print("PASS: bounded document previews, cancellation, ephemeral cache and original-text highlighting; All includes system-wide and local contents, fast partial results, selection preservation, deduplication/snippets, quiet cache reuse, stale-response rejection, visible failure with local results, utility/mode isolation and persisted opt-out; fixture index and temporary files only")
    }
}
