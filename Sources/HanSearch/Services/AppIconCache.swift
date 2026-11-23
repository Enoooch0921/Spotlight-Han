import AppKit
import HanSearchCore

@MainActor final class AppIconCache {
    static let shared = AppIconCache()
    private let images = NSCache<NSString, NSImage>()
    private var sourcePaths: [SystemSourceApp: String] = [:]
    func icon(_ path: String) -> NSImage {
        if let cached = images.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        images.setObject(icon, forKey: path as NSString)
        return icon
    }
    func icon(for source: SystemSourceApp) -> NSImage? {
        if let path = sourcePaths[source] { return icon(path) }
        guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.rawValue)?.path else { return nil }
        sourcePaths[source] = path
        return icon(path)
    }
}
