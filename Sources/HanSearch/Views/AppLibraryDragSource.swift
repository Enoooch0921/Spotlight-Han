import AppKit
import SwiftUI

/// Local drag controls for the borderless launcher. SwiftUI owns the categories;
/// AppKit tracks the pointer without starting a cross-application file drag.
struct AppLibraryDragSource: NSViewRepresentable {
    enum IconPlacement { case category, grid, list }
    let payload: String
    let image: NSImage
    let click: () -> Void
    var acceptsDrop: (([String]) -> Bool)? = nil
    var drop: (([String]) -> Bool)? = nil
    var targeted: ((Bool) -> Void)? = nil
    var pressChanged: ((Bool) -> Void)? = nil
    var iconPlacement: IconPlacement = .grid
    @Environment(\.launcherMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> SourceView { SourceView() }
    func updateNSView(_ view: SourceView, context: Context) {
        view.payload = payload; view.preview = image; view.click = click
        view.acceptsDrop = acceptsDrop; view.drop = drop; view.targeted = targeted
        view.pressChanged = pressChanged
        view.iconPlacement = iconPlacement; view.motionEnabled = motionEnabled; view.reduceMotion = reduceMotion
    }
    static func dismantleNSView(_ view: SourceView, coordinator: ()) { view.clearDrag() }
    final class SourceView: NSView {
        var payload = ""
        var preview = NSImage()
        var click: (() -> Void)?
        var acceptsDrop: (([String]) -> Bool)?
        var drop: (([String]) -> Bool)?
        var targeted: ((Bool) -> Void)?
        var pressChanged: ((Bool) -> Void)?
        var iconPlacement: IconPlacement = .grid
        var motionEnabled = true
        var reduceMotion = false
        private var pressed = false
        private var origin: NSPoint?
        private var dragged = false
        private weak var hoveredTarget: SourceView?
        private var ghost: DragPreview?
        private var cancellation: NSObjectProtocol?
        private var keyMonitor: Any?
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            clearDrag(); origin = event.locationInWindow; setPressed(true)
            // Losing the key window must cancel even a click that has not yet
            // crossed the drag threshold (for example switching apps mid-press).
            if let window {
                cancellation = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clearDrag() }
                }
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.dragged, event.keyCode == 53 else { return event }
                self.finishDrag(commit: false)
                return nil
            }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let origin else { return }
            if !dragged, hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) < 4 {
                setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))
                return
            }
            setPressed(false)
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
            guard origin != nil else { return }
            setPressed(false)
            if dragged {
                updateTarget(event.locationInWindow)
                finishDrag(commit: true)
            } else {
                let activate = bounds.contains(convert(event.locationInWindow, from: nil))
                clearDrag()
                if activate { click?() }
            }
        }
        private func iconFrame(in root: NSView) -> NSRect {
            let side: CGFloat = iconPlacement == .category ? 17 : iconPlacement == .list ? 30 : 44
            let x: CGFloat = iconPlacement == .grid ? (bounds.width - side) / 2 : 10
            let y: CGFloat = iconPlacement == .grid ? (isFlipped ? 9 : bounds.height - 9 - side) : (bounds.height - side) / 2
            return convert(NSRect(x: x, y: y, width: side, height: side), to: root)
        }
        private func finishDrag(commit: Bool) {
            guard let root = ghost?.superview, let image = ghost else { clearDrag(); return }
            let target = hoveredTarget
            let home = iconFrame(in: root)
            let destination = target?.iconFrame(in: root)
            let payload = payload
            let animate = motionEnabled, reduced = reduceMotion
            // Transfer the preview before updating SwiftUI. A successful move
            // can remove this source view; its dismantle must not kill landing.
            ghost = nil
            clearDrag()
            let accepted = commit && (target?.drop?([payload]) == true)
            guard animate, root.window?.isVisible == true else { image.removeFromSuperview(); return }
            let end = accepted ? (destination ?? home) : home
            LauncherMotion.perform(duration: reduced ? LauncherMotion.pressDuration : LauncherMotion.resizeDuration, changes: {
                if !reduced { image.animator().frame = end }
                image.animator().alphaValue = 0
            }) { image.removeFromSuperview() }
        }
        private func updateTarget(_ point: NSPoint) {
            let destination = window?.contentView.flatMap { root in
                destinations(in: root).first { target in
                    let local = target.convert(point, from: nil)
                    // SwiftUI's unclipped hosting layers can report a visibleRect
                    // larger than this representable. Require the row's own
                    // bounds too, otherwise empty space can hit the first row.
                    return target !== self && !target.isHiddenOrHasHiddenAncestor &&
                        target.bounds.contains(local) && target.visibleRect.contains(local) &&
                        target.acceptsDrop?([payload]) == true
                }
            }
            if hoveredTarget !== destination { hoveredTarget?.targeted?(false); hoveredTarget = destination; destination?.targeted?(true) }
        }
        private func destinations(in view: NSView) -> [SourceView] {
            if let source = view as? SourceView { return source.drop == nil ? [] : [source] }
            return view.subviews.flatMap { destinations(in: $0) }
        }
        func clearDrag() {
            setPressed(false)
            hoveredTarget?.targeted?(false); hoveredTarget = nil
            ghost?.removeFromSuperview(); ghost = nil; origin = nil; dragged = false
            if let cancellation { NotificationCenter.default.removeObserver(cancellation); self.cancellation = nil }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        }
        private func setPressed(_ value: Bool) {
            guard pressed != value else { return }
            pressed = value; pressChanged?(value)
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { clearDrag() } }
    }
    private final class DragPreview: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
