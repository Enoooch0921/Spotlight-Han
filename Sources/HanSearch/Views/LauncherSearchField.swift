import AppKit
import SwiftUI

/// A single native editor survives changes between search, Apps and the composer.
/// Publish the field editor's value (including an empty edit) immediately, instead
/// of allowing its display and the query used to filter Apps to drift apart.
struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder: String
    var accessibilityLabel: String
    var enabled: Bool
    var inspectDroppedFile: ((URL) -> Void)? = nil
    var submit: () -> Void
    var tab: () -> Bool
    var move: (Int) -> Bool
    var escape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        if let cell = field.cell as? NSTextFieldCell {
            let dropCell = LauncherFieldCell(textCell: text)
            dropCell.isEditable = cell.isEditable
            dropCell.isSelectable = cell.isSelectable
            field.cell = dropCell
        }
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 25)
        field.textColor = .labelColor
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        (field.cell as? NSTextFieldCell)?.setWantsNotificationForMarkedText(true)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityIdentifier("launcher-search-field")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        (field.cell as? LauncherFieldCell)?.editor.inspectFile = inspectDroppedFile
        field.placeholderString = placeholder
        field.setAccessibilityLabel(accessibilityLabel)
        field.isEnabled = enabled
        coordinator.applyModel(to: field)
        // Focus changes cannot synchronously publish state during a SwiftUI update.
        coordinator.focusGeneration += 1
        let generation = coordinator.focusGeneration
        DispatchQueue.main.async { [weak field, weak coordinator] in
            guard let field, let coordinator, coordinator.focusGeneration == generation,
                  let window = field.window else { return }
            if coordinator.parent.focused && field.isEnabled && window.isKeyWindow {
                if field.currentEditor() == nil { window.makeFirstResponder(field) }
            } else if !coordinator.parent.focused, let editor = field.currentEditor(), window.firstResponder === editor {
                window.makeFirstResponder(nil)
            }
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.focusGeneration += 1
        field.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherSearchField
        var focusGeneration = 0
        private var lastText: String

        init(_ parent: LauncherSearchField) {
            self.parent = parent
            lastText = parent.text
        }

        func applyModel(to field: NSTextField) {
            // Unrelated result updates must not replace marked Chinese input or
            // move the caret. Only an actual model edit (clear/reset) writes back.
            guard parent.text != lastText else { return }
            lastText = parent.text
            if let editor = field.currentEditor() as? NSTextView, editor.string != parent.text {
                let selection = editor.selectedRange()
                editor.unmarkText()
                editor.string = parent.text
                let length = (parent.text as NSString).length
                editor.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            }
            if field.stringValue != parent.text { field.stringValue = parent.text }
        }

        private func publish(_ field: NSTextField, editor: NSText? = nil) {
            let value = (editor ?? field.currentEditor())?.string ?? field.stringValue
            lastText = value
            if parent.text != value { parent.text = value }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            publish(field, editor: notification.userInfo?["NSFieldEditor"] as? NSText)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.focused { parent.focused = true }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            publish(field)
            if parent.focused { parent.focused = false }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            // Return/arrows/Escape belong to the input method while choosing a
            // Chinese candidate; never open an App or dismiss the launcher then.
            guard !textView.hasMarkedText() else { return false }
            switch command {
            case #selector(NSResponder.insertNewline(_:)): parent.submit(); return true
            case #selector(NSResponder.insertTab(_:)): return parent.tab()
            case #selector(NSResponder.moveDown(_:)): return parent.move(1)
            case #selector(NSResponder.moveUp(_:)): return parent.move(-1)
            case #selector(NSResponder.cancelOperation(_:)): parent.escape(); return true
            default: return false
            }
        }
    }
}

/// AppKit's shared field editor can otherwise consume a Finder drop as text
/// before the surrounding SwiftUI drop destination receives the file.
private final class LauncherFieldCell: NSTextFieldCell {
    let editor: FileDropFieldEditor = {
        let editor = FileDropFieldEditor()
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.drawsBackground = false
        return editor
    }()
    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

private final class FileDropFieldEditor: NSTextView {
    var inspectFile: ((URL) -> Void)?
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { super.acceptableDragTypes + [.fileURL] }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(.fileURL) == true { return fileOperation(sender) }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.types?.contains(.fileURL) == true { return fileOperation(sender) }
        return super.draggingUpdated(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if sender.draggingPasteboard.types?.contains(.fileURL) == true { return fileOperation(sender) == .copy }
        return super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        guard board.types?.contains(.fileURL) == true else { return super.performDragOperation(sender) }
        guard fileOperation(sender) == .copy, let inspectFile,
              let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              urls.count == 1 else { return false }
        inspectFile(urls[0])
        return true
    }
    private func fileOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        inspectFile != nil && sender.draggingSource == nil && sender.draggingPasteboard.pasteboardItems?.count == 1 ? .copy : []
    }
}
