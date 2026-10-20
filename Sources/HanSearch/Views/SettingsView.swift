import SwiftUI


struct SettingsView: View {
    @ObservedObject var store: SearchStore
    @State private var page: SettingsPage? = .general
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { item in
                Label(L.text(item.title), systemImage: item.symbol).tag(item)
            }.listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 175, ideal: 190, max: 220)
                .safeAreaInset(edge: .bottom) {
                    Button { openWindow(id: "usage-guide") } label: {
                        Label(L.text("使用說明…"), systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).padding(16)
                }
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(L.text((page ?? .general).title)).font(.title2.weight(.semibold))
                    Spacer()
                    Button { openWindow(id: "usage-guide") } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain).help(L.text("使用說明" )).accessibilityLabel(L.text("使用說明"))
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
                Group {
                    switch page ?? .general {
                    case .general: GeneralSettingsView(store: store)
                    case .search: SearchPreferencesView(store: store)
                    case .files: FileSearchSettingsView(store: store)
                    case .sources: SourceSettingsView(store: store)
                    case .tools: UtilitySettingsView(store: store)
                    case .about: AboutSettingsView(store: store)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.locale, store.interfaceLanguage.locale)
        .id(store.interfaceLanguage.rawValue)
        .onChange(of: page) { _, value in store.settingsPage = value ?? .general }
        .onChange(of: store.settingsPage) { _, value in page = value }
        .onAppear { page = store.settingsPage }
        .background(AuxiliaryWindowLifecycle { visible in
            store.settingsPresented = visible
            store.settingsVisibilityChanged?(visible || store.helpPresented || store.onboardingPresented)
            if visible { store.reconcileSourcePermissions() }
        })
    }
}
