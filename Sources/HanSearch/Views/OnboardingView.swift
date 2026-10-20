import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var store: SearchStore
    let finish: () -> Void
    @State private var step: OnboardingStep? = .welcome
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    private var current: OnboardingStep { step ?? .welcome }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Spotlight Han").font(.headline)
                        Text(L.text("開始之前")).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                List(OnboardingStep.allCases, selection: $step) { item in
                    Label(L.text(item.title), systemImage: item.symbol).tag(item)
                        .padding(.vertical, 5)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Button(L.text("稍後設定"), action: finish).buttonStyle(.plain)
                    Text(L.text("每一步都可以略過。")).font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }.frame(width: 210).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L.text("歡迎使用 Spotlight Han")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%02d / %02d", current.rawValue + 1, OnboardingStep.allCases.count))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(.bottom, 14)
                Text(L.text(current.heading)).font(.system(size: 29, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
                Text(L.text(current.subtitle)).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 24)
                ScrollView {
                    page.id(current).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider().padding(.top, 12).padding(.bottom, 18)
                HStack(spacing: 12) {
                    Button { openWindow(id: "usage-guide") } label: { Label(L.text("使用說明"), systemImage: "questionmark.circle") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer()
                    if current != .welcome { Button(L.text("上一步")) { step = OnboardingStep(rawValue: current.rawValue - 1) } }
                    Button(L.text(current == .ready ? "開始搜尋" : "繼續")) {
                        if current == .ready { finish() }
                        else { step = OnboardingStep(rawValue: current.rawValue + 1) }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }.controlSize(.large)
            }.padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 24)
        }
        .environment(\.locale, store.interfaceLanguage.locale)
        .animation(LauncherMotion.animation(enabled: store.motionEnabled), value: current)
    }
    @ViewBuilder private var page: some View {
        switch current {
        case .welcome: OnboardingWelcomePage()
        case .shortcuts: OnboardingShortcutPage(store: store, settings: settings)
        case .files: OnboardingFilesPage(store: store, settings: settings)
        case .sources: OnboardingSourcesPage(store: store, settings: settings)
        case .tools: OnboardingToolsPage(settings: settings)
        case .ready: OnboardingReadyPage(store: store, settings: settings)
        }
    }
    private func settings(_ page: SettingsPage) { store.settingsPage = page; openSettings() }
}
