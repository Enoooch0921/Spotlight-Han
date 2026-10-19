/// AppKit may keep isVisible true for a floating panel hidden on app deactivation.
/// A hotkey should show that panel on its first press, rather than dismiss stale state.
public struct LauncherPresentation: Sendable {
    public enum Action: Equatable, Sendable { case show, hide }
    public private(set) var isPresented = false
    public init() {}
    public mutating func show() { isPresented = true }
    public mutating func hide() { isPresented = false }
    public mutating func toggle(applicationActive: Bool, windowVisible: Bool) -> Action {
        let hide = isPresented && applicationActive && windowVisible
        isPresented = !hide
        return hide ? .hide : .show
    }
}
