import AppKit
import QuickLookUI
import HanSearchCore

struct FilePreviewRequest: Equatable, Sendable {
    let url: URL
    let name: String
    let query: String
    let pages: [Int]
    let isOCR: Bool
    init(item: SearchItem, query: String) {
        url = item.url; name = item.name; self.query = item.supplement?.query ?? query
        pages = item.matchPages; isOCR = item.isOCR
    }
}

private final class QuickPreviewWindow: NSPanel {
    var dismiss: (() -> Void)?
    var navigate: ((Int) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { super.sendEvent(event); return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty {
            if event.keyCode == 49 { if !event.isARepeat { dismiss?() }; return }
            if event.keyCode == 53 { dismiss?(); return }
            if event.keyCode == 125 { navigate?(1); return }
            if event.keyCode == 126 { navigate?(-1); return }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class FileQuickPreviewController: NSWindowController, NSWindowDelegate {
    var didClose: (() -> Void)?
    var navigate: ((Int) -> Void)?
    var shouldDeferOCR: @Sendable () -> Bool = { false }
    private(set) var request: FilePreviewRequest?
    var isPresented: Bool { window?.isVisible == true }
    private let pdf = PDFQuickPreviewSession()
    private var quickLook: QLPreviewView?
    private let body = NSView()
    private let status = NSTextField(labelWithString: "")
    private let pageStatus = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let previous = NSButton(), next = NSButton()
    private var loadTask: Task<Void, Never>?
    private var cancellation = ProcessCancellation()
    private var generation = UUID()
    private var restoreFocus = true

    init() {
        let panel = QuickPreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 680),
                                       styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = L.text("快速預覽"); panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.minSize = NSSize(width: 520, height: 380)
        panel.delegate = self
        panel.dismiss = { [weak self] in self?.dismiss() }
        panel.navigate = { [weak self] in self?.navigate?($0) }
        buildInterface(panel)
        pdf.changed = { [weak self] message, busy, page, total, hits in
            guard let self, self.request?.url.pathExtension.lowercased() == "pdf" else { return }
            self.setStatus(L.text(message), busy: busy)
            self.pageStatus.stringValue = total > 0 ? L.format("第 %@／%@ 頁", String(page), String(total)) : ""
            self.previous.isHidden = hits.isEmpty; self.next.isHidden = hits.isEmpty
            self.previous.isEnabled = hits.count > 1; self.next.isEnabled = hits.count > 1
        }
        pdf.failed = { [weak self] message in self?.showMessage(message) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(_ request: FilePreviewRequest, relativeTo parent: NSWindow?) {
        clearPreview(); self.request = request
        window?.title = request.name + " — " + L.text("快速預覽")
        if !isPresented, let screen = parent?.screen ?? NSScreen.main {
            let area = screen.visibleFrame
            let size = NSSize(width: min(800, area.width - 60), height: min(720, area.height - 60))
            window?.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: false)
        }
        setStatus(L.text("正在載入預覽…"), busy: true)
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        if request.url.pathExtension.lowercased() == "pdf" {
            install(pdf.view); pdf.shouldDeferOCR = shouldDeferOCR; pdf.open(request)
        } else {
            let token = generation, cancellation = cancellation
            loadTask = Task { [weak self] in
                do {
                    try await PreviewReadQueue.run(cancellation: cancellation) { try PDFPreviewSearch.validate(request.url) }
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.loadTask = nil
                    guard let preview = QLPreviewView(frame: .zero, style: .normal) else { throw FilePreviewError.unavailable }
                    // Never auto-play audio/video when merely browsing search results.
                    preview.autostarts = false; preview.shouldCloseWithWindow = false
                    self.quickLook = preview; self.install(preview)
                    preview.previewItem = request.url as NSURL
                    self.setStatus(L.text("系統快速預覽 · 空白鍵或 Esc 返回搜尋"), busy: false)
                } catch {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.loadTask = nil; self.showMessage(L.text(error.localizedDescription))
                }
            }
        }
    }
    func dismiss(restoreFocus: Bool = true) {
        self.restoreFocus = restoreFocus
        if isPresented { window?.close() } else { clearPreview() }
        self.restoreFocus = true
    }
    func windowWillClose(_ notification: Notification) {
        clearPreview()
        if restoreFocus { didClose?() }
    }
    private func clearPreview() {
        generation = UUID(); loadTask?.cancel(); loadTask = nil; cancellation.cancel(); cancellation = ProcessCancellation()
        request = nil; pdf.close(); quickLook?.previewItem = nil; quickLook?.close(); quickLook = nil
        body.subviews.forEach { $0.removeFromSuperview() }
        pageStatus.stringValue = ""; previous.isHidden = true; next.isHidden = true
    }
    private func buildInterface(_ panel: NSPanel) {
        let root = NSView(); panel.contentView = root
        let toolbar = NSStackView(); toolbar.orientation = .horizontal; toolbar.spacing = 8
        previous.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: L.text("上一個命中頁"))
        next.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: L.text("下一個命中頁"))
        for button in [previous, next] { button.bezelStyle = .texturedRounded; button.target = self; button.isHidden = true }
        previous.action = #selector(previousHit); next.action = #selector(nextHit)
        previous.toolTip = L.text("上一個命中頁"); next.toolTip = L.text("下一個命中頁")
        pageStatus.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); pageStatus.textColor = .secondaryLabelColor
        let open = NSButton(title: L.text("在原本的 App 開啟"), target: self, action: #selector(openOriginal)); open.bezelStyle = .rounded
        let flexible = NSView(); flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for item in [previous, next, pageStatus, flexible, open] { toolbar.addArrangedSubview(item) }
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let footer = NSStackView(views: [spinner, status]); footer.orientation = .horizontal; footer.spacing = 8
        let separator = NSBox(); separator.boxType = .separator
        for item in [toolbar, separator, body, footer] { item.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(item) }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14), toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14), toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), toolbar.heightAnchor.constraint(equalToConstant: 28),
            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10), separator.leadingAnchor.constraint(equalTo: root.leadingAnchor), separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.topAnchor.constraint(equalTo: separator.bottomAnchor), body.leadingAnchor.constraint(equalTo: root.leadingAnchor), body.trailingAnchor.constraint(equalTo: root.trailingAnchor), body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14), footer.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14), footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10), footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
            spinner.widthAnchor.constraint(equalToConstant: 16), spinner.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    private func install(_ view: NSView) {
        body.subviews.forEach { $0.removeFromSuperview() }; view.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: body.leadingAnchor), view.trailingAnchor.constraint(equalTo: body.trailingAnchor), view.topAnchor.constraint(equalTo: body.topAnchor), view.bottomAnchor.constraint(equalTo: body.bottomAnchor)])
    }
    private func setStatus(_ text: String, busy: Bool) {
        status.stringValue = text; status.toolTip = text
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
    private func showMessage(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message); label.alignment = .center; label.textColor = .secondaryLabelColor
        let container = NSView(); label.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: container.centerXAnchor), label.centerYAnchor.constraint(equalTo: container.centerYAnchor), label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.8)])
        install(container); setStatus(L.text("空白鍵或 Esc 返回搜尋"), busy: false)
    }
    @objc private func previousHit() { pdf.moveHit(-1) }
    @objc private func nextHit() { pdf.moveHit(1) }
    @objc private func openOriginal() { if let request { NSWorkspace.shared.open(request.url) } }
}
