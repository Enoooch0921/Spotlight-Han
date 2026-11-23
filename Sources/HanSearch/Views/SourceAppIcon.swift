import SwiftUI
import HanSearchCore

struct SourceAppIcon: View {
    let app: SystemSourceApp?
    let symbol: String
    var size: CGFloat = 30
    var showsPaneSymbol = false

    var body: some View {
        if let app {
            Group {
                if let image = AppIconCache.shared.icon(for: app) {
                    Image(nsImage: image).renderingMode(.original).resizable().interpolation(.high).scaledToFit()
                } else { fallback }
            }
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if showsPaneSymbol {
                    Image(systemName: symbol).font(.system(size: size * 0.33, weight: .semibold))
                        .frame(width: size * 0.53, height: size * 0.53)
                        .background(.regularMaterial, in: Circle())
                }
            }
            .accessibilityLabel(Text(L.text(app.title)))
            .help(L.text(app.title))
        } else { fallback.frame(width: size, height: size).accessibilityHidden(true) }
    }
    private var fallback: some View {
        Image(systemName: symbol).font(.system(size: size * 0.73)).foregroundStyle(.secondary)
    }
}
