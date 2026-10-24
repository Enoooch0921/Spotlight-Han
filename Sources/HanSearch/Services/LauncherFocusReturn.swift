import AppKit

/// One launcher session remembers its origin. Consume once and only while Han
/// still owns activation, so a delayed fade cannot pull focus from a new app.
struct LauncherFocusSession<Target: Equatable> {
    private(set) var origin: Target?
    mutating func capture(_ frontmost: Target?, owner: Target) {
        if let frontmost, frontmost != owner { origin = frontmost }
    }
    mutating func discard() { origin = nil }
    mutating func takeReturnTarget(frontmost: Target?, owner: Target, hasOtherKeyWindow: Bool) -> Target? {
        defer { discard() }
        guard frontmost == owner, !hasOtherKeyWindow else { return nil }
        return origin
    }
}

@MainActor
final class LauncherFocusReturn {
    private var session = LauncherFocusSession<NSRunningApplication>()
    func capture() {
        session.capture(NSWorkspace.shared.frontmostApplication, owner: .current)
    }
    func discard() { session.discard() }
    func restore(excluding panel: NSWindow) {
        let otherKeyWindow = NSApp.keyWindow.map { $0 !== panel && $0.isVisible } ?? false
        guard let origin = session.takeReturnTarget(frontmost: NSWorkspace.shared.frontmostApplication,
                                                   owner: .current, hasOtherKeyWindow: otherKeyWindow),
              !origin.isTerminated else { return }
        // Reactivate the existing app without reopening documents or raising all
        // its windows. Its existing text responder/caret remain under its control.
        NSApp.yieldActivation(to: origin)
        origin.activate(options: [])
    }
}
