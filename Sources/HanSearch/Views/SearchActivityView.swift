import SwiftUI

struct SearchActivityView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(L.text("正在搜尋…")).font(.caption.weight(.medium))
                Spacer(minLength: 4)
                if store.verifyingDocumentContents {
                    Text(L.format("核對內文 %@／%@ 份", String(store.documentVerificationCompleted), String(store.documentVerificationTotal)))
                        .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L.text(store.searchPhase)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if store.verifyingDocumentContents {
                ProgressView(value: Double(store.documentVerificationCompleted), total: Double(max(1, store.documentVerificationTotal)))
                    .progressViewStyle(.linear)
                    .animation(LauncherMotion.animation(enabled: store.motionEnabled), value: store.documentVerificationCompleted)
                    .accessibilityLabel(L.text("核對文件內文"))
                    .accessibilityValue("\(store.documentVerificationCompleted) / \(store.documentVerificationTotal)")
            } else {
                ProgressView().progressViewStyle(.linear).accessibilityLabel(L.text("查詢系統文件索引"))
            }
        }.padding(.horizontal, 18).padding(.vertical, 10)
    }
}
