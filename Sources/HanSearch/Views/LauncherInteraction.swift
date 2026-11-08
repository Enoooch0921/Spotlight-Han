import SwiftUI

private struct LauncherMotionEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var launcherMotionEnabled: Bool {
        get { self[LauncherMotionEnabledKey.self] }
        set { self[LauncherMotionEnabledKey.self] = newValue }
    }
}

/// Also accepts the press owned by the AppKit drag overlay. No gesture is added
/// here: buttons retain their activation, cancellation and keyboard semantics.
struct LauncherButtonStyle: ButtonStyle {
    var externalPressed = false
    var shape = AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    @Environment(\.launcherMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && (configuration.isPressed || externalPressed)
        configuration.label
            .overlay { shape.fill(.primary.opacity(pressed ? 0.07 : 0)).allowsHitTesting(false) }
            .scaleEffect(pressed && motionEnabled && !reduceMotion ? 0.97 : 1)
            .animation(LauncherMotion.feedback(enabled: motionEnabled, pressed: pressed), value: pressed)
            // The visual press must not shrink the interaction region and
            // cancel a click near the original circle/row edge.
            .contentShape(.interaction, shape)
    }
}

private struct LauncherSelectionAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct LauncherSelectionBackground: ViewModifier {
    let selection: String?
    let cornerRadius: CGFloat
    @Environment(\.launcherMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.backgroundPreferenceValue(LauncherSelectionAnchors.self) { anchors in
            GeometryReader { geometry in
                if let selection, let anchor = anchors[selection] {
                    let rect = geometry[anchor]
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.primary.opacity(0.10))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        // The moving shape is independent of the labels and results.
                        .animation(LauncherMotion.selection(enabled: motionEnabled, reduceMotion: reduceMotion), value: rect)
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

extension View {
    func launcherSelectionAnchor(_ id: String) -> some View {
        anchorPreference(key: LauncherSelectionAnchors.self, value: .bounds) { [id: $0] }
    }
    func launcherSelectionBackground(_ selection: String?, cornerRadius: CGFloat) -> some View {
        modifier(LauncherSelectionBackground(selection: selection, cornerRadius: cornerRadius))
    }
    @ViewBuilder func launcherGlassIdentity(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26, *) {
            // Keep the material live. Only the content inside it crossfades;
            // a group opacity transition can flatten the sampled backdrop.
            self.glassEffectID(id, in: namespace).glassEffectTransition(.identity)
        } else { self }
    }
}
