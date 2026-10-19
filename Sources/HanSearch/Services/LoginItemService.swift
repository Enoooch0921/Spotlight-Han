import AppKit
import ServiceManagement

@MainActor
final class LoginItemService: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error = ""
    var requested: Bool { status == .enabled || status == .requiresApproval }
    var statusText: String {
        switch status {
        case .enabled: return "已啟用：登入這台 Mac 後自動開啟 Han。"
        case .requiresApproval: return "已送出設定，請到系統「登入項目」允許啟動。"
        case .notRegistered: return "目前不會在登入時自動開啟。"
        case .notFound: return "系統找不到 App，請確認 App 仍在原本位置。"
        @unknown default: return "系統目前無法確認登入項目狀態。"
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) {
        error = ""; refresh()
        do {
            if enabled && !requested { try SMAppService.mainApp.register() }
            if !enabled && requested { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh(); self.error = "設定未完成：\(error.localizedDescription)"
        }
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
