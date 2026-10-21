import Foundation
import HanSearchCore

enum TaskRecurrenceText {
    static func description(_ rule: TaskRecurrence, start: Date, locale: Locale = L.language.locale) -> String {
        switch rule.frequency {
        case .daily: return rule.interval == 1 ? L.text("每天") : L.format("每 %@ 天", String(rule.interval))
        case .weekly:
            let formatter = DateFormatter(); formatter.locale = locale; formatter.dateFormat = "EEEE"
            return L.format("每 %@ 週：%@", String(rule.interval), formatter.string(from: start))
        case .monthly:
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
            return L.format("每 %@ 個月：%@ 號", String(rule.interval), String(calendar.component(.day, from: start)))
        }
    }
}
