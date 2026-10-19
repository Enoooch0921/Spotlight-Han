import Foundation

public struct TaskPlan: Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case alarm, reminder, event }
    public let kind: Kind
    public let title: String
    public let start: Date
    public let duration: TimeInterval
    public let relativeDelay: TimeInterval?

    public init(kind: Kind, title: String, start: Date, duration: TimeInterval = 3600, relativeDelay: TimeInterval? = nil) {
        self.kind = kind; self.title = title; self.start = start; self.duration = duration; self.relativeDelay = relativeDelay
    }
    public func resolved(at now: Date) -> TaskPlan {
        TaskPlan(kind: kind, title: title, start: relativeDelay.map { now.addingTimeInterval($0) } ?? start, duration: duration, relativeDelay: relativeDelay)
    }
}

public enum TaskCommandParser {
    private static let numberPattern = #"(?:[0-9]+(?:\.[0-9]+)?|[零〇一二兩两三四五六七八九十百]+|半)"#

    public static func parse(_ original: String, now: Date = Date(), calendar: Calendar = .current) -> TaskPlan? {
        guard original.count <= 200 else { return nil }
        let text = ChineseSearch.simplified(original).trimmingCharacters(in: .whitespacesAndNewlines)
        // Relative timers: "設定30分鐘後的鬧鐘", "倒數半小時", "提醒我10分鐘後喝水".
        let relativePattern = "(" + numberPattern + #")\s*(小时|分钟|分|秒钟|秒|天)\s*(?:之后|以后|后)?"#
        if let relative = capture(relativePattern, in: text), String(text[..<relative.range.lowerBound]).range(of: #"^(?:(?:请|帮我|设定|设置|新增|添加|一个|闹钟|倒数|倒计时|计时器|计时|提醒我|提醒|启动|开始|在)\s*)*$"#, options: .regularExpression) != nil, let value = number(relative.parts[0]), value > 0 {
            let factor: Double = relative.parts[1] == "小时" ? 3600 : (relative.parts[1] == "天" ? 86400 : (["分钟", "分"].contains(relative.parts[1]) ? 60 : 1))
            let delay = value * factor
            guard delay >= 1, delay <= 31 * 86400 else { return nil }
            let isAlarm = text.contains("闹钟")
            let isReminder = text.hasPrefix("提醒") || text.hasPrefix("新增提醒") || text.hasPrefix("添加提醒")
            if isAlarm || isReminder {
                let suffix = String(text[relative.range.upperBound...])
                if let next = capture(relativePattern, in: suffix), next.range.lowerBound == suffix.startIndex { return nil }
                let cleaned = suffix.replacingOccurrences(of: #"^[的，,:：\s]+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^(?:闹钟|提醒事项|提醒|计时器)[：:\s]*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title = cleaned.isEmpty ? (isAlarm ? "時間到了" : "提醒事項") : cleaned
                return TaskPlan(kind: isAlarm ? .alarm : .reminder, title: originalTitle(title, in: text, original: original), start: now.addingTimeInterval(delay), relativeDelay: delay)
            }
        }

        // Explicit local date/time. Ambiguous or incomplete commands produce no write action.
        let isReminder = text.hasPrefix("提醒") || text.hasPrefix("新增提醒") || text.hasPrefix("添加提醒")
        let isAlarm = text.contains("闹钟")
        let timePattern = #"(上午|早上|下午|晚上|中午|凌晨)?\s*("# + numberPattern + #")\s*(?:[:：](\d{1,2})|点(?:([零〇一二兩两三四五六七八九十百0-9]+)分?)?(半)?)"#
        guard let time = capture(timePattern, in: text), let rawHour = number(time.parts[1]), rawHour.rounded() == rawHour else { return nil }
        var hour = Int(rawHour), minute = 0
        if !time.parts[2].isEmpty { minute = Int(time.parts[2]) ?? -1 }
        else if !time.parts[3].isEmpty { minute = Int(number(time.parts[3]) ?? -1) }
        else if !time.parts[4].isEmpty { minute = 30 }
        let period = time.parts[0]
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if !period.isEmpty {
            guard (0...12).contains(hour) else { return nil }
            if ["下午", "晚上"].contains(period), hour < 12 { hour += 12 }
            if ["上午", "早上", "凌晨"].contains(period), hour == 12 { hour = 0 }
            if period == "中午", hour < 11 { hour += 12 }
        }
        var dayOffset = 0
        var explicitDate = false
        if text.contains("明天") { dayOffset = 1; explicitDate = true }
        else if text.contains("后天") { dayOffset = 2; explicitDate = true }
        else if text.contains("今天") || text.contains("今晚") { explicitDate = true }
        let base = calendar.date(byAdding: .day, value: dayOffset, to: now)!
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        if let date = capture(#"(?:(\d{4})[-/年])?(\d{1,2})[-/月](\d{1,2})(?:日|号)?"#, in: text) {
            if !date.parts[0].isEmpty { components.year = Int(date.parts[0]) }
            components.month = Int(date.parts[1]); components.day = Int(date.parts[2]); explicitDate = true
        }
        components.hour = hour; components.minute = minute; components.second = 0
        guard var start = calendar.date(from: components) else { return nil }
        let verified = calendar.dateComponents([.month, .day, .hour, .minute], from: start)
        guard verified.month == components.month, verified.day == components.day, verified.hour == hour, verified.minute == minute else { return nil }
        if start <= now {
            if explicitDate { return nil }
            start = calendar.date(byAdding: .day, value: 1, to: start)!
        }
        var title = String(text[time.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.replacingOccurrences(of: #"^[的，,:：\s]+"#, with: "", options: .regularExpression)
        var duration: Double = 3600
        if !isReminder && !isAlarm, let length = capture("(" + numberPattern + #")\s*(小时|分钟|分)\s*$"#, in: title), let value = number(length.parts[0]), value > 0 {
            duration = value * (length.parts[1] == "小时" ? 3600 : 60)
            title = String(title[..<length.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard duration <= 7 * 86400 else { return nil }
        title = title.replacingOccurrences(of: #"^(?:的)?(?:闹钟|提醒事项)[：:\s]*"#, with: "", options: .regularExpression)
        // Event creation requires a date or a clear event verb. A bare clock time is not a command.
        if !isReminder && !isAlarm {
            guard explicitDate || ["行程", "行事历", "会议", "开会", "安排", "预约"].contains(where: text.contains), !title.isEmpty else { return nil }
        }
        if title.isEmpty { title = isAlarm ? "時間到了" : "提醒事項" }
        return TaskPlan(kind: isAlarm ? .alarm : (isReminder ? .reminder : .event), title: originalTitle(title, in: text, original: original), start: start, duration: duration)
    }

    private static func originalTitle(_ title: String, in normalized: String, original: String) -> String {
        guard let range = normalized.range(of: title, options: .backwards), let originalRange = Range(NSRange(range, in: normalized), in: original) else { return title }
        let candidate = String(original[originalRange])
        return ChineseSearch.simplified(candidate) == title ? candidate : title
    }

    private static func capture(_ pattern: String, in text: String) -> (parts: [String], range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range, in: text) else { return nil }
        let parts = (1..<match.numberOfRanges).map { i -> String in
            guard let range = Range(match.range(at: i), in: text) else { return "" }; return String(text[range])
        }
        return (parts, range)
    }
    private static func number(_ raw: String) -> Double? {
        if raw == "半" { return 0.5 }
        if let value = Double(raw) { return value }
        let digits: [Character: Int] = ["零":0, "〇":0, "一":1, "二":2, "兩":2, "两":2, "三":3, "四":4, "五":5, "六":6, "七":7, "八":8, "九":9]
        var value = 0, digit = 0
        for char in raw {
            if let n = digits[char] { digit = n }
            else if char == "十" { value += max(digit, 1) * 10; digit = 0 }
            else if char == "百" { value += max(digit, 1) * 100; digit = 0 }
            else { return nil }
        }
        return Double(value + digit)
    }
}
