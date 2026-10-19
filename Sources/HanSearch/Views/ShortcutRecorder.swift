import AppKit
import SwiftUI
import Carbon
import HanSearchCore

struct ShortcutRecorder: NSViewRepresentable {
    let title: String
    let changed: (ShortcutBinding) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton(title: title, target: nil, action: nil)
        view.bezelStyle = .rounded; view.target = view; view.action = #selector(RecorderButton.beginRecording)
        view.changed = changed; return view
    }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.savedTitle = title; view.changed = changed
        if !view.recording { view.title = title }
    }
}

final class RecorderButton: NSButton {
    var changed: ((ShortcutBinding) -> Void)?
    var savedTitle = "設定快捷鍵"
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() {
        recording = true; title = L.text("按下快捷鍵（Esc 取消）"); window?.makeFirstResponder(self)
    }
    override func resignFirstResponder() -> Bool { recording = false; title = savedTitle; return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == kVK_Escape { recording = false; title = savedTitle; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let label: String
        switch Int(event.keyCode) {
        case kVK_Space: label = "Space"
        case kVK_Return: label = "Return"
        case kVK_Tab: label = "Tab"
        case kVK_Delete: label = "⌫"
        case kVK_LeftArrow: label = "←"
        case kVK_RightArrow: label = "→"
        case kVK_UpArrow: label = "↑"
        case kVK_DownArrow: label = "↓"
        default: label = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
        let binding = ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: carbon, keyLabel: label)
        guard binding.isValid else { title = L.text("請搭配 ⌘、⌃ 或 ⌥"); return }
        recording = false; title = savedTitle; changed?(binding)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}
