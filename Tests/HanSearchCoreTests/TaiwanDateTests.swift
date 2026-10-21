import Foundation
import HanSearchCore

extension ChineseSearchTests {
    func testTaiwanDates() async throws {
        let yearCases = ["115年":"西元 2026 年", "民國115年10月":"西元 2026 年 10 月", "民国115年10月5号":"西元 2026 年 10 月 5 日", "2026年":"民國 115 年", "西元2026年":"民國 115 年", "公元2026年10月":"民國 115 年 10 月", "115年換西元":"西元 2026 年", "2026年=民國":"民國 115 年", "１１５年":"西元 2026 年", "民國113年2月29日":"西元 2024 年 2 月 29 日"]
        for (query, answer) in yearCases { precondition(TaiwanYearConverter.result(query)?.text == answer, "Year conversion: \(query)") }
        for query in ["115年.txt", "115年報告", "2026年年度計畫", "民國115年2月29日", "115年13月", "0年", "民國0年", "2026年換西元", "115年換民國", "115", "3年後", "115年10月32日"] { precondition(TaiwanYearConverter.result(query) == nil, "Unexpected year conversion: \(query)") }
        let quick = QuickProvider.results(query: "115年").first { $0.id == "quick:year-conversion" }
        precondition(quick?.title == "西元 2026 年" && quick?.action == .copy("西元 2026 年"))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))! }
        let now = date(2026, 10, 19), parser = NaturalTaskParser()
        func stamp(_ date: Date) -> String {
            let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: date)
        }
        let cases: [(String, TaskComposerMode, String, String, TaskRecurrence?)] = [
            ("每週三晚上七點上課", .event, "上課", "2026-10-21 19:00", TaskRecurrence(.weekly)),
            ("每个星期一上午9点开会", .event, "开会", "2026-10-26 09:00", TaskRecurrence(.weekly)),
            ("每兩週一上午9點開會", .event, "開會", "2026-11-02 09:00", TaskRecurrence(.weekly, interval: 2)),
            ("每週日晚上7點聚會", .event, "聚會", "2026-10-25 19:00", TaskRecurrence(.weekly)),
            ("每天上午9點喝水", .reminder, "喝水", "2026-10-20 09:00", TaskRecurrence(.daily)),
            ("每天9點喝水", .reminder, "喝水", "2026-10-20 09:00", TaskRecurrence(.daily)),
            ("每天上午11點喝水", .reminder, "喝水", "2026-10-19 11:00", TaskRecurrence(.daily)),
            ("每隔兩天上午9點喝水", .reminder, "喝水", "2026-10-21 09:00", TaskRecurrence(.daily, interval: 2)),
            ("每月5號提醒繳房租", .reminder, "繳房租", "2026-11-05 00:00", TaskRecurrence(.monthly)),
            ("每月五日提醒繳房租", .reminder, "繳房租", "2026-11-05 00:00", TaskRecurrence(.monthly)),
            ("每月5号上午9点提醒缴房租", .reminder, "缴房租", "2026-11-05 09:00", TaskRecurrence(.monthly)),
            ("每2個月5號繳房租", .reminder, "繳房租", "2026-12-05 00:00", TaskRecurrence(.monthly, interval: 2)),
            ("民國115年12月5日上午9點開會", .event, "開會", "2026-12-05 09:00", nil),
            ("民国116年1月5日交报告", .reminder, "交报告", "2027-01-05 00:00", nil)
        ]
        for (input, mode, title, start, rule) in cases {
            let draft = try await parser.parse(input, mode: mode, now: now, calendar: calendar)
            precondition(draft.title == title && stamp(draft.start) == start && draft.recurrence == rule, "Recurring parse: \(input) → \(draft.title), \(stamp(draft.start)), \(String(describing: draft.recurrence))")
            precondition(draft.plan.recurrence == rule && draft.plan.resolved(at: now.addingTimeInterval(10)).recurrence == rule)
        }
        let january = date(2027, 1, 31, 11)
        let monthly = try await parser.parse("每月31號上午9點結帳", mode: .event, now: january, calendar: calendar)
        precondition(stamp(monthly.start) == "2027-03-31 09:00", "31st must skip February")
        let leap = TaskRecurrence(.monthly).next(after: date(2028, 1, 29), calendar: calendar)!
        precondition(stamp(leap) == "2028-02-29 10:00")
        let extended = try await parser.parse("每週三晚上7點到8點上課", mode: .event, now: now, calendar: calendar)
        precondition(extended.end.timeIntervalSince(extended.start) == 3600)
        let lead = try await parser.parse("每週三晚上7點上課提前10分鐘提醒", mode: .event, now: now, calendar: calendar)
        precondition(lead.alarmOffset == -600)
        for input in ["每週晚上7點上課", "每月32號繳房租", "每0週三晚上7點上課", "每一二週三晚上7點上課", "每53週三晚上7點上課", "每週三、五晚上7點上課", "每週三晚上7點上課直到12月31日", "每年10月5日開會", "農曆8月15日聚會", "民國115年2月30日開會", "民國115年10月開會", "民國0年12月5日開會", "每週三晚上7點", "每月5號"] {
            do { _ = try await parser.parse(input, mode: .event, now: now, calendar: calendar); preconditionFailure("Unsupported recurrence/date silently accepted: \(input)") }
            catch is NaturalTaskFailure { }
        }
        for input in ["每週三晚上7點開會", "每月5號上午9點開會", "民國116年1月5日上午9點開會"] {
            precondition(TaskCommandParser.parse(input, now: now, calendar: calendar) == nil, "Legacy parser must not discard recurrence or era")
        }
        var invalid = extended; invalid.recurrence?.interval = 0; precondition(invalid.validationError(at: now, calendar: calendar) != nil)
        print("PASS: era years/months/dates, bare year queries, recurring daily/weekly/monthly drafts, intervals, next occurrence, short months/leap day, validation and preview plan preservation")
    }
}
