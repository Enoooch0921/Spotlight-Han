import Foundation
import HanSearchCore

@main struct LauncherReopenChecks {
    @MainActor static func main() {
        let suite = "HanReopenChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func makeStore() -> SearchStore {
            SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults)
        }
        let store = makeStore(), start = Date(timeIntervalSince1970: 1000)
        precondition(store.reopenBehavior == .timed && store.reopenRetention == 300 && store.defaultSearchMode == .all)
        store.prepareLauncherForOpening(now: start)
        store.mode = .notes; store.query = "合成測試"; store.details = "保留的詳情"
        store.launcherDidHide(now: start)
        store.launcherDidHide(now: start.addingTimeInterval(200)) // An unrelated hide must not extend retention.
        store.prepareLauncherForOpening(now: start.addingTimeInterval(299))
        precondition(store.mode == .notes && store.query == "合成測試" && store.details != nil)
        store.prepareLauncherForOpening(now: start.addingTimeInterval(10_000)) // Already visible: never erase active typing.
        precondition(store.query == "合成測試")
        store.launcherDidHide(now: start.addingTimeInterval(300))
        store.defaultSearchMode = .apps
        store.appLibrary.select(.recent)
        store.prepareLauncherForOpening(now: start.addingTimeInterval(600))
        precondition(store.mode == .apps && store.query.isEmpty && store.details == nil && store.appLibrary.group == .all)
        store.reopenBehavior = .reset; store.reopenRetention = 60
        store.query = "語言準備中的輸入"
        store.launcherDidHide(now: start)
        store.prepareLauncherForOpening(now: start.addingTimeInterval(1000), continuingFlow: true)
        precondition(store.query == "語言準備中的輸入")
        store.launcherDidHide(now: start); store.composerMode = .event; store.query = "明天下午開會"
        store.prepareLauncherForOpening(now: start.addingTimeInterval(1000))
        precondition(store.composerMode == .event && store.query == "明天下午開會")
        store.composerMode = nil; store.reopenBehavior = .keep
        store.launcherDidHide(now: start)
        store.prepareLauncherForOpening(now: start.addingTimeInterval(100_000))
        precondition(store.query == "明天下午開會")
        let restored = makeStore()
        precondition(restored.reopenBehavior == .keep && restored.reopenRetention == 60 && restored.defaultSearchMode == .apps)
        restored.prepareLauncherForOpening(now: start)
        precondition(restored.mode == .apps && restored.query.isEmpty)
        print("PASS: reopen expiry boundary, repeated hide callbacks, visible typing, default Apps reset, continuing translation/task flows, preference persistence and no restored query")
    }
}
