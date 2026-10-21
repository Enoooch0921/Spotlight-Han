import Foundation

public struct TaskRecurrence: Hashable, Sendable {
    public enum Frequency: String, CaseIterable, Sendable { case daily, weekly, monthly }
    public var frequency: Frequency
    public var interval: Int
    public init(_ frequency: Frequency, interval: Int = 1) { self.frequency = frequency; self.interval = interval }
    public var isValid: Bool { (1...52).contains(interval) }

    /// Uses the reviewed start date as the weekday/month-day anchor, just like EventKit.
    public func next(after date: Date, calendar: Calendar) -> Date? {
        guard isValid else { return nil }
        if frequency != .monthly { return calendar.date(byAdding: frequency == .daily ? .day : .weekOfYear, value: interval, to: date) }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let month = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) else { return nil }
        // Never clamp the 31st to the end of a short month. Match EventKit's BYMONTHDAY.
        for step in 1...24 {
            guard let target = calendar.date(byAdding: .month, value: step * interval, to: month) else { return nil }
            var candidate = calendar.dateComponents([.year, .month], from: target)
            candidate.day = parts.day; candidate.hour = parts.hour; candidate.minute = parts.minute; candidate.second = parts.second
            if let value = calendar.date(from: candidate), calendar.component(.month, from: value) == candidate.month, calendar.component(.day, from: value) == parts.day { return value }
        }
        return nil
    }
}

enum RecurringTaskInput {
    struct Prepared { let text: String; let recurrence: TaskRecurrence }
    static func prepare(_ input: String, now: Date, calendar: Calendar) throws -> Prepared? {
        let pattern = #"^\s*(?:(?:請|请|幫我|帮我|新增|添加|建立|安排|提醒事項|提醒事项|提醒我|提醒|行事曆|行事历|行程)[：:\s]*)*每(?:隔)?([0-9零〇一二兩两三四五六七八九十]+)?(?:個|个)?(星期|禮拜|礼拜|週|周|天|日|月)\s*([0-9一二三四五六七八九十日天]+)?(?:日|號|号)?\s*"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)), let range = Range(match.range, in: input) else { return nil }
        func part(_ index: Int) -> String { Range(match.range(at: index), in: input).map { String(input[$0]) } ?? "" }
        let interval = part(1).isEmpty ? 1 : integer(part(1)) ?? 0
        let token = part(2), day = part(3)
        var remainder = String(input[range.upperBound...])
        let frequency: TaskRecurrence.Frequency = token == "月" ? .monthly : (["天", "日"].contains(token) ? .daily : .weekly)
        let rule = TaskRecurrence(frequency, interval: interval)
        guard rule.isValid else { throw NaturalTaskFailure.invalid("重複間隔請填 1 到 52。") }
        var anchor = calendar.startOfDay(for: now)
        switch frequency {
        case .daily:
            remainder = day + remainder
        case .weekly:
            let weekday: Int
            if ["日", "天", "7"].contains(day) { weekday = 1 }
            else if let value = integer(day), (1...6).contains(value) { weekday = value + 1 }
            else { throw NaturalTaskFailure.invalid("請指定每週的星期幾，例如「每週三晚上7點上課」。") }
            anchor = calendar.date(byAdding: .day, value: (weekday - calendar.component(.weekday, from: anchor) + 7) % 7, to: anchor)!
        case .monthly:
            guard let value = integer(day.hasSuffix("日") ? String(day.dropLast()) : day), (1...31).contains(value) else { throw NaturalTaskFailure.invalid("請指定每月 1 到 31 號，例如「每月5號提醒繳房租」。") }
            let parts = calendar.dateComponents([.year, .month], from: anchor)
            let month = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1))!
            var found: Date?
            for step in 0...12 {
                let target = calendar.date(byAdding: .month, value: step, to: month)!
                var candidate = calendar.dateComponents([.year, .month], from: target); candidate.day = value
                if let date = calendar.date(from: candidate), calendar.component(.day, from: date) == value { found = date; break }
            }
            guard let date = found else { throw NaturalTaskFailure.invalid("日期或時間無效，請重新輸入。") }; anchor = date
        }
        if remainder.range(of: #"^(?:[、，,/]|和|及|與|与)\s*(?:星期|週|周)?[一二三四五六七日天1-7]|直到|截止|截至|結束於|结束于|共\s*[0-9一二三四五六七八九十]+\s*次"#, options: .regularExpression) != nil {
            throw NaturalTaskFailure.invalid("目前支援每天、每週一個星期幾、每月一個日期；結束條件請在系統 App 調整。")
        }
        let components = calendar.dateComponents([.year, .month, .day], from: anchor)
        return Prepared(text: "\(components.year!)年\(components.month!)月\(components.day!)日 " + remainder, recurrence: rule)
    }
    private static func integer(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let digits: [Character: Int] = ["零":0,"〇":0,"一":1,"二":2,"兩":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
        if text.count == 1, let char = text.first { return char == "十" ? 10 : digits[char] }
        let parts = text.split(separator: "十", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count <= 1, parts[1].count <= 1 else { return nil }
        let tens = parts[0].isEmpty ? 1 : parts[0].first.flatMap { digits[$0] }
        let ones = parts[1].isEmpty ? 0 : parts[1].first.flatMap { digits[$0] }
        guard let tens, let ones, tens > 0 else { return nil }
        return tens * 10 + ones
    }
}
