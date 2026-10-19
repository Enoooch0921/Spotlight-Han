import SwiftUI
import AppKit
import HanSearchCore

@main
struct HanSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("Spotlight Han", systemImage: "magnifyingglass") {
            Button("開啟 Spotlight Han") { delegate.showSearch() }
            SettingsLink { Text("設定與資料來源…") }
            Divider()
            Button("結束 Spotlight Han") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        Settings { SettingsView(store: delegate.store).frame(width: 650, height: 650) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SearchStore()
    private let hotkey = HotKey()
    private var panel: LauncherPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 76), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Spotlight Han"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ContentView(store: store))
        panel.command = { [weak self] key in self?.command(key) ?? false }
        self.panel = panel
        store.onLayoutChanged = { [weak self] in self?.resizePanel() }
        store.hideLauncher = { [weak panel] in panel?.orderOut(nil) }
        hotkey.action = { [weak self] in self?.showSearch() }
        if !hotkey.register() { store.hotkeyNotice = "快捷鍵被占用 · 請從選單列開啟" }
        showSearch()
    }
    private func command(_ key: String) -> Bool {
        switch key {
        case "1": store.mode = .apps
        case "2": store.mode = .names
        case "3": store.mode = .shortcuts
        case "4": store.mode = .clipboard
        case "f": store.focusToken = UUID()
        case "r": store.revealSelection()
        default: return false
        }
        store.search(); return true
    }
    func resizePanel() {
        guard let panel else { return }
        let count = store.results.count + store.quickResults.count
        let height: CGFloat = !store.hasBody ? 76 : (count == 0 ? 330 : min(570, CGFloat(190 + count * 58)))
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - height, width: 740, height: height), display: true)
    }
    func showSearch() {
        guard let panel else { return }
        resizePanel()
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.maxY - visible.height * 0.26 - panel.frame.height))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.focusToken = UUID(); store.refreshIfNeeded()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSearch(); return true }
}

private final class LauncherPanel: NSPanel {
    var command: ((String) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers, command?(key) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
