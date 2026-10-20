import SwiftUI

struct OnboardingNote: View {
    let text: String
    var symbol = "info.circle"
    var body: some View {
        Label { Text(L.text(text)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol) }
            .font(.callout).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
    }
}

struct OnboardingFeatureLine: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(L.text(title)).font(.headline)
                Text(L.text(detail)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OnboardingKey: View {
    let text: String
    var body: some View {
        Text(text).font(.system(.body, design: .monospaced).weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.08)))
    }
}
