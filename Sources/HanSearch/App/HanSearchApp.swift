import SwiftUI
import AppKit
import HanSearchCore
import OSLog
import Carbon
import Combine

@main
struct HanSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("Spotlight Han", systemImage: "magnifyingglass") {
            HanMenuView(store: delegate.store, open: { delegate.showSearch() })
        }
        Settings { SettingsView(store: delegate.store).frame(width: 650, height: 650) }
    }
}

private struct HanMenuView: View {
    @ObservedObject var store: SearchStore
    let open: () -> Void
    var body: some View {
        Group {
            Button(L.text("開啟 Spotlight Han"), action: open)
            SettingsLink { Text(L.text("設定與資料來源…")) }
            AppUpdateMenu(updater: store.appUpdater)
            Link(L.text("GitHub 專案與原始碼"), destination: URL(string: "https://github.com/Enoooch0921/Spotlight-Han")!)
            Divider()
            Button(L.text("結束 Spotlight Han")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }.environment(\.locale, store.interfaceLanguage.locale)
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
    private var rejectedBinding: ShortcutBinding?
    private var presentation = LauncherPresentation()
    private var fadeGeneration = 0
    private var layoutTarget: NSRect?
    private var updateObservation: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 804, height: 140), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Spotlight Han"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let hosting = TransparentHostingView(rootView: ContentView(store: store))
        // AppKit owns this panel's finite frame. Intrinsic/min/max probes can loop
        // when a large expandable category preview changes its content height.
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.command = { [weak self] key in self?.command(key) ?? false }
        panel.dismiss = { [weak self] in
            guard let self else { return }
            if self.store.appLibrary.isEditingCategory { self.store.appLibrary.isEditingCategory = false }
            else if self.store.appLibrary.isPreviewingSuggestions { self.store.appLibrary.isPreviewingSuggestions = false }
            else { self.hideSearch() }
        }
        self.panel = panel
        store.onLayoutChanged = { [weak self] in self?.resizePanel() }
        store.hideLauncher = { [weak self] in self?.hideSearch() }
        store.showLauncher = { [weak self] in self?.showSearch() }
        store.settingsVisibilityChanged = { [weak self] visible in
            if visible {
                self?.hideSearch(animated: false)
                // Present system consent from an ordinary foreground app while Settings is open.
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            } else if self?.store.authorizationInFlight != true {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        store.prepareSystemAuthorization = { [weak self] in
            NSApp.setActivationPolicy(.regular)
            self?.hideSearch(animated: false)
            NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.isVisible && $0 !== self?.panel && $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        store.prepareTranslation = { [weak self] source in
            guard let self else { return }
            if #available(macOS 15.0, *) {
                self.hideSearch(animated: false)
                self.translationWindow?.close()
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.title = "Spotlight Han · 本機翻譯語言"; window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: TranslationSetupView(store: self.store, source: source, query: self.store.query.trimmingCharacters(in: .whitespacesAndNewlines), close: { [weak self, weak window] in window?.close(); self?.showSearch() }))
                self.translationWindow = window
                window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            }
        }
        hotkey.action = { [weak self] in self?.toggleSearch() }
        store.changeHotkey = { [weak self] binding in self?.setHotkey(binding) }
        let saved = UserDefaults.standard.data(forKey: "shortcutBinding.v1").flatMap { try? JSONDecoder().decode(ShortcutBinding.self, from: $0) }
        if let saved, HotKey.systemConflict(saved) == nil, hotkey.register(saved) { store.hotkeyNotice = saved.display }
        else if hotkey.register() {
            store.hotkeyNotice = ShortcutBinding.standard.display
            if let saved { rejectedBinding = saved; store.hotkeyError = HotKey.systemConflict(saved) ?? "原快捷鍵無法註冊，已使用預設快捷鍵。" }
        } else { store.hotkeyError = "快捷鍵被占用，請從選單列開啟並重新設定。" }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true, self.hotkey.matches(event) else { return event }
            if !event.isARepeat { self.toggleSearch() }
            return nil
        }
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = launchEvent?.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem))?.booleanValue == true ||
            launchEvent?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !loginLaunch { showSearch() }
        updateObservation = store.appUpdater.$available.combineLatest(store.appUpdater.$dismissedVersion).sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizePanel() }
        }
        store.appUpdater.start()
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        store.checkClockSetupOnReturn(); store.loginItem.refresh()
        if let rejectedBinding { setHotkey(rejectedBinding) }
        else if let binding = hotkey.binding { store.hotkeyError = HotKey.systemConflict(binding) ?? "" }
    }
    func applicationDidResignActive(_ notification: Notification) { hideSearch(animated: false) }
    private func command(_ key: String) -> Bool {
        if store.composerMode != nil, key != "f" { return false }
        switch key {
        case "1": store.appLibrary.isEditingCategory = false; store.appLibrary.isPreviewingSuggestions = false; store.appLibrary.select(.all); store.mode = .apps
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
        let baseHeight: CGFloat = store.composerMode != nil ? 610 : (store.details != nil ? detailHeight : (!store.hasBody ? 140 : store.isAppBrowser ? 650 : count == 0 ? 410 : 580))
        let desired = baseHeight + (store.appUpdater.showsBanner ? 48 : 0)
        let screen = presentation.isPresented ? (panel.screen ?? NSScreen.main) : (NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main)
        let visible = screen?.visibleFrame
        let preferredTop = visible.map { $0.maxY - $0.height * 0.26 } ?? panel.frame.maxY
        let top = presentation.isPresented ? panel.frame.maxY : preferredTop
        let available = visible.map { max(140, top - $0.minY - 16) } ?? desired
        let height = min(desired, available)
        let frame = NSRect(x: panel.frame.minX, y: top - height, width: 804, height: height)
        guard layoutTarget != frame else { return }
        layoutTarget = frame
        if presentation.isPresented, panel.isVisible, store.motionEnabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            LauncherMotion.perform(duration: LauncherMotion.resizeDuration) { panel.animator().setFrame(frame, display: true) }
        } else { panel.setFrame(frame, display: true) }
    }
    private func setHotkey(_ binding: ShortcutBinding) {
        if let conflict = HotKey.systemConflict(binding) { rejectedBinding = binding; store.hotkeyError = conflict; return }
        guard hotkey.register(binding) else {
            rejectedBinding = binding
            store.hotkeyError = "無法使用 \(binding.display)，可能已被系統或其他 App 占用。原快捷鍵仍可使用；⌘Space 請先關閉 Spotlight 的同名快捷鍵。"
            return
        }
        rejectedBinding = nil
        store.hotkeyNotice = binding.display; store.hotkeyError = ""
        if let data = try? JSONEncoder().encode(binding) { UserDefaults.standard.set(data, forKey: "shortcutBinding.v1") }
    }
    func toggleSearch() {
        guard !store.authorizationInFlight, NSApp.modalWindow == nil, translationWindow?.attachedSheet == nil else { return }
        // Carbon and a local monitor can observe the same physical press. Ignore only that tiny duplicate window.
        guard Date().timeIntervalSince(lastToggle) > 0.04 else { return }
        lastToggle = Date()
        let active = NSApp.isActive && !NSApp.isHidden
        let visible = panel?.isVisible == true
        let action = presentation.toggle(applicationActive: active, windowVisible: visible)
        Logger(subsystem: "local.hansearch.mac", category: "hotkey").info("Toggle launcher; active=\(active, privacy: .public), visible=\(visible, privacy: .public)")
        if action == .hide { hideSearch() } else { showSearch() }
    }
    private func hideSearch(animated: Bool = true) {
        presentation.hide(); fadeGeneration += 1
        guard let panel else { return }
        let generation = fadeGeneration
        guard panel.isVisible, animated, store.motionEnabled else {
            panel.orderOut(nil); panel.alphaValue = 1; return
        }
        LauncherMotion.perform(duration: LauncherMotion.hideDuration, changes: { panel.animator().alphaValue = 0 }) { [weak self, weak panel] in
            guard let self, self.fadeGeneration == generation, !self.presentation.isPresented else { return }
            panel?.orderOut(nil); panel?.alphaValue = 1
        }
    }
    func showSearch() {
        guard !store.authorizationInFlight, let panel, NSApp.modalWindow == nil else { return }
        fadeGeneration += 1
        let wasVisible = panel.isVisible && NSApp.isActive && !NSApp.isHidden
        // Resize offscreen on entry; later structural expansions retarget the native window animation.
        if !wasVisible { presentation.hide(); layoutTarget = nil }
        resizePanel()
        if !wasVisible {
            let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.maxY - visible.height * 0.26 - panel.frame.height))
            }
            layoutTarget = panel.frame
        }
        let fade = store.motionEnabled
        if !panel.isVisible { panel.alphaValue = fade ? 0 : 1 }
        presentation.show()
        NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        store.focusToken = UUID()
        if fade {
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? LauncherMotion.hideDuration : LauncherMotion.showDuration
            LauncherMotion.perform(duration: duration) { panel.animator().alphaValue = 1 }
        } else { panel.alphaValue = 1 }
        store.refreshIfNeeded()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = translationWindow, window.isVisible { window.makeKeyAndOrderFront(nil) }
        else if NSApp.modalWindow == nil { showSearch() }
        return true
    }
}

private final class LauncherPanel: NSPanel {
    var command: ((String) -> Bool)?
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers, command?(key) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { if let dismiss { dismiss() } else { orderOut(nil) } }
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
