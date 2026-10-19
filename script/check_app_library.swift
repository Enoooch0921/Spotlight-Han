import Foundation
import HanSearchCore

@main
struct AppLibraryChecks {
    @MainActor static func main() async throws {
        let suite = "HanAppLibraryChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let apps = (0..<25).map { index in InstalledApplication(url: URL(fileURLWithPath: "/fixture/Tool\(index).app"), name: index == 1 ? "紅果短劇" : "Tool \(index)", bundleID: "fixture.\(index)", declaredCategory: index == 1 ? "public.app-category.video" : nil) }
        var opened: [URL] = [], acceptsOpen = true
        let library = AppLibraryStore(defaults: defaults, loader: { apps }, opener: { url in
            if acceptsOpen { opened.append(url) }
            return acceptsOpen
        })
        func waitForLoad(_ value: AppLibraryStore) async throws {
            for _ in 0..<100 {
                if !value.loading { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            preconditionFailure("App library did not load")
        }
        library.refresh(); library.refresh(force: true)
        try await waitForLoad(library)
        let fcp = InstalledApplication(url: URL(fileURLWithPath: "/fixture/Final Cut Pro.app"), name: "Final Cut Pro")
        let exactFCP = InstalledApplication(url: URL(fileURLWithPath: "/fixture/FCP.app"), name: "FCP")
        let aliasLibrary = AppLibraryStore(defaults: defaults, loader: { [fcp, exactFCP] }, opener: { _ in false })
        aliasLibrary.refresh(); try await waitForLoad(aliasLibrary)
        precondition(aliasLibrary.items(query: "FCP").map(\.id) == [exactFCP.id, fcp.id])
        precondition(aliasLibrary.items(query: "fcpx").map(\.id) == [fcp.id])
        aliasLibrary.customAliases = { $0.id == fcp.id ? ["剪片神器"] : [] }
        precondition(aliasLibrary.items(query: "剪片神器").map(\.id) == [fcp.id])
        precondition(aliasLibrary.items(query: "不存在的縮寫").isEmpty)
        precondition(library.applications.count == 25 && library.group == .all)
        precondition(library.items(query: "红果短剧").map(\.id) == [apps[1].id])
        precondition(library.items(query: "", group: .recent).isEmpty)
        library.togglePin(apps[1]); library.setCategory(apps[1], group: .work)
        precondition(library.items(query: "", group: .pinned).map(\.id) == [apps[1].id])
        precondition(library.items(query: "", group: .creative).isEmpty)
        precondition(library.items(query: "", group: .work).map(\.id) == [apps[1].id])
        let moved = InstalledApplication(url: URL(fileURLWithPath: "/another/Drama.app"), name: "紅果短劇", bundleID: apps[1].bundleID)
        precondition(library.isPinned(moved) && library.category(moved) == .work)
        library.listView = true
        let reloaded = AppLibraryStore(defaults: defaults, loader: { apps }, opener: { _ in false })
        precondition(reloaded.isPinned(apps[1]) && reloaded.category(apps[1]) == .work && reloaded.listView)
        library.setCategory(apps[1], group: nil)
        precondition(library.category(apps[1]) == .creative)
        library.group = .all; library.selectFirst(query: "红果")
        precondition(library.selected(query: "红果")?.id == apps[1].id)
        library.move(5, query: "红果"); precondition(library.selection == apps[1].id)
        for app in apps { precondition(library.open(app)) }
        precondition(library.recent.count == 20)
        precondition(library.items(query: "", group: .recent).first?.id == apps.last?.id)
        let previous = library.recent
        acceptsOpen = false; precondition(!library.open(apps[0]))
        precondition(library.recent == previous && !library.error.isEmpty && opened.count == 25)
        library.togglePin(apps[1]); precondition(library.items(query: "", group: .pinned).isEmpty)
        precondition(library.createCategory("  ") == nil)
        precondition(library.createCategory(String(repeating: "a", count: 31)) == nil)
        precondition(library.createCategory("全部 App") == nil)
        let first = library.createCategory("教會")!, second = library.createCategory("影片製作")!, third = library.createCategory("工作")!
        precondition(library.createCategory("教會") == nil)
        precondition(library.selectedCustomGroupID == third.id)
        precondition(library.drop(["han-app:" + apps[1].id], to: first.id))
        precondition(library.items(query: "红果", custom: first.id).map(\.id) == [apps[1].id])
        precondition(library.items(query: "", group: .creative).isEmpty)
        library.selectCustom(first.id)
        precondition(library.items(query: "").count == 1 && library.selectedTitle == "教會")
        precondition(library.items(query: "", group: .all).count == 25)
        precondition(!library.drop(["/Applications/Fake.app", "han-app:/unknown.app"], to: first.id))
        precondition(!library.drop(["han-app:" + apps[0].id], to: "unknown"))
        precondition(!library.drop(["han-app:" + apps[0].id], to: ApplicationGroup.recent.rawValue))
        precondition(library.drop(["han-app:" + apps[1].id], to: ApplicationGroup.pinned.rawValue))
        precondition(library.drop(["han-app:" + apps[1].id], to: ApplicationGroup.pinned.rawValue))
        precondition(library.pinned.count == 1 && library.categoryID(apps[1]) == first.id)
        precondition(library.drop(["han-category:" + first.id], to: third.id))
        precondition(Array(library.orderedCategoryIDs.prefix(3)) == [second.id, third.id, first.id])
        precondition(library.drop(["han-category:" + first.id], to: second.id))
        precondition(Array(library.orderedCategoryIDs.prefix(3)) == [first.id, second.id, third.id])
        precondition(library.renameCategory(first.id, name: "教會常用", symbol: "waveform"))
        precondition(!library.renameCategory(first.id, name: second.name))
        let saved = AppLibraryStore(defaults: defaults, loader: { apps }, opener: { _ in false })
        precondition(saved.customGroups == library.customGroups && saved.categoryID(moved) == first.id && saved.customGroups.first?.symbol == "waveform" && saved.orderedCategoryIDs == library.orderedCategoryIDs)
        precondition(library.selectedTitle == "教會常用")
        library.deleteCategory(first.id)
        precondition(library.selectedCustomGroupID == nil && library.group == .all)
        precondition(library.categoryID(apps[1]) == ApplicationGroup.creative.rawValue && library.isPinned(apps[1]))
        let deleted = AppLibraryStore(defaults: defaults, loader: { apps }, opener: { _ in false })
        precondition(!deleted.customGroups.contains { $0.id == first.id } && deleted.categoryID(apps[1]) == ApplicationGroup.creative.rawValue)
        precondition(opened.count == 25, "Organizing categories must never launch apps")
        precondition(library.drop(["han-category:" + ApplicationGroup.utilities.rawValue], to: ApplicationGroup.all.rawValue))
        precondition(library.orderedCategoryIDs.firstIndex(of: "utilities")! < library.orderedCategoryIDs.firstIndex(of: "all")!)
        precondition(!library.acceptsDrop(["han-app:" + apps[0].id], to: "all"))
        precondition(library.acceptsDrop(["han-category:utilities"], to: "all"))
        let legacy = Data("[{\"id\":\"custom:legacy\",\"name\":\"Legacy\"}]".utf8)
        let legacyGroups = try JSONDecoder().decode([UserApplicationGroup].self, from: legacy)
        precondition(legacyGroups.first?.symbol == "folder")
        let vendorApps = [
            InstalledApplication(url: URL(fileURLWithPath: "/fixture/Waves/Tool.app"), name: "Tool", bundleID: "com.WavesAudio.Tool"),
            InstalledApplication(url: URL(fileURLWithPath: "/fixture/RX.app"), name: "RX", bundleID: "com.izotope.RX12"),
            InstalledApplication(url: URL(fileURLWithPath: "/fixture/Final Cut.app"), name: "FCP", bundleID: "com.apple.FinalCutApp"),
            InstalledApplication(url: URL(fileURLWithPath: "/fixture/Excel.app"), name: "Excel", bundleID: "com.microsoft.Excel"),
            InstalledApplication(url: URL(fileURLWithPath: "/fixture/Defender.app"), name: "Defender", bundleID: "com.microsoft.wdav.shim")]
        let suggestions = AppLibraryStore(defaults: defaults, loader: { vendorApps }, opener: { _ in false })
        suggestions.refresh(); try await waitForLoad(suggestions)
        suggestions.setCategory(vendorApps[2], group: .work)
        precondition(suggestions.applySuggestions([.waves, .izotope, .production, .office]) == 3)
        precondition(suggestions.categoryID(vendorApps[0]) == "custom:suggested.waves")
        precondition(suggestions.categoryID(vendorApps[2]) == "work", "Suggestions preserve manual overrides")
        precondition(suggestions.categoryID(vendorApps[4]) == "other", "Office must not absorb every Microsoft app")
        precondition(suggestions.applySuggestions([.waves, .izotope, .production, .office]) == 0)
        precondition(ApplicationSuggestion.production.matches(InstalledApplication(url: URL(fileURLWithPath: "/fixture/Tool.app"), name: "Tool", bundleID: "com.rationalacoustics.smaart")))
        let applePro = InstalledApplication(url: URL(fileURLWithPath: "/Applications/Logic Pro.app"), name: "Logic Pro", bundleID: "com.apple.logic10")
        let systemApp = InstalledApplication(url: URL(fileURLWithPath: "/System/Applications/Notes.app"), name: "Notes", bundleID: "com.apple.Notes")
        precondition(systemApp.isSystemApplication && !applePro.isSystemApplication)
        precondition(InstalledApplication(url: URL(fileURLWithPath: "/Applications/Safari.app"), name: "Safari", bundleID: "com.apple.Safari").isSystemApplication)
        print("PASS: app-library filtering, fixed categories, pinning/reclassification persistence across moves, recent successful launches, keyboard bounds, view preference and failed-open handling, custom group validation/create/rename/delete/order persistence, app drops and rejected foreign payloads; fake apps/opener only")
    }
}
