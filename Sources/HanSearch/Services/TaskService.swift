import Foundation
import EventKit
import HanSearchCore

struct TaskCalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let source: String
    var label: String { source.isEmpty ? title : title + " · " + source }
}

@MainActor
enum TaskService {
    private static let store = EKEventStore()
    static func eventCalendars() -> [TaskCalendarChoice] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return store.calendars(for: .event).filter(\.allowsContentModifications).map { TaskCalendarChoice(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "") }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    static func destinationTitle(for kind: TaskPlan.Kind, calendarID: String? = nil) -> String {
        if kind == .event {
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return L.text("系統預設行事曆（確認後授權）") }
            if let calendarID { return eventCalendars().first { $0.id == calendarID }?.label ?? L.text("原選行事曆已無法使用，請重新選擇。") }
            return store.defaultCalendarForNewEvents?.title ?? L.text("尚無可寫入的預設行事曆")
        }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return L.text("系統預設提醒事項清單（確認後授權）") }
        return store.defaultCalendarForNewReminders()?.title ?? L.text("尚無可寫入的預設提醒事項清單")
    }
    static func create(_ plan: TaskPlan) async throws -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = plan.isAllDay ? .none : .short
        switch plan.kind {
        case .event:
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw ProcessFailure.failed("尚未允許行事曆存取。") }
            let calendar: EKCalendar
            if let id = plan.calendarID {
                guard let selected = store.calendars(for: .event).first(where: { $0.calendarIdentifier == id }), selected.allowsContentModifications else { throw ProcessFailure.failed("原選行事曆已無法使用，請重新選擇。") }
                calendar = selected
            } else {
                guard let selected = store.defaultCalendarForNewEvents, selected.allowsContentModifications else { throw ProcessFailure.failed("沒有可寫入的預設行事曆，請在行事曆 App 設定。") }
                calendar = selected
            }
            let event = makeEvent(plan, store: store)
            event.calendar = calendar
            try store.save(event, span: .thisEvent, commit: true)
            return L.format("已新增行程「%@」", plan.title) + "\n" + formatter.string(from: plan.start) + (plan.isAllDay ? " · " + L.text("全天") : " · \(Int(plan.duration / 60)) " + L.text("分鐘")) + "\n" + L.text("行事曆") + "：" + calendar.title
        case .reminder:
            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw ProcessFailure.failed("尚未允許提醒事項存取。") }
            guard let calendar = store.defaultCalendarForNewReminders(), calendar.allowsContentModifications else { throw ProcessFailure.failed("沒有可寫入的預設提醒事項清單，請先在提醒事項 App 建立清單。") }
            let reminder = makeReminder(plan, store: store)
            reminder.calendar = calendar
            try store.save(reminder, commit: true)
            return L.format("已新增提醒「%@」", plan.title) + "\n" + formatter.string(from: plan.start) + "\n" + L.text("清單") + "：" + calendar.title
        case .alarm: throw ProcessFailure.failed("鬧鐘應交由 Apple 系統時鐘捷徑處理。")
        }
    }
    // Pure object construction is separate from commit so mapping can be checked without
    // requesting access or inserting test items into a person's calendars.
    static func makeEvent(_ plan: TaskPlan, store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = plan.title; event.startDate = plan.start; event.endDate = plan.start.addingTimeInterval(plan.duration)
        event.isAllDay = plan.isAllDay
        if let offset = plan.alarmOffset { event.addAlarm(EKAlarm(relativeOffset: offset)) }
        return event
    }
    static func makeReminder(_ plan: TaskPlan, store: EKEventStore) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.title = plan.title
        var calendar = Calendar.current
        calendar.timeZone = .current
        let fields: Set<Calendar.Component> = plan.isAllDay ? [.year,.month,.day] : [.year,.month,.day,.hour,.minute,.second]
        var components = calendar.dateComponents(fields, from: plan.start)
        components.timeZone = calendar.timeZone
        reminder.dueDateComponents = components
        if !plan.isAllDay { reminder.addAlarm(EKAlarm(absoluteDate: plan.start)) }
        return reminder
    }
}
