import Foundation

/// Reads one system symbolic shortcut record without changing the user's keyboard settings.
public enum SystemShortcutPreference {
    public static func enabledBinding(_ record: [String: Any]) -> ShortcutBinding? {
        guard let enabled = record["enabled"] as? Bool, enabled,
              let value = record["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber], parameters.count == 3 else { return nil }
        let keyCode = parameters[1].int64Value, cocoa = parameters[2].int64Value
        guard (0...127).contains(keyCode), cocoa >= 0 else { return nil }
        var carbon: UInt32 = 0
        if cocoa & (1 << 17) != 0 { carbon |= 512 }
        if cocoa & (1 << 18) != 0 { carbon |= 4096 }
        if cocoa & (1 << 19) != 0 { carbon |= 2048 }
        if cocoa & (1 << 20) != 0 { carbon |= 256 }
        return ShortcutBinding(keyCode: UInt32(keyCode), modifiers: carbon, keyLabel: "Space")
    }
    public static func sameKeys(_ lhs: ShortcutBinding, _ rhs: ShortcutBinding) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }
}
