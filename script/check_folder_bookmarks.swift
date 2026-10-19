import Foundation

@main
struct BookmarkChecks {
    @MainActor static func main() throws {
        let domain = "SpotlightHan.BookmarkChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = parent.appendingPathComponent("original")
        let renamed = parent.appendingPathComponent("renamed")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let service = FileAccessBookmarks(defaults: defaults)
        try service.add([original])
        let restored = FileAccessBookmarks(defaults: defaults)
        precondition(restored.urls.count == 1)
        precondition(restored.urls[0].resolvingSymlinksInPath().path == original.resolvingSymlinksInPath().path)
        // SearchStore persists the resolved root path after each restore.
        let savedIndexRoot = restored.resolvedIndexURL(original.path)
        try FileManager.default.moveItem(at: original, to: renamed)
        let moved = FileAccessBookmarks(defaults: defaults)
        precondition(moved.urls[0].resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)
        precondition(moved.resolvedIndexURL(savedIndexRoot.appendingPathComponent("fixture.mp4").path).path == moved.urls[0].appendingPathComponent("fixture.mp4").path)
        moved.clear()
        precondition(FileAccessBookmarks(defaults: defaults).urls.isEmpty)
        let invalid = ["/fixture/unavailable": Data("unresolvable fixture".utf8)]
        defaults.set(try JSONEncoder().encode(invalid), forKey: "folderAccessBookmarks.v1")
        let unavailable = FileAccessBookmarks(defaults: defaults)
        precondition(unavailable.urls.isEmpty && unavailable.unavailablePaths == ["/fixture/unavailable"])
        let retained = try JSONDecoder().decode([String: Data].self, from: defaults.data(forKey: "folderAccessBookmarks.v1")!)
        precondition(retained == invalid, "Failed restore must preserve the bookmark for recovery")
        let roots = unavailable.restoreIndexRoots(["/fixture/unavailable/videos"])
        precondition(roots.available.isEmpty && roots.unavailable.map(\.path) == ["/fixture/unavailable/videos"])
        unavailable.clear(); precondition(FileAccessBookmarks(defaults: defaults).unavailablePaths.isEmpty)
        print("PASS: folder bookmark persistence, renamed-folder recovery and forgetting grants; isolated test directory only")
    }
}
