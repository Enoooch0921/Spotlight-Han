import SwiftUI
import AppKit

/// A retained SwiftUI Settings scene may reopen without a new onAppear.
/// Observe its actual AppKit window so foreground/consent policy follows visibility.
struct AuxiliaryWindowLifecycle: NSViewRepresentable {
    let changed: (Bool) -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView(changed: changed) }
    func updateNSView(_ view: ObserverView, context: Context) { view.changed = changed }
    final class ObserverView: NSView {
        var changed: (Bool) -> Void
        private var tokens: [NSObjectProtocol] = []
        private var lastVisible: Bool?
        init(changed: @escaping (Bool) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens = []
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification, NSWindow.willCloseNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    let closing = notification.name == NSWindow.willCloseNotification
                    let becameKey = notification.name == NSWindow.didBecomeKeyNotification
                    Task { @MainActor [weak self] in self?.report(closing: closing, force: becameKey) }
                })
            }
        }
        private func report(closing: Bool, force: Bool) {
            let visible = !closing && window?.isVisible == true
            guard force || lastVisible != visible else { return }
            lastVisible = visible; changed(visible)
        }
        deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
    }
}
