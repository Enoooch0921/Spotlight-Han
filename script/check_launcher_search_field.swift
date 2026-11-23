import AppKit
import SwiftUI

@MainActor private final class QueryState {
    var query = "HanNoMatchFixture"
    var focused = true
    var submissions = 0
    var moves = 0
    var escapes = 0
}

private final class TestField: NSTextField {
    let editor = NSTextView()
    override func currentEditor() -> NSText? { editor }
}

@main struct LauncherSearchFieldChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let state = QueryState()
        let view = LauncherSearchField(
            text: Binding(get: { state.query }, set: { state.query = $0 }),
            focused: Binding(get: { state.focused }, set: { state.focused = $0 }),
            placeholder: "Spotlight Han 搜尋", accessibilityLabel: "Search", enabled: true,
            submit: { state.submissions += 1 }, tab: { true },
            move: { state.moves += $0; return true }, escape: { state.escapes += 1 })
        let coordinator = view.makeCoordinator()
        let field = TestField(string: state.query)
        let changed = Notification(name: NSControl.textDidChangeNotification, object: field,
                                   userInfo: ["NSFieldEditor": field.editor])

        // The exact failure: the visible editor was cleared while the control's
        // committed value still contains the previous search. Empty is an edit.
        let staleControl = NSTextField(string: state.query)
        field.editor.string = ""
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: staleControl,
                                                       userInfo: ["NSFieldEditor": field.editor]))
        precondition(state.query.isEmpty && !staleControl.stringValue.isEmpty)

        for text in ["騰訊會議", "腾讯会议", "", "HanNoMatchFixture", ""] {
            field.editor.string = text
            coordinator.controlTextDidChange(changed)
            coordinator.parent.placeholder = "搜尋應用程式…"
            coordinator.applyModel(to: field)
            precondition(state.query == text && field.editor.string == text)
        }

        field.editor.setMarkedText("ㄊㄒ", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.controlTextDidChange(changed)
        coordinator.applyModel(to: field)
        precondition(field.editor.hasMarkedText() && state.query == field.editor.string)
        precondition(!coordinator.control(field, textView: field.editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        precondition(!coordinator.control(field, textView: field.editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        precondition(state.submissions == 0 && state.escapes == 0)

        // Explicit clear/reset synchronizes both the active editor and the model.
        state.query = ""
        coordinator.applyModel(to: field)
        precondition(field.editor.string.isEmpty && field.stringValue.isEmpty && !field.editor.hasMarkedText())
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        precondition(state.query.isEmpty && !state.focused)
        coordinator.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        precondition(state.focused)
        state.query = "cal"
        coordinator.applyModel(to: field)
        precondition(field.editor.string == "cal" && field.stringValue == "cal")
        precondition(coordinator.control(field, textView: field.editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        precondition(coordinator.control(field, textView: field.editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        precondition(coordinator.control(field, textView: field.editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        precondition(coordinator.control(field, textView: field.editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        precondition(state.submissions == 1 && state.moves == 1 && state.escapes == 1)
        precondition(!coordinator.control(field, textView: field.editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        print("PASS: empty edit replaces stale committed query, Chinese/English edits, mode placeholder changes, marked-text preservation, explicit reset, focus and command routing; synthetic text only")
    }
}
