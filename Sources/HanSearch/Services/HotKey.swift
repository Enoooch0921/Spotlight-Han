import AppKit
import Carbon
import HanSearchCore

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var binding: ShortcutBinding?
    private var nextID: UInt32 = 1
    var action: (() -> Void)?

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
