import SwiftUI
import AppKit
import QuartzCore

/// One small motion vocabulary for the launcher; text and numeric results remain immediate.
enum LauncherMotion {
    static let showDuration = 0.16
    static let hideDuration = 0.125
    static let resizeDuration = 0.18
    @MainActor static func animation(enabled: Bool) -> Animation? {
        enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .timingCurve(0.23, 1, 0.32, 1, duration: showDuration) : nil
    }
    @MainActor static func perform(duration: Double, changes: () -> Void, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            changes()
        } completionHandler: { completion?() }
    }
}
