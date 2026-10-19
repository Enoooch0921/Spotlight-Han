import SwiftUI
import AppKit
import HanSearchCore
import OSLog

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
    private var translationWindow: NSWindow?
    private var keyMonitor: Any?
    private var lastToggle = Date.distantPast
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 804, height: 140), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Spotlight Han"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.contentView = TransparentHostingView(rootView: ContentView(store: store))
        panel.command = { [weak self] key in self?.command(key) ?? false }
        self.panel = panel
        store.onLayoutChanged = { [weak self] in self?.resizePanel() }
        store.hideLauncher = { [weak panel] in panel?.orderOut(nil) }
        store.prepareTranslation = { [weak self] source in
            guard let self else { return }
            if #available(macOS 15.0, *) {
                self.panel?.orderOut(nil)
                self.translationWindow?.close()
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 210), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.title = "Spotlight Han · 本機翻譯語言"; window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: TranslationSetupView(store: self.store, source: source, query: self.store.query.trimmingCharacters(in: .whitespacesAndNewlines), close: { [weak self, weak window] in window?.close(); self?.showSearch() }))
                self.translationWindow = window
                window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            }
        }
        hotkey.action = { [weak self] in self?.toggleSearch() }
        store.changeHotkey = { [weak self] binding in self?.setHotkey(binding) }
        let saved = UserDefaults.standard.data(forKey: "shortcutBinding.v1").flatMap { try? JSONDecoder().decode(ShortcutBinding.self, from: $0) }
        if let saved, hotkey.register(saved) { store.hotkeyNotice = saved.display }
        else if hotkey.register() {
            store.hotkeyNotice = ShortcutBinding.standard.display
            if saved != nil { store.hotkeyError = "原快捷鍵無法註冊，已使用預設快捷鍵。" }
        } else { store.hotkeyError = "快捷鍵被占用，請從選單列開啟並重新設定。" }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true, self.hotkey.matches(event) else { return event }
            if !event.isARepeat { self.toggleSearch() }
            return nil
        }
        showSearch()
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
    func applicationDidBecomeActive(_ notification: Notification) { store.checkClockSetupOnReturn() }
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
        let count = store.results.count + store.allQuickResults.count
        let detailHeight = min(600, CGFloat(320 + ((store.details?.count ?? 0) / 50) * 22))
        let height: CGFloat = store.details != nil ? detailHeight : (!store.hasBody ? 140 : (count == 0 ? 410 : min(650, CGFloat(282 + count * 64))))
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - height, width: 804, height: height), display: true)
    }
    private func setHotkey(_ binding: ShortcutBinding) {
        guard hotkey.register(binding) else {
            store.hotkeyError = "無法使用 \(binding.display)，可能已被系統或其他 App 占用。原快捷鍵仍可使用；⌘Space 請先關閉 Spotlight 的同名快捷鍵。"
            return
        }
        store.hotkeyNotice = binding.display; store.hotkeyError = ""
        if let data = try? JSONEncoder().encode(binding) { UserDefaults.standard.set(data, forKey: "shortcutBinding.v1") }
    }
    func toggleSearch() {
        guard NSApp.modalWindow == nil, translationWindow?.attachedSheet == nil else { return }
        guard Date().timeIntervalSince(lastToggle) > 0.2 else { return }
        lastToggle = Date()
        let visible = panel?.isVisible == true
        Logger(subsystem: "local.hansearch.mac", category: "hotkey").info("Toggle launcher; visible=\(visible, privacy: .public)")
        if visible { panel?.orderOut(nil) }
        else { showSearch() }
        Logger(subsystem: "local.hansearch.mac", category: "hotkey").info("Toggle complete; visible=\(self.panel?.isVisible == true, privacy: .public)")
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
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = translationWindow, window.isVisible { window.makeKeyAndOrderFront(nil) }
        else if NSApp.modalWindow == nil { showSearch() }
        return true
    }
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

/// Keep the hosting surface clear; only the individual native glass shapes draw chrome.
private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
