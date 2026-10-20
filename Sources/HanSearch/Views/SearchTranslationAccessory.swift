import SwiftUI
import HanSearchCore

/// Translation is an auxiliary footer, leaving the first result in view.
struct SearchTranslationAccessory: View {
    @ObservedObject var store: SearchStore
    let item: QuickResult
    @State private var expanded = false
    @State private var translationHeight: CGFloat = 20
    private var needsSetup: Bool { if case .prepareTranslation = item.action { return true }; return false }
    private var translationFailed: Bool { item.title == "翻譯暫時無法完成" }
    private var title: String { needsSetup ? L.text(item.title) : item.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).font(.callout)
                        .accessibilityLabel(L.text(expanded ? "收起完整翻譯" : "展開完整翻譯"))
                    Button { activate() } label: { Image(systemName: "doc.on.doc").frame(width: 28, height: 24).contentShape(Rectangle()) }
                        .buttonStyle(.plain).help(L.text("複製翻譯"))
                        .accessibilityLabel(L.text("複製翻譯"))
                }
            }
            if expanded && !needsSetup {
                ScrollView {
                    Text(item.title).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: TranslationHeightKey.self, value: geometry.size.height)
                        })
                }.frame(height: min(100, max(20, translationHeight)))
                    .onPreferenceChange(TranslationHeightKey.self) { translationHeight = $0 }
                Text(L.text("Apple 本機翻譯 · 選取後按 Return 複製"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(store.selection == item.id ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { store.selection = item.id }
        .onChange(of: store.query) { _, _ in expanded = false }
        .onChange(of: store.translationTarget) { _, _ in expanded = false }
    }

    private func activate() {
        store.selection = item.id
        store.openSelection()
    }
}

private struct TranslationHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 20
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
