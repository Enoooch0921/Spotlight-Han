import Foundation
import JavaScriptCore

public enum TaskComposerMode: String, Sendable {
    case event, reminder
    public var kind: TaskPlan.Kind { self == .event ? .event : .reminder }
    public static func command(_ query: String) -> TaskComposerMode? {
        switch ChineseSearch.normalized(query).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "cal", "calendar", "行事历", "行程": return .event
        case "rem", "reminder", "提醒", "提醒事项": return .reminder
        default: return nil
        }
    }
}

public struct TaskDraft: Equatable, Sendable {
    public var kind: TaskPlan.Kind
    public var title: String
    public var start: Date
    /// Exclusive end, including for all-day events.
    public var end: Date
    public var isAllDay: Bool
    public var alarmOffset: TimeInterval?
    public var calendarID: String?
    public var recurrence: TaskRecurrence?

    public init(kind: TaskPlan.Kind, title: String, start: Date, end: Date, isAllDay: Bool = false, alarmOffset: TimeInterval? = nil, calendarID: String? = nil, recurrence: TaskRecurrence? = nil) {
        self.kind = kind; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay; self.alarmOffset = alarmOffset
        self.calendarID = calendarID
        self.recurrence = recurrence
    }

    public func validationError(at now: Date = Date(), calendar: Calendar = .current) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "請補上事項名稱。" }
        if title.count > 200 { return "事項名稱最多 200 字。" }
        if kind == .alarm { return "此模式僅支援行事曆與提醒事項。" }
        if let recurrence, !recurrence.isValid { return "重複間隔請填 1 到 52。" }
        if isAllDay ? calendar.startOfDay(for: start) < calendar.startOfDay(for: now) : start <= now { return "時間已經過去，請調整後再建立。" }
        if kind == .event && (end <= start || end.timeIntervalSince(start) > 7 * 86400 + 3600) { return "結束時間必須晚於開始時間，且不超過 7 天。" }
        if let alarmOffset, !alarmOffset.isFinite || alarmOffset > 0 || alarmOffset < -31 * 86400 { return "提前通知時間超出範圍。" }
        return nil
    }
    /// The reviewed date stays fixed; waiting on a preview never reanchors a relative command.
    public var plan: TaskPlan {
        TaskPlan(kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines), start: start, duration: end.timeIntervalSince(start), isAllDay: isAllDay, alarmOffset: isAllDay ? nil : alarmOffset, calendarID: calendarID, recurrence: recurrence)
    }
}

