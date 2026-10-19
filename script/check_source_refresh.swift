import Foundation
import AppKit
import Combine
import HanSearchCore

@main
struct SourceRefreshChecks {
    @MainActor static func main() async throws {
        let suite = "HanSourceRefreshChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([SearchMode.calendar.rawValue, SearchMode.reminders.rawValue], forKey: "enabledSources.v1")
        var calls: [SearchMode: Int] = [:]
        var pending: [SearchMode: CheckedContinuation<PersonalLoad, Error>] = [:]
        var allowed = true
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults, sourceAccessCheck: { _ in allowed }, eventSourceLoader: { source in
            calls[source, default: 0] += 1
            return try await withCheckedThrowingContinuation { pending[source] = $0 }
        }, eventCalendarLoader: { [] })
        func wait(_ condition: @escaping @MainActor () -> Bool) async throws {
            for _ in 0..<400 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            preconditionFailure("Background refresh did not reach the expected state")
        }
        func finish(_ source: SearchMode, records: [PersonalRecord] = []) {
            let value = pending.removeValue(forKey: source)
            precondition(value != nil)
            value?.resume(returning: PersonalLoad(records: records, status: "已連接測試來源"))
        }
        for source: SearchMode in [.calendar, .reminders] { store.sourceHealth[source] = SourceHealth(phase: .ready, lastSuccess: Date()) }
        // A setup batch and a long Notes read must not block already-authorised EventKit reads.
        store.setupRunning = true
        store.connecting.insert(.notes)
        store.sourceHealth[.notes] = SourceHealth(phase: .loading)
        store.authorizationInFlight = true
        store.eventSourcesDidChange()
        try await Task.sleep(for: .milliseconds(2200))
        precondition(calls.isEmpty, "Do not read while a consent dialog is being handled")
        store.authorizationInFlight = false
        try await wait { pending.count == 2 }
        precondition(store.connecting.contains(.notes) && store.setupRunning)
        precondition(calls[.calendar] == 1 && calls[.reminders] == 1)
        // A second change arriving during the read survives completion and triggers a follow-up.
        store.eventSourcesDidChange()
        finish(.calendar); finish(.reminders)
        try await wait { pending.count == 2 }
        precondition(calls[.calendar] == 2 && calls[.reminders] == 2)
        finish(.calendar); finish(.reminders)
        try await wait { !store.connecting.contains(.calendar) && !store.connecting.contains(.reminders) }
        precondition(store.sourceHealth[.calendar]?.invalidated == false)
        precondition(store.sourceHealth[.reminders]?.invalidated == false)
        let completed = store.sourceHealth[.calendar]?.lastSuccess
        // Turning background refresh off preserves dirtiness without starting work.
        store.autoRefreshEnabled = false
        store.eventSourcesDidChange(); store.refreshAuthorizedSources()
        try await Task.sleep(for: .milliseconds(2200))
        precondition(calls[.calendar] == 2 && store.sourceHealth[.calendar]?.invalidated == true)
        store.autoRefreshEnabled = true
        store.refreshAuthorizedSources()
        try await wait { pending.count == 2 }
        pending.removeValue(forKey: .calendar)?.resume(throwing: ProcessFailure.failed("fake read failure"))
        pending.removeValue(forKey: .reminders)?.resume(throwing: SourceAccessFailure(source: "提醒事項", status: .denied))
        try await wait { !store.connecting.contains(.calendar) && !store.connecting.contains(.reminders) }
        precondition(store.sourceHealth[.calendar]?.phase == .failed)
        precondition(store.sourceHealth[.calendar]?.lastSuccess == completed)
        precondition(store.sourceHealth[.reminders]?.phase == .needsPermission)
        // Failure backoff and lost permission must not reopen consent or spin indefinitely.
        let before = calls
        store.refreshAuthorizedSources(changedOnly: true)
        precondition(calls == before)
        store.sourceHealth[.calendar] = SourceHealth(phase: .ready, lastSuccess: Date(), invalidated: true)
        allowed = false
        store.refreshAuthorizedSources(changedOnly: true)
        precondition(store.sourceHealth[.calendar]?.phase == .needsPermission && calls == before)
        store.cancelConnections()
        // Background snapshots must update matches without restarting the query,
        // moving its selection, dismissing details, or flashing a progress indicator.
        allowed = true
        store.setupRunning = false
        store.query = "Fixture"; store.mode = .calendar
        var queryStarts = 0
        let changes = store.$searching.dropFirst().sink { if $0 { queryStarts += 1 } }
        store.search()
        for _ in 0..<20 { store.refreshSearchResults() }
        try await wait { !store.searching }
        precondition(queryStarts == 1)
        let first = PersonalRecord(id: "fixture:first", title: "Fixture First", subtitle: "", text: "Fixture", symbol: "calendar", mode: .calendar, action: .details("First"))
        let second = PersonalRecord(id: "fixture:second", title: "Fixture Second", subtitle: "", text: "Fixture", symbol: "calendar", mode: .calendar, action: .details("Second"))
        store.sourceHealth[.calendar] = SourceHealth(phase: .ready, lastSuccess: Date(), invalidated: true)
        store.refreshAuthorizedSources(changedOnly: true)
        try await wait { pending[.calendar] != nil }
        finish(.calendar, records: [first])
        try await wait { store.quickResults.contains { $0.id == "quick:fixture:first" } }
        let selected = "quick:fixture:first"
        store.selection = selected; store.details = "Keep this open"
        store.sourceHealth[.calendar]?.markChanged()
        store.refreshAuthorizedSources(changedOnly: true)
        try await wait { pending[.calendar] != nil }
        finish(.calendar, records: [first, second])
        try await wait { store.quickResults.contains { $0.id == "quick:fixture:second" } }
        precondition(store.selection == selected && store.details == "Keep this open")
        precondition(queryStarts == 1 && !store.showSearchActivity)
        changes.cancel()
        store.cancelConnections()
        print("PASS: deferred notifications, concurrent EventKit refresh during Notes/setup, changes during reads, auto-refresh switch, failure backoff, old timestamps, permission loss and quiet search refresh preserving selection/details; fake loaders only, no personal reads or writes")
    }
}
