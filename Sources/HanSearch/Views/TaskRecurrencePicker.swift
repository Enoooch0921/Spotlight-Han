import SwiftUI
import HanSearchCore

struct TaskRecurrencePicker: View {
    @Binding var recurrence: TaskRecurrence?
    let start: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L.text("重複"), selection: frequency) {
                Text(L.text("不重複")).tag("none")
                Text(L.text("每天")).tag("daily")
                Text(L.text("每週")).tag("weekly")
                Text(L.text("每月")).tag("monthly")
            }
            if let recurrence {
                Stepper(L.format("重複間隔：%@", String(recurrence.interval)), value: interval, in: 1...52)
                TaskRecurrenceSummary(rule: recurrence, start: start)
            }
        }
    }
    private var frequency: Binding<String> {
        Binding(get: { recurrence?.frequency.rawValue ?? "none" }, set: { value in
            recurrence = TaskRecurrence.Frequency(rawValue: value).map { TaskRecurrence($0, interval: recurrence?.interval ?? 1) }
        })
    }
    private var interval: Binding<Int> {
        Binding(get: { recurrence?.interval ?? 1 }, set: { recurrence?.interval = $0 })
    }
}

struct TaskRecurrenceSummary: View {
    let rule: TaskRecurrence
    let start: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(TaskRecurrenceText.description(rule, start: start), systemImage: "repeat").font(.callout.weight(.medium))
            Text(L.text("持續重複，未設定結束日期。")).font(.caption).foregroundStyle(.secondary)
            if rule.frequency == .monthly {
                Text(L.text("以開始日期的日數重複；沒有該日期的月份會略過。")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
