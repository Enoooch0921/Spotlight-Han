import SwiftUI
import HanSearchCore

/// Translation is an auxiliary footer, leaving the first result in view.
struct SearchTranslationAccessory: View {
    @ObservedObject var store: SearchStore
    let item: QuickResult
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var needsSetup: Bool { if case .prepareTranslation = item.action { return true }; return false }
    private var translationFailed: Bool { item.title == "翻譯暫時無法完成" }
    private var title: String { needsSetup ? L.text(item.title) : item.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "translate").foregroundStyle(.secondary)
                Text(L.text("翻譯")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if needsSetup {
                    Text(title + " · " + item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(item.subtitle)
                    Spacer(minLength: 4)
                    Button(L.text(translationFailed ? "檢查翻譯…" : "檢查語言…")) { activate() }.controlSize(.small)
                } else {
                    Button {
                        expanded.toggle()
                        store.onLayoutChanged?()
                    } label: {
                        HStack(spacing: 5) {
                            Text(item.title).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                                .animation(reduceMotion ? nil : LauncherMotion.structure(enabled: store.motionEnabled), value: expanded)
                        }.contentShape(Rectangle())
                    }.buttonStyle(LauncherButtonStyle()).font(.callout)
                        .accessibilityLabel(L.text(expanded ? "收起完整翻譯" : "展開完整翻譯"))
                    Button { activate() } label: { Image(systemName: "doc.on.doc").frame(width: 28, height: 24).contentShape(Rectangle()) }
                        .buttonStyle(LauncherButtonStyle()).help(L.text("複製翻譯"))
                        .accessibilityLabel(L.text("複製翻譯"))
                }
            }
            if !needsSetup { TranslationExpansion(text: item.title, expanded: expanded) }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(store.selection == item.id ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { store.selection = item.id }
        .onChange(of: store.query) { _, _ in collapseImmediately() }
        .onChange(of: store.translationTarget) { _, _ in collapseImmediately() }
        .onChange(of: needsSetup) { _, _ in collapseImmediately() }
    }

    private func activate() {
        store.selection = item.id
        store.openSelection()
    }
    private func collapseImmediately() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { expanded = false }
    }
}