public enum NaturalTaskFailure: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// One serial JavaScriptCore context, with no network, file or host callbacks exposed to JavaScript.
/// A fixed, vendored Chrono bundle handles dates; Han handles title, intent and validation.
public actor NaturalTaskParser {
    private var context: JSContext?
    public init() {}

    public func parse(_ input: String, mode: TaskComposerMode, now: Date = Date(), calendar: Calendar = .current) throws -> TaskDraft {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, input.count <= 200 else { throw NaturalTaskFailure.invalid("請輸入時間和事項，最多 200 字。") }
        // Era conversion is explicit; a user's display calendar must not change Chrono's Gregorian components.
        var solar = Calendar(identifier: .gregorian); solar.timeZone = calendar.timeZone
        let calendar = solar
        let prepared = try RecurringTaskInput.prepare(input.precomposedStringWithCompatibilityMapping, now: now, calendar: calendar)
        let input = try TaiwanYearConverter.taskInput(prepared?.text ?? input)
        if input.range(of: "農曆|农历|陰曆|阴历", options: .regularExpression) != nil { throw NaturalTaskFailure.invalid("農曆日期尚未支援，請改用國曆日期。") }
        let context = try loadedContext()
        let ref = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let reference = ["year": ref.year!, "month": ref.month!, "day": ref.day!, "hour": ref.hour!, "minute": ref.minute!, "second": ref.second!]
        context.exception = nil
        guard let raw = context.objectForKeyedSubscript("HanDates")?.objectForKeyedSubscript("parse")?.call(withArguments: [input, mode.rawValue, reference]).toString(), context.exception == nil,
              let data = raw.data(using: .utf8) else { throw NaturalTaskFailure.invalid("時間解析暫時無法使用，請重新開啟 Han。") }
        let result = try JSONDecoder().decode(Parsed.self, from: data)
        if let error = result.error { throw NaturalTaskFailure.invalid(error) }
        guard let title = result.title, let value = result.start, let allDay = result.allDay else { throw NaturalTaskFailure.invalid("時間解析暫時無法使用，請重新開啟 Han。") }
        let start = try date(value, allDay: allDay, calendar: calendar)
        let end: Date
        if let value = result.end {
            let parsedEnd = try date(value, allDay: allDay, calendar: calendar)
            end = allDay ? calendar.date(byAdding: .day, value: 1, to: parsedEnd)! : parsedEnd
        } else if allDay { end = calendar.date(byAdding: .day, value: 1, to: start)! }
        else { end = start.addingTimeInterval(result.duration ?? 3600) }
        var draft = TaskDraft(kind: mode.kind, title: title, start: start, end: end, isAllDay: allDay, alarmOffset: result.alarmOffset, recurrence: prepared?.recurrence)
        if let rule = prepared?.recurrence {
            let duration = draft.end.timeIntervalSince(draft.start)
            let days = calendar.dateComponents([.day], from: draft.start, to: draft.end).day ?? 1
            if draft.start < calendar.startOfDay(for: now) || (!allDay && draft.start <= now) {
                guard let next = rule.next(after: draft.start, calendar: calendar) else { throw NaturalTaskFailure.invalid("日期或時間無效，請重新輸入。") }
                draft.start = next
                draft.end = allDay ? calendar.date(byAdding: .day, value: days, to: next)! : next.addingTimeInterval(duration)
            }
        }
        if let error = draft.validationError(at: now, calendar: calendar) { throw NaturalTaskFailure.invalid(error) }
        return draft
    }
    private func loadedContext() throws -> JSContext {
        if let context { return context }
        // Bundle.module's generated fallback embeds the developer's build path. Use relocatable
        // bundle locations instead, both in the .app and beside the SwiftPM check executable.
        let bundleName = "HanSearch_HanSearchCore.bundle"
        let roots = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent(), Bundle.main.bundleURL].compactMap { $0 }
        let url = roots.map { $0.appendingPathComponent(bundleName + "/Resources/NaturalDates.js") }.first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url, let source = try? String(contentsOf: url, encoding: .utf8), let context = JSContext() else { throw NaturalTaskFailure.invalid("缺少時間解析元件，請重新安裝 Han。") }
        context.evaluateScript(source)
        guard context.exception == nil, context.objectForKeyedSubscript("HanDates")?.isUndefined == false else { throw NaturalTaskFailure.invalid("時間解析暫時無法使用，請重新開啟 Han。") }
        self.context = context
        return context
    }
    private func date(_ value: Components, allDay: Bool, calendar: Calendar) throws -> Date {
        let hour = allDay ? 0 : value.hour, minute = allDay ? 0 : value.minute, second = allDay ? 0 : value.second
        let parts = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: value.year, month: value.month, day: value.day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts) else { throw NaturalTaskFailure.invalid("日期或時間無效，請重新輸入。") }
        let actual = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
        guard actual.year == value.year, actual.month == value.month, actual.day == value.day, actual.hour == hour, actual.minute == minute, actual.second == second else { throw NaturalTaskFailure.invalid("日期或時間無效，請重新輸入。") }
        return date
    }
    private struct Components: Decodable { let year: Int; let month: Int; let day: Int; let hour: Int; let minute: Int; let second: Int }
    private struct Parsed: Decodable {
        let error: String?
        let title: String?
        let start: Components?
        let end: Components?
        let allDay: Bool?
        let duration: Double?
        let alarmOffset: Double?
    }
}
