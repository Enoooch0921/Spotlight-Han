import AppKit
import HanSearchCore

extension SearchStore {
    func editAliases(identity: String, title: String) {
        guard !authorizationInFlight, !actionInFlight, NSApp.modalWindow == nil else { return }
        actionInFlight = true
        defer { actionInFlight = false; showLauncher?(); startNextSource() }
        // Keep a floating launcher from covering this normal modal dialog.
        hideLauncher?()
        let alert = NSAlert()
        alert.messageText = L.text("自訂搜尋縮寫")
        alert.informativeText = title + "\n" + L.text("多個縮寫以逗號分隔，每個最多32字、最多8個。留空可移除。只保存在本機；縮寫只會找出已連接、已載入的結果。")
        let field = NSTextField(string: aliases.aliases(for: identity).joined(separator: ", "))
        field.frame = NSRect(x: 0, y: 0, width: 340, height: 26)
        alert.accessoryView = field
        alert.addButton(withTitle: L.text("儲存")); alert.addButton(withTitle: L.text("取消"))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let parsed = SearchAliasStore.parse(field.stringValue), aliases.set(parsed, for: identity) else {
            notice = "縮寫未儲存：每項最多32字、最多8項，總共最多2,000個項目。"; return
        }
        notice = "搜尋縮寫已儲存"; refreshSearchResults()
    }
}
