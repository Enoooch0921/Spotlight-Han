import Foundation
import HanSearchCore

@main struct PersistentIndexIntegrationChecks {
    @MainActor static func main() async throws {
        let suite = "HanWatcherChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(suite)
        let root = base.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.txt")
        try "原始索引文字".write(to: original, atomically: true, encoding: .utf8)
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults,
                                contentSearcher: { _, _ in preconditionFailure("Independent index must not call Spotlight") }, documentIndexURL: base.appendingPathComponent("index/documents.sqlite"))
        defer {
            store.pauseDocumentIndex()
            try? FileManager.default.removeItem(at: base)
            defaults.removePersistentDomain(forName: suite)
        }
        func wait(_ condition: () -> Bool) async throws {
            for _ in 0..<1500 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure("Persistent background update timed out: \(store.indexNotice)")
        }
        try store.addDocumentRoots([root]); try await wait { !store.indexing && store.indexSnapshot.searchable == 1 }
        store.query = "事件更新驗證"; store.search(); try await wait { !store.searching }
        precondition(store.results.isEmpty)
        let outside = base.appendingPathComponent("incoming.txt"), added = root.appendingPathComponent("arrived.txt")
        try "事件更新验证：由另一程序新增的文件。".write(to: outside, atomically: true, encoding: .utf8)
        // FSEvents IgnoreSelf excludes this app's writes; emulate another editor with cp.
        _ = try ProcessRunner.run("/bin/cp", [outside.path, added.path])
        try await wait { !store.indexing && store.indexSnapshot.files == 2 && store.results.contains { $0.url.path == added.path } }
        _ = try ProcessRunner.run("/bin/rm", [added.path])
        try await wait { !store.indexing && store.indexSnapshot.files == 1 && store.results.isEmpty }
        precondition(!store.spotlightSupplement)
        print("PASS: real FSEvents updates independent full text after external file creation/deletion; query results quietly refresh; owned synthetic folders only")
    }
}
