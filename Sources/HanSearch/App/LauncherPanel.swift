import AppKit

final class LauncherPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        // AppKit can start a server-side window move before a result row
        // crosses the system drag threshold. Only the search icon may move us.
        isMovableByWindowBackground = false
        isMovable = false
    }

    var command: ((String) -> Bool)?
    var dismiss: (() -> Void)?
    private weak var dragRegion: ResultDragRegion.Region?
    private var dragPayload: SearchResultDrag?
    private var dragOrigin = NSPoint.zero

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragOrigin = event.locationInWindow
            dragRegion = ResultDragRegion.Region.at(dragOrigin, in: self)
            dragPayload = dragRegion?.payload
        case .leftMouseDragged:
            if let region = dragRegion, let payload = dragPayload, hypot(event.locationInWindow.x - dragOrigin.x, event.locationInWindow.y - dragOrigin.y) >= 4 {
                dragRegion = nil
                dragPayload = nil
                region.beginDrag(payload, with: event)
                return
            }
        case .leftMouseUp:
            dragRegion = nil
            dragPayload = nil
        default: break
        }
        super.sendEvent(event)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command, let key = event.charactersIgnoringModifiers, command?(key) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { if let dismiss { dismiss() } else { orderOut(nil) } }
}
