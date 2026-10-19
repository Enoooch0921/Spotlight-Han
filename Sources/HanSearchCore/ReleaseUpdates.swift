import Foundation

public struct ReleaseVersion: Comparable, Equatable, Sendable {
    private let numbers: [Int]
    private let prerelease: [String]
    public init?(_ value: String) {
        guard value.count < 80, let regex = try? NSRegularExpression(pattern: "^v?([0-9]+)\\.([0-9]+)\\.([0-9]+)(?:-([0-9A-Za-z.-]+))?(?:\\+[0-9A-Za-z.-]+)?$"),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        let parts = (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[range])
        }
        guard parts.count == 3 else { return nil }
        numbers = parts
        prerelease = Range(match.range(at: 4), in: value).map { String(value[$0]).split(separator: ".").map(String.init) } ?? []
    }
    public var isPrerelease: Bool { !prerelease.isEmpty }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            if let a = Int(left), let b = Int(right) { return a < b }
            if Int(left) != nil { return true }
            if Int(right) != nil { return false }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

public struct ReleaseUpdate: Codable, Equatable, Sendable {
    public let version: String
    public let releaseURL: URL
    public let dmgURL: URL
    public let prerelease: Bool
}

public enum ReleaseUpdateCatalog {
    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable { let name: String; let browser_download_url: String; let state: String }
    public static func latest(in data: Data, newerThan current: String, includePrereleases: Bool, architecture: String) throws -> ReleaseUpdate? {
        guard data.count <= 1_000_000, let installed = ReleaseVersion(current) else { return nil }
        let releases = try JSONDecoder().decode([Release].self, from: data)
        return releases.compactMap { release -> ReleaseUpdate? in
            guard !release.draft, includePrereleases || !release.prerelease, let version = ReleaseVersion(release.tag_name), includePrereleases || !version.isPrerelease, version > installed,
                  let url = ownedURL(release.html_url, prefix: "/Enoooch0921/Spotlight-Han/releases/tag/"),
                  let asset = release.assets.first(where: { asset in
                      asset.state == "uploaded" && asset.name.hasPrefix("Spotlight-Han-") && (asset.name.hasSuffix("-macOS-" + architecture + ".dmg") || asset.name.hasSuffix("-macOS-universal.dmg"))
                  }), let dmg = ownedURL(asset.browser_download_url, prefix: "/Enoooch0921/Spotlight-Han/releases/download/"), dmg.pathExtension == "dmg" else { return nil }
            return ReleaseUpdate(version: release.tag_name, releaseURL: url, dmgURL: dmg, prerelease: release.prerelease)
        }.max { ReleaseVersion($0.version)! < ReleaseVersion($1.version)! }
    }
    private static func ownedURL(_ value: String, prefix: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil, url.port == nil, url.path.hasPrefix(prefix) else { return nil }
        return url
    }
}
