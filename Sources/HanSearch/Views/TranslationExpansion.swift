import SwiftUI

/// Measure while collapsed so opening does not first jump to a one-line height.
/// Only this disclosure changes height; search rows retain their reading anchor.
struct TranslationExpansion: View {
    let text: String
    let expanded: Bool
    @Environment(\.launcherMotionEnabled) private var motionEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textHeight: CGFloat = 20
    @State private var contentHeight: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(text).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { ceil($0.size.height) }) { textHeight = $0 }
            }.frame(height: min(100, max(20, textHeight)))
            Text(L.text("Apple 本機翻譯 · 選取後按 Return 複製"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { ceil($0.size.height) }) { contentHeight = $0 }
        .frame(height: expanded ? contentHeight : 0, alignment: .top)
        .clipped()
        .animation(reduceMotion ? nil : LauncherMotion.structure(enabled: motionEnabled), value: expanded)
        .opacity(expanded ? 1 : 0)
        .animation(LauncherMotion.feedback(enabled: motionEnabled, pressed: reduceMotion), value: expanded)
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
    }
}
