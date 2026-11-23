import AppKit

/// Han is a menu-bar utility. A regular app identity is temporary and only
/// needed while macOS presents consent (so its buttons remain interactive).
@MainActor
final class ApplicationPresence {
    private let application: NSApplication
    init(application: NSApplication) { self.application = application }

    func synchronize(authorizationInFlight: Bool) {
        let desired: NSApplication.ActivationPolicy = authorizationInFlight ? .regular : .accessory
        guard application.activationPolicy() != desired else { return }
        application.setActivationPolicy(desired)
    }
}
