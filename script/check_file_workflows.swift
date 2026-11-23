import AppKit
import HanSearchCore

@main struct FileWorkflowChecks {
    @MainActor static func main() async throws {
        let suite = "HanFileWorkflows." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite)
        let docs = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let file = docs.appendingPathComponent("fixture-报价单.pdf")
        let other = docs.appendingPathComponent("fixture-报价单.txt")
        try Data().write(to: file)
        try "报价单".write(to: other, atomically: true, encoding: .utf8)
        let dbURL = root.appendingPathComponent("index/db.sqlite")
        let index = PersistentDocumentIndex(databaseURL: dbURL, ocrEnabled: false)
        _ = try index.synchronize(roots: [docs])
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults,
                                sourcePreferences: defaults, contentSearcher: { _, _ in
                                    SearchResponse(items: [SearchItem(url: other, source: "文件・系統索引")])
                                }, documentIndexURL: dbURL)
        store.folder = docs
        store.spotlightSupplement = true
        store.fullTextInAll = true
        store.query = "PDF 報價單"
        store.search()
        func wait() async throws {
            for _ in 0..<300 { if !store.searching { return }; try await Task.sleep(for: .milliseconds(20)) }
            preconditionFailure("Search did not settle")
        }
        try await wait()
        precondition(store.matchText == "報價單" && store.results.map(\.url) == [file] && store.quickResults.isEmpty)
        store.inspectFile(file); precondition(store.diagnosticURL == file && store.actionFile == nil)
        store.escapeLauncherLayer(); precondition(store.diagnosticURL == nil && store.actionFile?.url == file)
        store.query = store.parsedFileQuery.removing(.type); store.search(); try await wait()
        precondition(Set(store.results.map(\.url)) == [file, other])
        let original = store.primaryResultIDs
        store.setLowered(true, fileID: original[0])
        precondition(store.primaryResultIDs.last == original[0])
        store.setLowered(false, fileID: original[0])
        precondition(store.primaryResultIDs == original)
        let drag = FileResultActions.draggingItem(for: file)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        precondition(pasteboard.writeObjects([drag.item as! NSPasteboardWriting]))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        precondition(urls?.map(\.standardizedFileURL) == [file.standardizedFileURL])
        print("PASS: filtered All search, action selection, inspection/return, filter removal, re-ranking/undo and native file URL drag payload")
    }
}
