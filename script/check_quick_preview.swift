import Foundation
import HanSearchCore

@main struct QuickPreviewChecks {
    @MainActor static func main() {
        let suite = "HanQuickPreviewChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults,
                                sourcePreferences: defaults, documentIndexURL: root.appendingPathComponent("Documents.sqlite"))
        let first = SearchItem(url: root.appendingPathComponent("preview-a.pdf"), source: "Han 索引・內文", excerpt: "preview")
        let app = SearchItem(url: root.appendingPathComponent("preview.app"), source: "App")
        let second = SearchItem(url: root.appendingPathComponent("preview-b.png"), source: "檔名")
        store.mode = .names; store.query = "preview"; store.results = [first, app, second]
        store.selection = first.id
        precondition(store.selectedPreviewItem == first && !store.previewSelectionArmed, "Automatic selection must not consume typing spaces")
        var opened = 0, dismissed = 0
        store.toggleFilePreview = { opened += 1 }; store.dismissFilePreview = { dismissed += 1 }
        store.previewFile(first)
        precondition(opened == 1 && store.previewSelectionArmed)
        store.query = "preview phrase"
        precondition(!store.previewSelectionArmed && dismissed == 1, "Editing resets preview intent and dismisses stale content")
        store.movePreviewSelection(1)
        precondition(store.selection == second.id && store.previewSelectionArmed, "Preview navigation must skip apps")
        store.movePreviewSelection(-1); precondition(store.selection == first.id)
        store.selection = app.id; precondition(store.selectedPreviewItem == nil)
        store.selection = first.id; store.mode = .apps
        precondition(store.selectedPreviewItem == nil && !store.previewSelectionArmed)
        store.mode = .contents; store.results = [SearchItem(url: first.url, source: "文件・系統索引")]
        store.query = "unconfirmed"; store.selection = first.id
        precondition(store.selectedPreviewItem == nil, "Collapsed unconfirmed results cannot be previewed accidentally")
        store.showOtherIndexedResults = true; precondition(store.selectedPreviewItem != nil)
        print("PASS: explicit result preview intent, normal query spaces, stale-query dismissal, app filtering, file navigation and hidden-result boundaries; isolated store/preferences only")
    }
}
