import AppKit
import HanSearchCore

extension SearchStore {
    var actionFile: SearchItem? {
        guard diagnosticURL == nil else { return nil }
        return selectedPreviewItem
    }

    func setLowered(_ lower: Bool, fileID: String) {
        habits.setLowered(lower, query: query, fileID: fileID)
        rankingUndo = lower ? fileID : nil
    }

    func inspectFile(_ url: URL) {
        guard url.isFileURL, composerMode == nil else { return }
        dismissFilePreview?()
        diagnosticURL = url.standardizedFileURL
        onLayoutChanged?()
    }

    func chooseDiagnosticFile() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.prompt = L.text("檢查這個檔案")
        if picker.runModal() == .OK, let url = picker.url { inspectFile(url) }
    }
}

@MainActor final class FileResultActions: NSObject {
    private var handlers: [() -> Void] = []
    private let menu = NSMenu()

    static func show(for store: SearchStore, in window: NSWindow) {
        guard let item = store.actionFile, let view = window.contentView else { return }
        let actions = FileResultActions()
        actions.add("快速預覽") { store.previewFile(item) }
        actions.add("在 Finder 顯示") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        actions.add("複製路徑") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.path, forType: .string)
        }
        actions.add("檢查這個檔案") { store.inspectFile(item.url) }
        let lowered = store.habits.history.loweredFiles(query: store.query, ids: [item.id]).contains(item.id)
        actions.add(lowered ? "恢復這筆的搜尋順位" : "只在這個搜尋詞降低順位") { store.setLowered(!lowered, fileID: item.id) }
        _ = withExtendedLifetime(actions) {
            actions.menu.popUp(positioning: actions.menu.items.first, at: NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
        }
    }
    private func add(_ title: String, run: @escaping () -> Void) {
        let item = menu.addItem(withTitle: L.text(title), action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self; item.tag = handlers.count
        handlers.append(run)
    }
    @objc private func invoke(_ item: NSMenuItem) { handlers[item.tag]() }
}
