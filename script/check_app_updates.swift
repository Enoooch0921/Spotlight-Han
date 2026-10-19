import Foundation
import HanSearchCore

actor UpdateFixture {
    var calls = 0
    var fails = false
    let data: Data
    init(_ data: Data) { self.data = data }
    func fail() { fails = true }
    func count() -> Int { calls }
    func fetch() async throws -> Data {
        calls += 1
        try await Task.sleep(for: .milliseconds(20))
        if fails { throw URLError(.notConnectedToInternet) }
        return data
    }
}

@main struct AppUpdateChecks {
    @MainActor static func main() async throws {
        func release(_ version: String, preview: Bool = false, draft: Bool = false, arch: String = AppUpdateService.architecture, host: String = "github.com", state: String = "uploaded") -> [String: Any] {
            ["tag_name":version, "html_url":"https://github.com/Enoooch0921/Spotlight-Han/releases/tag/" + version, "prerelease":preview, "draft":draft,
             "assets":[["name":"Spotlight-Han-" + version + "-macOS-" + arch + ".dmg", "state":state, "browser_download_url":"https://" + host + "/Enoooch0921/Spotlight-Han/releases/download/" + version + "/App.dmg"]]]
        }
        let data = try JSONSerialization.data(withJSONObject: [release("v0.9.0"), release("v0.10.0", preview:true), release("v1.0.0",draft:true), release("v2.0.0",arch:"unsupported"), release("v3.0.0",host:"example.com"), release("v4.0.0",state:"pending")])
        precondition(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.0")!)
        precondition(ReleaseVersion("1.0.0-beta.10")! > ReleaseVersion("1.0.0-beta.2")!)
        precondition(ReleaseVersion("1.0.0-beta.2")! < ReleaseVersion("1.0.0")!)
        precondition(ReleaseVersion("1.0.0+build1") == ReleaseVersion("v1.0.0+build2"))
        precondition(ReleaseVersion("nonsense") == nil)
        let stable = try ReleaseUpdateCatalog.latest(in:data, newerThan:"0.8.0", includePrereleases:false, architecture:AppUpdateService.architecture)
        precondition(stable?.version == "v0.9.0")
        let preview = try ReleaseUpdateCatalog.latest(in:data, newerThan:"0.8.0", includePrereleases:true, architecture:AppUpdateService.architecture)
        precondition(preview?.version == "v0.10.0")
        let current = try ReleaseUpdateCatalog.latest(in:data, newerThan:"0.10.0", includePrereleases:true, architecture:AppUpdateService.architecture)
        precondition(current == nil)
        let suite = "HanUpdateChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let fixture = UpdateFixture(data)
        let service = AppUpdateService(defaults:defaults,currentVersion:"0.8.0",fetch:{ try await fixture.fetch() })
        let now = Date()
        await service.checkIfNeeded(now:now)
        precondition(service.available?.version == "v0.10.0" && service.showsBanner && !service.checking)
        service.dismissedVersion = service.available?.version; precondition(!service.showsBanner)
        await service.checkIfNeeded(now:now.addingTimeInterval(3600))
        let afterFirst = await fixture.count(); precondition(afterFirst == 1)
        let restarted = AppUpdateService(defaults:defaults,currentVersion:"0.8.0",fetch:{ try await fixture.fetch() })
        precondition(restarted.available == service.available && restarted.checkedAt != nil)
        await restarted.checkIfNeeded(now:now.addingTimeInterval(7200))
        let afterRestart = await fixture.count(); precondition(afterRestart == 1, "Daily throttle must survive restarts")
        service.includesPreviews = false
        await service.check(now:now.addingTimeInterval(3))
        precondition(service.available?.version == "v0.9.0")
        await fixture.fail()
        await service.check(now:now.addingTimeInterval(4))
        precondition(service.status == "無法檢查更新，請稍後再試" && service.available?.version == "v0.9.0")
        await service.checkIfNeeded(now:now.addingTimeInterval(1000))
        let afterFailure = await fixture.count(); precondition(afterFailure == 3)
        service.automaticallyChecks = false
        await service.checkIfNeeded(now:now.addingTimeInterval(200000))
        let afterDisabled = await fixture.count(); precondition(afterDisabled == 3)
        print("PASS: update version ordering, preview channel, compatible DMG assets, draft/foreign URL rejection, cached reminders, daily throttle across restarts, failure backoff and disabled auto checks; fixture network only")
    }
}
