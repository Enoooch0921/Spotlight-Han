import Foundation

/// Curated aliases only: arbitrary initials would make short queries too noisy.
public enum ApplicationAliases {
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
        aliases.contains(ChineseSearch.normalized(query).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
