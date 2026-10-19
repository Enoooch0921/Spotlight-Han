import AppKit
import SwiftUI

/// Local drag controls for the borderless launcher. SwiftUI owns the categories;
/// AppKit tracks the pointer without starting a cross-application file drag.
struct AppLibraryDragSource: NSViewRepresentable {
    let payload: String
    let image: NSImage
    let click: () -> Void
    var acceptsDrop: (([String]) -> Bool)? = nil
    var drop: (([String]) -> Bool)? = nil
    var targeted: ((Bool) -> Void)? = nil
    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.payload = payload; view.preview = image; view.click = click
        view.acceptsDrop = acceptsDrop; view.drop = drop; view.targeted = targeted
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.clearDrag() }
    final class SourceView: NSView {
        var payload = ""
        var preview = NSImage()
        var click: (() -> Void)?
        var acceptsDrop: (([String]) -> Bool)?
        var drop: (([String]) -> Bool)?
        var targeted: ((Bool) -> Void)?
        private var origin: NSPoint?
        private var dragged = false
        private weak var hoveredTarget: SourceView?
        private var ghost: DragPreview?
        private var cancellation: NSObjectProtocol?
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { clearDrag(); origin = event.locationInWindow }
        override func mouseDragged(with event: NSEvent) {
            guard let origin else { return }
            if !dragged, hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) < 4 { return }
            if !dragged, let window {
                cancellation = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clearDrag() }
                }
            }
            dragged = true
            updateTarget(event.locationInWindow)
            if let root = window?.contentView {
                let point = root.convert(event.locationInWindow, from: nil)
                if ghost == nil {
                    let image = DragPreview(); image.image = preview; image.imageScaling = .scaleProportionallyUpOrDown
                    image.alphaValue = 0.8; image.setAccessibilityElement(false)
                    root.addSubview(image); ghost = image
                }
                ghost?.frame = NSRect(x: point.x + 8, y: point.y - 22, width: 44, height: 44)
            }
        }
        override func mouseUp(with event: NSEvent) {
            defer { clearDrag() }
            guard origin != nil else { return }
            if dragged {
                updateTarget(event.locationInWindow)
                _ = hoveredTarget?.drop?([payload])
            } else if bounds.contains(convert(event.locationInWindow, from: nil)) { click?() }
        }
        private func updateTarget(_ point: NSPoint) {
            let destination = window?.contentView.flatMap { root in
                destinations(in: root).first { target in
                    target !== self && !target.isHidden && target.visibleRect.contains(target.convert(point, from: nil)) && target.acceptsDrop?([payload]) == true
                }
            }
            if hoveredTarget !== destination { hoveredTarget?.targeted?(false); hoveredTarget = destination; destination?.targeted?(true) }
        }
        private func destinations(in view: NSView) -> [SourceView] {
            if let source = view as? SourceView { return source.drop == nil ? [] : [source] }
            return view.subviews.flatMap { destinations(in: $0) }
        }
        func clearDrag() {
            hoveredTarget?.targeted?(false); hoveredTarget = nil
            ghost?.removeFromSuperview(); ghost = nil; origin = nil; dragged = false
            if let cancellation { NotificationCenter.default.removeObserver(cancellation); self.cancellation = nil }
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { clearDrag() } }
    }
    private final class DragPreview: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
