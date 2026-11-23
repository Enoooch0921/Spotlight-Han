import SwiftUI
import AppKit

/// A row marker lets the panel begin a native drag without taking clicks,
/// contextual menus or accessibility focus away from the SwiftUI result.
struct ResultDragRegion: NSViewRepresentable {
    let payload: SearchResultDrag
    func makeNSView(context: Context) -> Region { Region() }
    func updateNSView(_ view: Region, context: Context) { view.payload = payload }

    final class Region: NSView, NSDraggingSource {
        static let visible = NSHashTable<Region>.weakObjects()
        var payload: SearchResultDrag?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { Self.visible.remove(self) } else { Self.visible.add(self) }
        }
        static func at(_ point: NSPoint, in window: NSWindow) -> Region? {
            visible.allObjects.first { region in
                let local = region.convert(point, from: nil)
                return region.window === window && !region.isHiddenOrHasHiddenAncestor &&
                    region.bounds.contains(local) && region.visibleRect.contains(local)
            }
        }
        func beginDrag(_ payload: SearchResultDrag, with event: NSEvent) {
            let item = payload.draggingItem()
            let point = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(origin: point, size: NSSize(width: 40, height: 40)), contents: payload.icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }
    }
}

/// Only the leading search icon acts as the launcher’s move handle.
struct LauncherMoveHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {}

    final class Handle: NSView {
        private var grabOffset = NSPoint.zero
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { grabOffset = event.locationInWindow }
        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(x: pointer.x - grabOffset.x, y: pointer.y - grabOffset.y))
        }
    }
}
