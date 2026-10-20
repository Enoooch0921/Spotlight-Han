import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let store: SearchStore
    private var completed: (() -> Void)?
    init(store: SearchStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L.text("歡迎使用 Spotlight Han")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(completed: @escaping () -> Void) {
        self.completed = completed
        window?.contentView = NSHostingView(rootView: OnboardingView(store: store, finish: { [weak self] in self?.finish() }))
        store.onboardingPresented = true; store.settingsVisibilityChanged?(true)
        showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func finish() {
        window?.close()
    }
    func windowWillClose(_ notification: Notification) {
        store.onboarding.finish()
        store.onboardingPresented = false
        store.settingsVisibilityChanged?(store.settingsPresented || store.helpPresented)
        let callback = completed; completed = nil
        DispatchQueue.main.async { callback?() }
    }
}
