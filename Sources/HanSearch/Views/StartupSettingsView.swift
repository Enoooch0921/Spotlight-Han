import SwiftUI

struct StartupSettingsView: View {
    @ObservedObject var service: LoginItemService
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(L.text("登入 Mac 時自動啟動"), isOn: Binding(get: { service.requested }, set: { service.setEnabled($0) }))
            Text(L.text(service.statusText)).font(.caption).foregroundStyle(.secondary)
            if !service.error.isEmpty { Text(L.text(service.error)).font(.caption).foregroundStyle(.orange) }
            if service.status == .requiresApproval || !service.error.isEmpty {
                Button(L.text("開啟系統登入項目")) { service.openSystemSettings() }
            }
        }.onAppear { service.refresh() }
    }
}
