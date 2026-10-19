import Foundation
import AppKit
import EventKit
import HanSearchCore

@main
struct TaskComposerChecks {
    @MainActor static func main() async throws {
        let defaults = UserDefaults(suiteName: "HanComposerChecks.\(UUID().uuidString)")!
        var plans: [TaskPlan] = []
        var finishWrite: CheckedContinuation<String, Never>?
        let calendars = [TaskCalendarChoice(id: "thumb", title: "大拇指", source: "測試"), TaskCalendarChoice(id: "toe", title: "大腳趾", source: "測試")]
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, eventCalendarLoader: { calendars }, contentSearcher: { _, _ in SearchResponse(items: []) }, taskWriter: { plan in
            plans.append(plan)
            return await withCheckedContinuation { finishWrite = $0 }
        })
        func waitForPreview() async throws {
            for _ in 0..<150 {
                if !store.composerParsing { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            preconditionFailure("Composer preview did not finish")
        }
        store.defaultEventCalendarID = "thumb"
        precondition(defaults.string(forKey: "defaultEventCalendarID.v1") == "thumb")
        store.query = "cal"; precondition(store.enterComposer()); precondition(store.query.isEmpty)
        store.query = "明天下午3點到4點開會"; store.search(); store.reviewComposer()
        try await waitForPreview()
        precondition(store.composerReviewing && store.composerDraft?.title == "開會")
        precondition(plans.isEmpty, "Preview must never write")
        precondition(store.composerDraft?.calendarID == "thumb")
        store.composerDraft?.calendarID = "missing"
        store.confirmComposer(); precondition(plans.isEmpty && store.composerCalendarError != nil)
        store.composerDraft?.calendarID = "toe"
        precondition(store.defaultEventCalendarID == "thumb", "Per-event override must not change the default")
        store.composerDraft?.title = "調整後的事項"
        store.search() // A background index refresh must preserve edits to the reviewed draft.
        precondition(store.composerDraft?.title == "調整後的事項")
        store.openSelection(); precondition(plans.isEmpty, "Return on preview must not write")
        store.authorizationInFlight = true; store.confirmComposer(); precondition(plans.isEmpty)
        store.authorizationInFlight = false
        store.connecting.insert(.notes) // A background read must not block a separate task consent.
        store.confirmComposer(); store.confirmComposer()
        for _ in 0..<20 { if finishWrite != nil { break }; await Task.yield() }
        precondition(plans.count == 1 && plans[0].title == "調整後的事項" && plans[0].calendarID == "toe", "Confirmation writes the reviewed item exactly once")
        store.cancelComposer(); precondition(store.composerMode != nil, "Cannot discard an in-flight write")
        store.connecting.remove(.notes)
        finishWrite?.resume(returning: "已建立測試事項"); finishWrite = nil
        for _ in 0..<20 { if !store.actionInFlight { break }; await Task.yield() }
        precondition(store.composerCreated != nil && store.composerDraft == nil)
        store.confirmComposer(); precondition(plans.count == 1, "Success cannot be submitted twice")
        store.cancelComposer(); precondition(store.composerMode == nil && store.query.isEmpty)
        store.query = "提醒"; precondition(store.enterComposer())
        store.query = "30分鐘後喝水"; store.search(); try await waitForPreview()
        precondition(store.composerDraft?.kind == .reminder)
        store.confirmComposer(); precondition(plans.count == 1, "An unreviewed parse cannot be submitted")
        store.reviewComposer()
        store.query = "明天上午9點買牛奶" // Simulate key input before SwiftUI's onChange callback.
        store.confirmComposer(); precondition(plans.count == 1, "A stale preview cannot be submitted")
        store.search(); try await waitForPreview()
        precondition(store.composerDraft?.title == "買牛奶" && !store.composerReviewing)
        store.composerDraft?.start = Date.distantPast; store.reviewComposer(); store.confirmComposer()
        precondition(!store.composerError.isEmpty && plans.count == 1)
        store.cancelComposer()
        store.query = "cal"; precondition(store.enterComposer())
        store.query = "下下週一下午3點開會"; store.search(); store.cancelComposer()
        try await Task.sleep(for: .milliseconds(250))
        precondition(store.composerMode == nil && store.composerDraft == nil, "Cancelled parse cannot restore a draft")
        // Verify EventKit object mapping without permissions, calendars, or save calls.
        let eventStore = EKEventStore(), future = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 + 86400))
        let eventPlan = TaskPlan(kind: .event, title: "測試行程", start: future, duration: 1800, alarmOffset: -600)
        let event = TaskService.makeEvent(eventPlan, store: eventStore)
        precondition(event.title == eventPlan.title && event.startDate == future && event.endDate == future.addingTimeInterval(1800))
        precondition(!event.isAllDay && event.alarms?.first?.relativeOffset == -600)
        let reminderPlan = TaskPlan(kind: .reminder, title: "喝水", start: future)
        let reminder = TaskService.makeReminder(reminderPlan, store: eventStore)
        precondition(reminder.title == "喝水" && reminder.alarms?.first?.absoluteDate == future && reminder.dueDateComponents?.hour != nil)
        let dayPlan = TaskPlan(kind: .reminder, title: "交報告", start: future, isAllDay: true)
        let day = TaskService.makeReminder(dayPlan, store: eventStore)
        precondition(day.dueDateComponents?.hour == nil && (day.alarms ?? []).isEmpty)
        let reopened = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, eventCalendarLoader: { calendars }, contentSearcher: { _, _ in SearchResponse(items: []) })
        precondition(reopened.defaultEventCalendarID == "thumb")
        print("PASS: composer Tab routing, preview-only Return, reviewed edits, stale input, cancellation, duplicate submission, validation, and EventKit object mapping; no personal data read or written")
    }
}
