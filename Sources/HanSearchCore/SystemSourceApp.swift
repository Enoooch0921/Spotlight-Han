import Foundation

/// The system app that owns a result or receives a reviewed creation command.
public enum SystemSourceApp: String, CaseIterable, Sendable {
    case notes = "com.apple.Notes"
    case contacts = "com.apple.AddressBook"
    case calendar = "com.apple.iCal"
    case reminders = "com.apple.reminders"
    case mail = "com.apple.mail"
    case shortcuts = "com.apple.shortcuts"
    case clock = "com.apple.clock"
    case settings = "com.apple.systempreferences"
    case dictionary = "com.apple.Dictionary"

    public init?(_ source: SearchMode) {
        switch source {
        case .notes: self = .notes
        case .contacts: self = .contacts
        case .calendar: self = .calendar
        case .reminders: self = .reminders
        case .mail: self = .mail
        case .shortcuts: self = .shortcuts
        case .alarms: self = .clock
        default: return nil
        }
    }
    public var title: String {
        switch self {
        case .notes: return "備忘錄"
        case .contacts: return "聯絡人"
        case .calendar: return "行事曆"
        case .reminders: return "提醒事項"
        case .mail: return "郵件"
        case .shortcuts: return "捷徑"
        case .clock: return "時鐘"
        case .settings: return "系統設定"
        case .dictionary: return "辭典"
        }
    }
}
