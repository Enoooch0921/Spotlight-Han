import Foundation
import EventKit
import HanSearchCore

enum TaskService {
    static func create(_ plan: TaskPlan) async throws -> String {
        let store = EKEventStore()
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        switch plan.kind {
        case .event:
            guard try await store.requestFullAccessToEvents() else { throw ProcessFailure.failed("尚未允許行事曆存取。") }
            guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { throw ProcessFailure.failed("沒有可寫入的預設行事曆，請在行事曆 App 設定。") }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar; event.title = plan.title; event.startDate = plan.start
            event.endDate = plan.start.addingTimeInterval(plan.duration)
            try store.save(event, span: .thisEvent, commit: true)
            return "已新增行程「\(plan.title)」\n\(formatter.string(from: plan.start)) · \(Int(plan.duration / 60)) 分鐘\n行事曆：\(calendar.title)"
        case .reminder:
            guard try await store.requestFullAccessToReminders() else { throw ProcessFailure.failed("尚未允許提醒事項存取。") }
            guard let calendar = store.defaultCalendarForNewReminders(), calendar.allowsContentModifications else { throw ProcessFailure.failed("沒有可寫入的預設提醒事項清單，請先在提醒事項 App 建立清單。") }
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar; reminder.title = plan.title
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.start)
            reminder.addAlarm(EKAlarm(absoluteDate: plan.start))
            try store.save(reminder, commit: true)
            return "已新增提醒「\(plan.title)」\n\(formatter.string(from: plan.start))\n清單：\(calendar.title)"
        case .alarm: throw ProcessFailure.failed("鬧鐘應交由 Apple 系統時鐘捷徑處理。")
        }
    }
}
