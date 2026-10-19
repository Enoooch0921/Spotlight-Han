import SwiftUI

struct AppUpdateSettingsView: View {
    @ObservedObject var updater: AppUpdateService
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(L.text("自動檢查新版本"), isOn: $updater.automaticallyChecks)
                .onChange(of: updater.automaticallyChecks) { _, enabled in if enabled { Task { await updater.checkIfNeeded() } } }
            Toggle(L.text("包含測試版更新"), isOn: $updater.includesPreviews)
                .onChange(of: updater.includesPreviews) { _, _ in Task { await updater.check() } }
            HStack {
                Button(L.text("檢查更新…")) { Task { await updater.check() } }.disabled(updater.checking)
                if updater.checking { ProgressView().controlSize(.small) }
                Text(L.text(updater.status)).font(.caption).foregroundStyle(.secondary)
            }
            if let date = updater.checkedAt { Text(L.format("上次檢查：%@", date.formatted(date: .abbreviated, time: .shortened))).font(.caption).foregroundStyle(.secondary) }
            if let update = updater.available {
                Label(L.format("新版本 %@", update.version), systemImage: "arrow.down.circle").font(.callout)
                HStack {
                    Link(L.text("下載 DMG"), destination: update.dmgURL)
                    Link(L.text("查看更新內容"), destination: update.releaseURL)
                }
            }
            Text(L.text("每天最多自動檢查一次 GitHub 公開版本；只讀取版本資訊，不傳送搜尋內容或 App 清單。更新由你下載與安裝。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AppUpdateBanner: View {
    @ObservedObject var updater: AppUpdateService
    var body: some View {
        if updater.showsBanner, let update = updater.available {
            HStack(spacing: 10) {
                Label(L.format("Spotlight Han %@ 可更新", update.version), systemImage: "arrow.down.circle").font(.callout)
                Spacer()
                Link(L.text("下載 DMG"), destination: update.dmgURL)
                Button(L.text("稍後")) { updater.dismissedVersion = update.version }.buttonStyle(.plain)
            }.padding(.horizontal, 18).padding(.vertical, 10).spotlightGlass(Capsule())
        }
    }
}

struct AppUpdateMenu: View {
    @ObservedObject var updater: AppUpdateService
    var body: some View {
        if let update = updater.available {
            Link(String(L.format("下載新版本 %@", update.version).prefix(30)), destination: update.releaseURL)
        }
        Button(L.text(updater.checking ? "正在檢查更新…" : "檢查更新…")) { Task { await updater.check() } }.disabled(updater.checking)
    }
}
