import Foundation

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    /// Carbon modifier mask, stored without a keyboard-layout-specific character.
    public let modifiers: UInt32
    public let keyLabel: String
    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    public static let standard = ShortcutBinding(keyCode: 49, modifiers: 4096 | 2048, keyLabel: "Space")
    public static let commandSpace = ShortcutBinding(keyCode: 49, modifiers: 256, keyLabel: "Space")
    public var isValid: Bool { keyCode <= 127 && modifiers & (256 | 4096 | 2048) != 0 && modifiers & ~UInt32(256 | 512 | 2048 | 4096) == 0 }
    public var display: String {
        (modifiers & 4096 != 0 ? "⌃" : "") + (modifiers & 2048 != 0 ? "⌥" : "") + (modifiers & 512 != 0 ? "⇧" : "") + (modifiers & 256 != 0 ? "⌘" : "") + keyLabel
    }
}
