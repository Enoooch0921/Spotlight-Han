import Foundation
import HanSearchCore

@main struct TaiwanSearchChecks {
    @MainActor static func main() async throws {
        let suite = "HanTaiwanChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "autoRefreshSources.v1")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        func wait(_ message: String, _ predicate: () -> Bool) async throws {
            for _ in 0..<500 { if predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
            preconditionFailure(message)
        }
        let calculator = InstalledApplication(url: root.appendingPathComponent("Calculator.app"), name: "Calculator", bundleID: "com.apple.calculator")
        let originalApp = InstalledApplication(url: root.appendingPathComponent("rnr.app"), name: "rnr")
        let printer = InstalledApplication(url: root.appendingPathComponent("Printer.app"), name: "打印工具")
        let literalPrint = InstalledApplication(url: root.appendingPathComponent("Print.app"), name: "列印工具")
        let library = AppLibraryStore(defaults: defaults, loader: { [calculator, originalApp, printer, literalPrint] }, opener: { _ in false })
        library.refresh(); try await wait("Fixture App library did not load") { !library.loading }
        // Simulate even an adversarial learned order: original matches retain their own partition.
        library.rankSearch = { apps, _ in Array(apps.reversed()) }
        precondition(library.items(query: "rnr").map(\.id) == [originalApp.id, calculator.id])
        precondition(library.items(query: "列印").map(\.id) == [literalPrint.id, printer.id])
        precondition(library.items(query: "打印").map(\.id) == [printer.id, literalPrint.id])
        library.customAliases = { $0.id == calculator.id ? ["rnr"] : [] }
        precondition(library.supplement(for: calculator, query: "rnr") == nil, "An explicitly saved alias is a primary match")

        let now = Date()
        let records = (0..<55).map { i in
            PersonalRecord(id: "event:related\(i)", title: "打印教學 \(i)", subtitle: "fixture", text: "打印", symbol: "calendar", mode: .calendar, action: .details("original fixture"), startDate: now.addingTimeInterval(Double(i+1)*3600))
        } + [PersonalRecord(id: "event:direct", title: "列印", subtitle: "fixture", text: "原始內容", symbol: "calendar", mode: .calendar, action: .details("原始內容"), startDate: now.addingTimeInterval(100*3600)),
             PersonalRecord(id: "event:year", title: "115年報告", subtitle: "fixture", text: "測試文字", symbol: "calendar", mode: .calendar, action: .details("fixture")),
             PersonalRecord(id: "event:temperature", title: "37度實驗", subtitle: "fixture", text: "測試文字", symbol: "calendar", mode: .calendar, action: .details("fixture"))]
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults,
            sourceAccessCheck: { _ in true }, eventSourceLoader: { _ in PersonalLoad(records: records, status: "fixture loaded") }, eventCalendarLoader: { [] },
            contentSearcher: { _, _ in SearchResponse(items: []) }, fileCreationDateLoader: { _ in nil }, documentIndexURL: root.appendingPathComponent("Index/test.sqlite"))
        defaults.set([SearchMode.calendar.rawValue], forKey: "enabledSources.v1")
        store.sourceHealth[.calendar] = SourceHealth(phase: .ready, lastSuccess: now.addingTimeInterval(-600), invalidated: true)
        store.autoRefreshEnabled = true; store.refreshAuthorizedSources()
        try await wait("Injected calendar loader did not complete") { store.connecting.isEmpty && store.personalStatus[.calendar] == "fixture loaded" }
        store.autoRefreshEnabled = false
        store.mode = .calendar; store.query = "列印"; store.search()
        try await wait("Calendar fixture did not finish loading/searching") { store.connecting.isEmpty && !store.searching && store.quickResults.contains { $0.id == "quick:event:direct" } }
        precondition(store.quickResults.count == 50, "The original match must survive a full supplemental result cap")
        precondition(store.allIDs.first == "quick:event:direct", "Chronology cannot put an inferred match ahead of original evidence")
        for _ in 0..<30 { store.habits.record(query: "列印", identity: "quick:event:related0", kind: .calendar) }
        store.mode = .all; store.search()
        try await wait("All fixture query did not finish") { !store.searching }
        let ids = store.allIDs
        precondition(ids.firstIndex(of: "quick:event:direct")! < ids.firstIndex(of: "quick:event:related0")!, "Learning cannot promote related wording above the original query")

        let direct = SearchItem(url: root.appendingPathComponent("列印.txt"), source: "fixture")
        let alternative = SearchItem(url: root.appendingPathComponent("打印.txt"), source: "fixture", excerpt: "打印文字", supplement: SearchSupplement(kind: .taiwanVocabulary, query: "打印"))
        store.quickResults = []; store.results = [alternative, direct]
        for _ in 0..<30 { store.habits.record(query: "列印", identity: "file:" + alternative.id, kind: .file) }
        for sort in FileResultSort.allCases {
            store.fileSort = sort
            store.fileDates = [alternative.id: now, direct.id: now.addingTimeInterval(-86400)]
            precondition(store.allIDs == [direct.id, alternative.id], "Date and learned sorting must stay inside relevance partitions")
        }
        let native = SearchItem(url: root.appendingPathComponent("unrelated.pdf"), source: "文件・系統索引")
        store.results.append(native); store.showOtherIndexedResults = true
        precondition(store.allIDs.last == native.id, "Unverified native-index candidates remain after verified supplemental hits")
        print("PASS: App primary/custom-alias partitions, All/calendar result caps, learned preferences, date sorting and unverified-index boundaries; fake sources and isolated defaults only")
        precondition(store.temperaturePreference == .system, "New installs follow the macOS temperature preference")
        store.temperaturePreference = .celsius; store.query = "37度"; store.search()
        try await wait("Celsius temperature inference did not appear") { !store.searching && store.quickResults.contains { $0.id == "quick:temperature" && $0.title == "98.6 °F" } }
        precondition(store.quickResults.contains { $0.id == "quick:event:temperature" }, "Automatic temperature must preserve original-query personal/file search")
        store.temperaturePreference = .fahrenheit
        try await wait("Preference change did not update the conversion") { !store.searching && store.quickResults.contains { $0.id == "quick:temperature" && $0.subtitle.contains("37 °F") } }
        let restored = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults, documentIndexURL: root.appendingPathComponent("Index/test.sqlite"))
        precondition(restored.temperaturePreference == .fahrenheit, "Manual override persists across launches")
        store.query = "37攝氏度"; store.search()
        try await wait("Explicit scale was overridden by preferences") { !store.searching && store.quickResults.contains { $0.id == "quick:temperature" && $0.title == "98.6 °F" } }
        store.query = "115年"; store.search()
        try await wait("Year conversion did not appear") { !store.searching && store.quickResults.contains { $0.id == "quick:year-conversion" && $0.title == "西元 2026 年" } }
        precondition(store.quickResults.contains { $0.id == "quick:event:year" }, "Year conversion must preserve matching search results")
        print("PASS: system-default temperature preference, persisted C/F override, immediate recalculation, explicit-scale precedence and normal search beside automatic conversion")
    }
}
