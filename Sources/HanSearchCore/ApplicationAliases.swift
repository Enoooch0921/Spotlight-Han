import Foundation

/// Curated aliases only: arbitrary initials would make short queries too noisy.
public enum ApplicationAliases {
    /// System app names should remain searchable across macOS display languages.
    public static func localizedNames(bundleID: String?) -> [String] {
        switch bundleID?.lowercased() {
        case "com.apple.terminal": return ["終端機", "終端"]
        case "com.apple.systempreferences": return ["系統設定", "系統設置", "系統偏好設定"]
        case "com.apple.notes": return ["備忘錄"]
        case "com.apple.ical": return ["行事曆", "日曆"]
        case "com.apple.reminders": return ["提醒事項"]
        case "com.apple.calculator": return ["計算機", "計算器"]
        case "com.apple.clock": return ["時鐘"]
        case "com.apple.photos": return ["照片"]
        case "com.apple.textedit": return ["文字編輯", "文本編輯"]
        case "com.apple.preview": return ["預覽"]
        case "com.apple.mail": return ["郵件"]
        case "com.apple.activitymonitor": return ["活動監視器"]
        default: return []
        }
    }
    public static func aliases(name: String, bundleID: String? = nil) -> [String] {
        let title = name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
        let key = ChineseSearch.applicationKey(title)
            .replacingOccurrences(of: "[0-9]+$", with: "", options: .regularExpression)
        switch bundleID?.lowercased() {
        case "com.apple.finalcut": return ["fcp", "fcpx"]
        case "com.apple.logic10": return ["lpx"]
        default: break
        }
        switch key {
        case "finalcutpro", "finalcutprox", "finalcutprocreatorstudio": return ["fcp", "fcpx"]
        case "logicpro", "logicprox", "logicprocreatorstudio": return ["lpx"]
        case "adobephotoshop", "photoshop": return ["ps"]
        case "adobeillustrator", "illustrator": return ["ai"]
        case "adobeaftereffects", "aftereffects": return ["ae"]
        case "adobepremierepro", "premierepro": return ["pr"]
        case "visualstudiocode": return ["vscode"]
        case "microsoftpowerpoint", "powerpoint": return ["ppt"]
        default: return []
        }
    }

    public static func matches(_ query: String, aliases: [String]) -> Bool {
        // An alias is a complete token, never an arbitrary substring such as "cp".
        let needle = ChineseSearch.normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        return aliases.contains { ChineseSearch.normalized($0) == needle }
    }
}
