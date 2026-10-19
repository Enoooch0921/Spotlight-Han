import SwiftUI
import HanSearchCore

struct SourceHealthView: View {
    let health: SourceHealth?
    var now = Date()
    private var label: String {
        guard let health else { return "未連接" }
        switch health.phase {
        case .queued: return health.partialUpdate == nil ? "等待讀取" : "等待續讀（已有部分資料）"
        case .authorizing: return "等待授權"
        case .loading: return health.partialUpdate == nil ? "正在讀取" : "正在讀取（已有部分資料）"
        case .ready: return health.isStale(at: now) ? (health.invalidated ? "資料有變動，待更新" : "資料已舊（超過15分鐘）") : "已更新"
        case .failed: return health.hasSnapshot ? "讀取失敗（仍顯示舊／部分資料）" : "讀取失敗（沒有可用資料）"
        case .incomplete: return "讀取不完整（部分資料）"
        case .stopped: return health.hasSnapshot ? "已停止（仍顯示舊／部分資料）" : "已停止（沒有可用資料）"
        case .needsPermission:
            if health.hasSnapshot { return "需要授權（仍顯示舊資料）" }
            switch health.permissionStatus {
            case .denied: return "存取已被拒絕"
            case .restricted: return "系統限制存取"
            case .writeOnly: return "搜尋需要完整存取"
            default: return "尚未完成授權"
            }
        }
    }
    private var color: Color {
        guard let health else { return .secondary }
        switch health.phase {
        case .failed: return .red
        case .needsPermission, .stopped, .incomplete: return .orange
        case .ready: return health.isStale(at: now) ? .orange : .green
        default: return .blue
        }
    }
    private var symbol: String {
        guard let health else { return "minus.circle" }
        switch health.phase {
        case .failed: return "xmark.octagon.fill"
        case .ready: return health.isStale(at: now) ? "clock.badge.exclamationmark" : "checkmark.circle.fill"
        case .needsPermission: return "lock.fill"
        case .stopped: return "stop.circle.fill"
        case .incomplete: return "exclamationmark.triangle.fill"
        default: return "arrow.triangle.2.circlepath"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(L.text(label), systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(color)
            if let updated = health?.lastSuccess {
                Text(L.format("上次完整更新：%@", updated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L.language.locale)))).font(.caption2).foregroundStyle(.secondary)
            } else if let partial = health?.partialUpdate {
                Text(L.format("部分資料讀取於：%@", partial.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L.language.locale)))).font(.caption2).foregroundStyle(.secondary)
            } else if health != nil { Text(L.text("尚無完整更新記錄")).font(.caption2).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

struct SearchSourceHealthBanner: View {
    @ObservedObject var store: SearchStore
    private let sourceOrder: [SearchMode] = [.names,.contents,.notes,.contacts,.calendar,.reminders,.mail,.shortcuts,.alarms]
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let attention = sourceOrder.filter { store.sourceHealth[$0]?.needsAttention(at: context.date) == true }
            let visible = store.mode == .all ? Array(attention.prefix(2)) : (store.sourceHealth[store.mode] == nil ? [] : [store.mode])
            if !visible.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(visible, id: \.self) { source in
                        HStack(alignment: .top, spacing: 12) {
                            Text(L.text(source.rawValue)).font(.caption.weight(.medium)).frame(width: 58, alignment: .leading)
                            SourceHealthView(health: store.sourceHealth[source], now: context.date)
                            Spacer(minLength: 2)
                            if store.shouldOfferSourcePrivacy(source) {
                                Button(L.text("開啟隱私權設定")) { store.openSourcePrivacy(source) }.controlSize(.small)
                            }
                            Button(L.text(store.sourceHealth[source]?.phase == .needsPermission ? "連接" : "重新讀取")) { store.refreshSource(source) }.controlSize(.small)
                                .disabled(store.connecting.contains(source) || store.authorizationInFlight || store.actionInFlight || (source == .names && store.catalogRefreshing) || (source == .contents && store.indexing))
                        }
                    }
                    if store.mode == .all && attention.count > 2 {
                        SettingsLink { Text(L.format("另有 %@ 個來源需要注意，查看設定", String(attention.count - 2))) }.font(.caption)
                    }
                }.padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.orange.opacity(attention.isEmpty ? 0 : 0.07))
            }
        }
    }
}
