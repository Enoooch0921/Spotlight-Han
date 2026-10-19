import Foundation

public enum ClockAlarmRequest {
    /// Clock alarms repeat at a wall-clock minute, without a one-off future date.
    public static func date(for plan: TaskPlan, now: Date, calendar: Calendar = .current) throws -> Date {
        guard plan.kind == .alarm, plan.start > now else { throw ProcessFailure.failed("鬧鐘時間已過，請重新輸入。") }
        let minute = floor(plan.start.timeIntervalSince1970 / 60) * 60
        let date = Date(timeIntervalSince1970: minute + (plan.start.timeIntervalSince1970 > minute + 0.001 ? 60 : 0))
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime), abs(next.timeIntervalSince(date)) < 1 else {
            throw ProcessFailure.failed("系統時鐘鬧鐘只設定下一次的時分；更晚日期請改用提醒事項，避免提早響鈴。")
        }
        return date
    }
}
