import SwiftUI

/// Dismiss the floating launcher before reopening an already-retained Settings window.
struct SettingsEntryButton<Label: View>: View {
    let store: SearchStore
    @ViewBuilder let label: () -> Label
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button {
            store.settingsVisibilityChanged?(true)
            openSettings()
        } label: { label() }
    }
}
