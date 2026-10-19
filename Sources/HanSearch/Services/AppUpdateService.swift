import Foundation
import Combine
import HanSearchCore

@MainActor
final class AppUpdateService: ObservableObject {
    @Published private(set) var available: ReleaseUpdate?
    @Published private(set) var checking = false
    @Published private(set) var checkedAt: Date?
    @Published private(set) var status = "尚未檢查更新"
    @Published var dismissedVersion: String?
    @Published var automaticallyChecks: Bool { didSet { defaults.set(automaticallyChecks, forKey: "updates.automatic.v1") } }
    @Published var includesPreviews: Bool {
        didSet {
            defaults.set(includesPreviews, forKey: "updates.previews.v1")
            if !includesPreviews, available?.prerelease == true { available = nil }
        }
    }
    let currentVersion: String
    private let defaults: UserDefaults
    private let fetch: @Sendable () async throws -> Data
    private var timer: Timer?
    private var lastAttempt = Date.distantPast
    init(defaults: UserDefaults = .standard, currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0", fetch: @escaping @Sendable () async throws -> Data = { try await AppUpdateService.fetchReleases() }) {
        self.defaults = defaults; self.currentVersion = currentVersion; self.fetch = fetch
        automaticallyChecks = defaults.object(forKey: "updates.automatic.v1") as? Bool ?? true
        includesPreviews = defaults.object(forKey: "updates.previews.v1") as? Bool ?? currentVersion.hasPrefix("0.")
        lastAttempt = defaults.object(forKey: "updates.lastAttempt.v1") as? Date ?? .distantPast
        checkedAt = defaults.object(forKey: "updates.checkedAt.v1") as? Date
        if let data = defaults.data(forKey: "updates.releases.v1") {
            available = try? ReleaseUpdateCatalog.latest(in: data, newerThan: currentVersion, includePrereleases: includesPreviews, architecture: Self.architecture)
            status = available == nil ? "目前已是最新可用版本" : "有新版本可下載"
        }
    }
    var showsBanner: Bool { available != nil && dismissedVersion != available?.version }
    func start() {
        guard timer == nil else { return }
        Task { try? await Task.sleep(for: .seconds(3)); await checkIfNeeded() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfNeeded() }
        }
    }
    func checkIfNeeded(now: Date = Date()) async {
        guard automaticallyChecks, now.timeIntervalSince(lastAttempt) >= (defaults.bool(forKey: "updates.succeeded.v1") ? 86400 : 3600) else { return }
        await check(now: now)
    }
    func check(now: Date = Date()) async {
        guard !checking else { return }
        checking = true; status = "正在檢查更新…"; lastAttempt = now
        defaults.set(now, forKey: "updates.lastAttempt.v1"); defaults.set(false, forKey: "updates.succeeded.v1")
        defer { checking = false }
        do {
            let data = try await fetch()
            let candidate = try ReleaseUpdateCatalog.latest(in: data, newerThan: currentVersion, includePrereleases: includesPreviews, architecture: Self.architecture)
            available = candidate
            defaults.set(data, forKey: "updates.releases.v1"); defaults.set(now, forKey: "updates.checkedAt.v1"); defaults.set(true, forKey: "updates.succeeded.v1")
            checkedAt = now
            status = available == nil ? "目前已是最新可用版本" : "有新版本可下載"
        } catch { status = "無法檢查更新，請稍後再試" }
    }
    nonisolated static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    nonisolated static func fetchReleases() async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Enoooch0921/Spotlight-Han/releases?per_page=20")!)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Spotlight-Han-Update-Check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 1_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
}
