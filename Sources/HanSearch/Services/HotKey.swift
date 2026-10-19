import AppKit
import Carbon
import HanSearchCore

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var binding: ShortcutBinding?
    private var nextID: UInt32 = 1
    var action: (() -> Void)?

    @MainActor static func systemConflict(_ requested: ShortcutBinding) -> String? {
        // The public Carbon list catches enabled system combinations, including customized ones.
        var items: Unmanaged<CFArray>?
        if CopySymbolicHotKeys(&items) == noErr, let values = items?.takeRetainedValue() as? [[String: Any]] {
            let matches = values.contains { value in
                (value[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
                (value[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == requested.keyCode &&
                (value[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == requested.modifiers
            }
            if matches {
                return requested == .commandSpace ? "⌘Space 仍被系統使用。請先關閉 Spotlight 的「顯示 Spotlight 搜尋」；也請檢查「顯示應用程式」是否使用相同組合。" : "\(requested.display) 已被系統快捷鍵使用，請改用其他組合，或先到系統鍵盤設定調整。"
            }
        }
        // The Spotlight-specific record is useful even when the running symbolic-key cache is stale.
        if let values = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any],
           let record = values["64"] as? [String: Any], let spotlight = SystemShortcutPreference.enabledBinding(record),
           SystemShortcutPreference.sameKeys(spotlight, requested) {
            return "Spotlight 的 \(requested.display) 仍然開啟。請先關閉系統 Spotlight 快捷鍵，再回來設定 Han。"
        }
        return nil
    }

    /// Acquire the new binding before releasing the old one so a conflict never strands the user.
    func register(_ requested: ShortcutBinding = .standard) -> Bool {
        guard requested.isValid else { return false }
        if binding == requested, reference != nil { return true }
        if handler == nil {
            var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let context = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
                guard let pointer else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<HotKey>.fromOpaque(pointer).takeUnretainedValue()
                DispatchQueue.main.async { service.action?() }
                return noErr
            }, 1, &specification, context, &handler)
            guard status == noErr else { return false }
        }
        var candidate: EventHotKeyRef?
        nextID &+= 1
        let identifier = EventHotKeyID(signature: 0x48414E53, id: nextID)
        guard RegisterEventHotKey(requested.keyCode, requested.modifiers, identifier, GetApplicationEventTarget(), 0, &candidate) == noErr else { return false }
        if let reference { UnregisterEventHotKey(reference) }
        reference = candidate; binding = requested
        return true
    }
    func matches(_ event: NSEvent) -> Bool {
        guard let binding, UInt32(event.keyCode) == binding.keyCode else { return false }
        var mask: UInt32 = 0
        if event.modifierFlags.contains(.command) { mask |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { mask |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { mask |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask == binding.modifiers
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
