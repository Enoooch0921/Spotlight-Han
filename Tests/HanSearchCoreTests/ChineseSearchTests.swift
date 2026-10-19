import Foundation
import HanSearchCore

private func XCTAssertTrue(_ condition: Bool) { precondition(condition) }
private func XCTAssertFalse(_ condition: Bool) { precondition(!condition) }
private func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
private func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
private func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Expected \(rhs), received \(lhs)") }

@main
struct CheckRunner {
    static func main() async throws {
        if CommandLine.arguments.contains("--benchmark") {
            guard let cache = FileCatalog.load() else { print("No filename cache yet. Open HanSearch and allow its scan to finish."); return }
            var durations: [Double] = []
            for _ in 0..<20 {
                let start = Date()
                _ = FileCatalog.search(cache.entries, query: "主日", mode: .videos)
                durations.append(Date().timeIntervalSince(start) * 1000)
            }
            durations.sort()
            print(String(format: "Filename catalog: %d entries; video name matching median %.2f ms, p95 %.2f ms (20 runs, engine only)", cache.entries.count, durations[10], durations[18]))
            return
        }
        let tests = ChineseSearchTests()
        if CommandLine.arguments.contains("--task-parser-only") {
            try await tests.testNaturalTaskComposer()
            print("PASS: relocated local date parser, Chinese/English drafts, ranges and validation")
            return
        }
        try tests.testApplicationCatalog()
        try tests.testPhoneticTitles()
        tests.testAppAndFilenameAcrossScripts()
        tests.testNormalizationAvoidsOneSimplifiedToManyTraditionalMisses()
        tests.testMetadataPredicateTreatsInputAsData()
        tests.testMergeDeduplicatesAndKeepsPreview()
        try tests.testRealDocxExtractionAndCrossScriptContent()
        try tests.testRealSpotlightQueryDoesNotError()
        try tests.testCalculator()
        tests.testConversions()
        try tests.testIndependentFilenameCatalog()
        tests.testPersonalRecordCrossScriptMatching()
        tests.testSafeQuickActions()
        try tests.testTaskCommands()
        try await tests.testNaturalTaskComposer()
        tests.testCurrencyQueries()
        tests.testCurrencyCountryNames()
        tests.testSearchHighlights()
        try tests.testShortcutBindings()
        tests.testLauncherVisibilityAfterSwitchingApps()
        tests.testSourceConnectionQueue()
        try await tests.testBoundedSystemCallbacks()
        try tests.testCancellableStreamingProcesses()
        tests.testSystemShortcutPreferences()
        tests.testSystemSettingsSearch()
        tests.testSourceFreshness()
        tests.testNotesResumeState()
        tests.testEventAccessCallbackState()
        tests.testCalendarChronologicalSort()
        print("PASS: 29 check groups — phonetic titles/initials, Chinese matching, ambiguous characters, escaping, deduplication, real DOCX extraction, Spotlight grammar, calculator, unit conversion, independent filename cache, personal-record matching, safe URL actions, calendar/reminder parsing and system Clock date boundaries, currency aliases and conversion, shortcut persistence and validation, launcher visibility after switching apps, serialized source connections, callback timeout/cancellation, streaming process cancellation, system shortcut preference decoding, multilingual settings pane search, currency country aliases, original-text highlighting and hit-centered excerpts.")
    }
}

final class ChineseSearchTests {
    func testPhoneticTitles() throws {
        let keys = PhoneticSearch("紅果短劇")
        for query in ["hongguo", "hóng guǒ", "hong2 guo3", "hgdj", "HGDJ", "ㄏㄨㄥˊ ㄍㄨㄛˇ", "ㄏㄨㄥㄍㄨㄛ", "ㄏㄍㄉㄐ"] { XCTAssertTrue(keys.matches(query)) }
        for query in ["h", "xyz", "ㄏabc", "***", "紅果"] { XCTAssertFalse(keys.matches(query)) }
        XCTAssertFalse(PhoneticSearch("Hello").matches("hl"))
        for query in ["lüyou", "lvyou", "lu:you"] { XCTAssertTrue(PhoneticSearch("旅遊").matches(query)) }
        let terminal = InstalledApplication(url: URL(fileURLWithPath: "/fixture/Terminal.app"), name: "Terminal", bundleID: "com.apple.Terminal")
        for query in ["zdj", "zhongduanji", "ㄓㄉㄐ", "终端机"] { XCTAssertTrue(terminal.matches(query)) }
        let file = CatalogEntry(url: URL(fileURLWithPath: "/fixture/紅果短劇.mp4"))
        for query in ["hongguo", "hgdj", "ㄏㄍㄉㄐ"] { XCTAssertEqual(FileCatalog.search([file], query: query, mode: .videos).first?.id, file.path) }
        XCTAssertTrue(FileCatalog.search([file], query: "other", mode: .videos, aliasPaths: [file.path]).count == 1)
        XCTAssertTrue(FileCatalog.search([file], query: "other", mode: .videos, folder: URL(fileURLWithPath: "/elsewhere"), aliasPaths: [file.path]).isEmpty)
        let record = PersonalRecord(id: "note:fixture", title: "鼎達叔叔", subtitle: "", text: "測試全文", symbol: "note", mode: .notes, action: .details("fixture"))
        for query in ["dingda", "ddss", "ㄉㄧㄥˇ ㄉㄚˊ", "ㄉㄉㄕㄕ"] { XCTAssertNotNil(record.result(query: query, mode: .notes)) }
        XCTAssertNil(record.result(query: "ceshi", mode: .notes)) // Only titles are transliterated.
        XCTAssertNotNil(record.result(query: "nickname", mode: .notes, aliasMatch: true))
        XCTAssertNil(record.result(query: "nickname", mode: .contacts, aliasMatch: true))
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as! [String: Any]
        old.removeValue(forKey: "phonetics")
        let migrated = try JSONDecoder().decode(CatalogEntry.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(migrated.phonetics.matches("hgdj"))
    }
    func testApplicationCatalog() throws {
        XCTAssertEqual(ApplicationGroup.declared("public.app-category.productivity"), .work)
        XCTAssertEqual(ApplicationGroup.declared("public.app-category.graphics-design"), .creative)
        XCTAssertEqual(ApplicationGroup.declared("public.app-category.developer-tools"), .development)
        XCTAssertEqual(ApplicationGroup.declared("public.app-category.role-playing-games"), .games)
        XCTAssertEqual(ApplicationGroup.declared("fake-games"), .other)
        XCTAssertEqual(ApplicationGroup.declared(nil), .other)
        XCTAssertFalse(ApplicationGroup.assignable.contains(.pinned))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HanAppCatalog-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ relative: String, _ name: String, _ id: String, _ category: String?) throws {
            let contents = root.appendingPathComponent(relative).appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture"]
            info["LSApplicationCategoryType"] = category
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        try bundle("Drama.app", "紅果短劇", "fixture.drama", "public.app-category.video")
        try bundle("Tools/Tool.app", "工具", "fixture.tool", nil)
        try bundle("Drama.app/Contents/Helpers/HiddenHelper.app", "Helper", "fixture.helper", nil)
        try bundle(".Hidden.app", "Hidden", "fixture.hidden", nil)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: root.appendingPathComponent("Drama.app"))
        let apps = ApplicationCatalog.scan(roots: [root])
        XCTAssertEqual(apps.count, 2)
        let drama = apps.first { $0.bundleID == "fixture.drama" }!
        XCTAssertEqual(drama.name, "紅果短劇"); XCTAssertEqual(drama.group, .creative)
        XCTAssertTrue(drama.matches("红果短剧")); XCTAssertTrue(drama.matches("Drama"))
        XCTAssertFalse(drama.matches("Not installed"))
        let logic = InstalledApplication(url: URL(fileURLWithPath: "/fixture/Logic Pro.app"), name: "Logic Pro", bundleID: "com.apple.logic10")
        for query in ["logicpro", "LOGICPRO", "Logic Pro", "logic-pro", "logic_pro"] { XCTAssertTrue(logic.matches(query)) }
        XCTAssertFalse(logic.matches("procom")) // Do not join separate metadata fields.
        let fcp = InstalledApplication(url: URL(fileURLWithPath: "/fixture/Final Cut Pro.app"), name: "Final Cut Pro Creator Studio")
        XCTAssertTrue(fcp.matches("finalcutpro"))
        for query in ["fcp", "FCP", "fcpx", "fcp creator"] { XCTAssertTrue(fcp.matches(query)) }
        XCTAssertFalse(fcp.matches("cp"))
        XCTAssertTrue(InstalledApplication(url: URL(fileURLWithPath: "/fixture/Renamed.app"), name: "剪輯", bundleID: "com.apple.FinalCut").matches("fcp"))
        XCTAssertTrue(InstalledApplication(url: URL(fileURLWithPath: "/fixture/Adobe Photoshop 2026.app"), name: "Adobe Photoshop 2026").matches("PS"))
        XCTAssertFalse(InstalledApplication(url: URL(fileURLWithPath: "/fixture/Fancy Creative Product.app"), name: "Fancy Creative Product").matches("fcp"))
        let exactFCP = SearchItem(url: URL(fileURLWithPath: "/fixture/FCP.app"), name: "FCP", source: "fixture")
        let aliasOrder = SearchService.merge([fcp.searchItem, exactFCP, similarlyNamedFileFixture()], query: "fcp")
        XCTAssertEqual(aliasOrder.prefix(2).map(\.id), [exactFCP.id, fcp.id])
        let similarlyNamedFile = SearchItem(url: URL(fileURLWithPath: "/fixture/logicpro guide.pdf"), source: "fixture")
        let spotlightApp = SearchItem(url: logic.url, source: "Spotlight")
        let merged = SearchService.merge([similarlyNamedFile, spotlightApp, logic.searchItem], query: "logicpro")
        XCTAssertEqual(merged.first?.id, logic.id)
        XCTAssertEqual(merged.first?.applicationIdentifier, logic.preferenceID)
        XCTAssertEqual(apps.first { $0.bundleID == "fixture.tool" }?.group, .other)
    }

    private func similarlyNamedFileFixture() -> SearchItem {
        SearchItem(url: URL(fileURLWithPath: "/fixture/fcp guide.pdf"), source: "fixture")
    }

    func testEventAccessCallbackState() {
        var events = EventAccessState()
        XCTAssertFalse(events.observe(.notDetermined))
        events.completed(granted: true)
        XCTAssertTrue(events.observe(.notDetermined)) // exact observed macOS callback/query disagreement
        XCTAssertTrue(events.observe(.notDetermined))
        XCTAssertFalse(events.observe(.denied))
        XCTAssertFalse(events.observe(.notDetermined))
        events.completed(granted: true)
        XCTAssertFalse(events.observe(.restricted))
        events.completed(granted: true)
        XCTAssertFalse(events.observe(.writeOnly))
        events.completed(granted: true)
        XCTAssertFalse(events.observe(nil))
        XCTAssertTrue(events.observe(.fullAccess))
        XCTAssertFalse(events.observe(.notDetermined)) // a reset after an observed grant is not stale state
        events.completed(granted: false)
        XCTAssertFalse(events.observe(.notDetermined))
        var reminders = EventAccessState()
        events.completed(granted: true)
        XCTAssertFalse(reminders.observe(.notDetermined)) // entity grants never leak to another type
        reminders.completed(granted: true)
        XCTAssertTrue(reminders.observe(.notDetermined))
    }

    func testSourceFreshness() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var health = SourceHealth(phase: .loading)
        XCTAssertFalse(health.hasSnapshot); XCTAssertFalse(health.needsAttention(at: now))
        health.succeeded(at: now)
        XCTAssertTrue(health.hasSnapshot); XCTAssertFalse(health.isStale(at: now.addingTimeInterval(899)))
        XCTAssertTrue(health.isStale(at: now.addingTimeInterval(900)))
        XCTAssertTrue(health.needsAttention(at: now.addingTimeInterval(901)))
        health.invalidated = true; XCTAssertTrue(health.needsAttention(at: now))
        health.succeeded(at: now); XCTAssertFalse(health.invalidated)
        XCTAssertFalse(health.shouldRefresh(at: now.addingTimeInterval(299), interval: 300))
        XCTAssertTrue(health.shouldRefresh(at: now.addingTimeInterval(300), interval: 300))
        XCTAssertTrue(health.shouldRefresh(at: now, interval: 300, force: true))
        health.phase = .loading; XCTAssertFalse(health.shouldRefresh(at: now.addingTimeInterval(1000), interval: 300, force: true))
        health.phase = .failed
        XCTAssertFalse(health.shouldRefresh(at: now.addingTimeInterval(300), interval: 300))
        XCTAssertFalse(health.shouldRefresh(at: now.addingTimeInterval(300), interval: 300, force: true))
        XCTAssertTrue(health.shouldRefresh(at: now.addingTimeInterval(900), interval: 300))
        XCTAssertTrue(health.needsAttention(at: now)); XCTAssertEqual(health.lastSuccess, now)
        XCTAssertTrue(health.hasSnapshot)
        for phase: SourceHealth.Phase in [.failed, .incomplete, .stopped, .needsPermission] {
            XCTAssertTrue(SourceHealth(phase: phase).needsAttention(at: now))
        }
        var partial = SourceHealth(phase: .loading, partialUpdate: now)
        XCTAssertTrue(partial.hasSnapshot)
        partial.phase = .failed; XCTAssertTrue(partial.needsAttention(at: now))
        partial.succeeded(at: now); XCTAssertNil(partial.partialUpdate)
        partial.completed(at: now.addingTimeInterval(60), complete: false)
        XCTAssertEqual(partial.phase, .incomplete); XCTAssertEqual(partial.lastSuccess, now)
        partial.recordFailure(SourceAccessFailure(source: "行事曆", status: .denied), at: now)
        XCTAssertEqual(partial.phase, .needsPermission); XCTAssertEqual(partial.permissionStatus, .denied)
        XCTAssertTrue(partial.offersPrivacySettings)
        for status: EventAccessState.Status? in [nil, .notDetermined, .fullAccess] {
            XCTAssertFalse(SourceHealth(phase: .needsPermission, permissionStatus: status).offersPrivacySettings)
        }
        for status: EventAccessState.Status in [.denied, .restricted, .writeOnly] {
            XCTAssertTrue(SourceHealth(phase: .needsPermission, permissionStatus: status).offersPrivacySettings)
            XCTAssertFalse(SourceHealth(phase: .ready, permissionStatus: status).offersPrivacySettings)
            XCTAssertFalse(SourceHealth(phase: .loading, permissionStatus: status).offersPrivacySettings)
        }
        XCTAssertFalse(SourceHealth(phase: .needsPermission, invalidated: true).shouldRefresh(at: now, interval: 300, force: true))
        XCTAssertEqual(partial.lastSuccess, now)
        partial.recordFailure(ProcessFailure.failed("讀取逾時"), at: now)
        XCTAssertEqual(partial.phase, .failed); XCTAssertNil(partial.permissionStatus)
    }
    func testNotesResumeState() {
        var scan = NotesReadState(identifiers: ["a", "locked", "b", "slow", "a"])
        XCTAssertEqual(scan.total, 4)
        scan.receive(id: "a", title: "簡體筆記", text: "电脑课程", isTruncated: false)
        scan.receive(id: "a", title: "duplicate", text: "ignored", isTruncated: false)
        XCTAssertEqual(scan.records.count, 1); XCTAssertEqual(scan.textCount, 4)
        scan.skip(id: "locked", protected: true)
        let checkpoint = scan
        scan.timedOut(id: "b")
        XCTAssertEqual(scan.pending, ["slow", "b"])
        scan.receive(id: "slow", title: "Later item", text: "Read after timeout", isTruncated: false)
        scan.receive(id: "b", title: "Resumed", text: "Second batch", isTruncated: false)
        XCTAssertEqual(scan.processed, 4); XCTAssertFalse(scan.hasMore); XCTAssertTrue(scan.complete)
        XCTAssertEqual(scan.protectedCount, 1)
        XCTAssertEqual(scan.records.map(\.id), ["note:a", "note:b", "note:slow"])
        XCTAssertTrue(scan.records[0].result(query: "電腦", mode: .notes) != nil)
        XCTAssertEqual(checkpoint.processed, 2) // earlier checkpoints remain independent
        var blocked = NotesReadState(identifiers: ["bad", "good"])
        blocked.timedOut(id: "bad"); blocked.receive(id: "good", title: "Good", text: "OK", isTruncated: false)
        blocked.timedOut(id: "bad")
        XCTAssertFalse(blocked.hasMore); XCTAssertFalse(blocked.complete)
        XCTAssertEqual(blocked.incompleteCount, 1); XCTAssertEqual(blocked.records.count, 1)
        var huge = NotesReadState(identifiers: ["huge"])
        huge.receive(id: "huge", title: "Title remains searchable", text: String(repeating: "x", count: 100001), isTruncated: false)
        XCTAssertEqual(huge.records.count, 1); XCTAssertFalse(huge.complete); XCTAssertEqual(huge.textCount, 0)
        XCTAssertEqual(NotesReadState(identifiers: (0..<2001).map(String.init)).total, 2000)
        XCTAssertTrue(NotesReadState(identifiers: (0..<2001).map(String.init)).capped)
        var health = SourceHealth(phase: .loading)
        let revision = health.changeRevision
        health.markChanged()
        health.completed(at: Date(), complete: true, observedRevision: revision)
        XCTAssertTrue(health.invalidated) // a change during a read survives completion
        let current = health.changeRevision
        health.completed(at: Date(), complete: true, observedRevision: current)
        XCTAssertFalse(health.invalidated)
        var queue = SourceConnectionQueue()
        queue.enqueue(.mail, allowPrompt: true)
        queue.enqueue(.notes, allowPrompt: false, priority: true)
        XCTAssertEqual(queue.next()?.source, .notes)
        queue.enqueue(.calendar, allowPrompt: false, priority: true)
        XCTAssertNil(queue.next()) // priority never preempts active work
        queue.finish(); XCTAssertEqual(queue.next()?.source, .calendar)
        queue.finish(); XCTAssertEqual(queue.next()?.allowPrompt, true)
    }

    func testCalendarChronologicalSort() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, _ offset: Double?, end: Double? = nil) -> PersonalRecord {
            PersonalRecord(id: id, title: "Sophie", subtitle: "測試", text: "會議", symbol: "calendar", mode: .calendar, action: .details(id), startDate: offset.map { now.addingTimeInterval($0) }, endDate: end.map { now.addingTimeInterval($0) })
        }
        let records = [event("old", -1000), event("far", 500), event("missing", nil), event("near", 100), event("past", -100), event("ongoing", -200, end: 100)]
        XCTAssertEqual(CalendarResultSort.upcoming.sorted(records, now: now).map(\.id), ["ongoing","near","far","past","old","missing"])
        XCTAssertEqual(CalendarResultSort.newest.sorted(records, now: now).map(\.id), ["far","near","past","ongoing","old","missing"])
        XCTAssertEqual(CalendarResultSort.oldest.sorted(records, now: now).map(\.id), ["old","ongoing","past","near","far","missing"])
        let note = PersonalRecord(id: "note", title: "Sophie", subtitle: "", text: "", symbol: "note", mode: .notes, action: .details(""))
        let mixed = [records[0], note, records[3]]
        XCTAssertEqual(CalendarResultSort.upcoming.sorted(mixed, now: now).map(\.id), ["near","note","old"])
        XCTAssertEqual(CalendarResultSort.upcoming.sorted([event("b", 100),event("a",100)], now: now).map(\.id), ["a","b"])
        let matches = CalendarResultSort.upcoming.sorted(records, now: now).compactMap { $0.result(query: "sophie", mode: .calendar) }
        XCTAssertEqual(matches.map(\.id), ["quick:ongoing","quick:near","quick:far","quick:past","quick:old","quick:missing"])
        XCTAssertEqual(matches.first?.endDate, now.addingTimeInterval(100))
    }

    func testNaturalTaskComposer() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10))!
        let parser = NaturalTaskParser()
        func stamp(_ date: Date) -> String {
            let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
        let cases: [(String, TaskComposerMode, String, String, String, Bool)] = [
            ("明天下午三點到四點和鼎達叔叔開會", .event, "和鼎達叔叔開會", "2026-10-20 15:00", "2026-10-20 16:00", false),
            ("明天下午三点到四点和鼎达叔叔开会", .event, "和鼎达叔叔开会", "2026-10-20 15:00", "2026-10-20 16:00", false),
            ("下下週一下午三點開會", .event, "開會", "2026-11-02 15:00", "2026-11-02 16:00", false),
            ("下下周一下午三点开会", .event, "开会", "2026-11-02 15:00", "2026-11-02 16:00", false),
            ("下週五上午10點開會30分鐘", .event, "開會", "2026-10-30 10:00", "2026-10-30 10:30", false),
            ("下週日上午十點去教會", .event, "去教會", "2026-11-01 10:00", "2026-11-01 11:00", false),
            ("明天開會", .event, "開會", "2026-10-20 00:00", "2026-10-21 00:00", true),
            ("30分鐘後喝水", .reminder, "喝水", "2026-10-19 10:30", "2026-10-19 11:30", false),
            ("半小時後喝水", .reminder, "喝水", "2026-10-19 10:30", "2026-10-19 11:30", false),
            ("明天交報告", .reminder, "交報告", "2026-10-20 00:00", "2026-10-21 00:00", true),
            ("提醒我明天上午9點交報告", .reminder, "交報告", "2026-10-20 09:00", "2026-10-20 10:00", false),
            ("明天23:00到後天01:00值班", .event, "值班", "2026-10-20 23:00", "2026-10-21 01:00", false),
            ("明天下午3點開會1小時30分鐘", .event, "開會", "2026-10-20 15:00", "2026-10-20 16:30", false),
            ("tomorrow at 3pm meeting for 30 minutes", .event, "meeting", "2026-10-20 15:00", "2026-10-20 15:30", false),
            ("tomorrow at 9am buy milk", .reminder, "buy milk", "2026-10-20 09:00", "2026-10-20 10:00", false),
            ("鼎達叔叔 明天下午3點 開會", .event, "鼎達叔叔 開會", "2026-10-20 15:00", "2026-10-20 16:00", false)
        ]
        for (input, mode, title, start, end, allDay) in cases {
            let draft = try await parser.parse(input, mode: mode, now: now, calendar: calendar)
            XCTAssertEqual(draft.title, title); XCTAssertEqual(stamp(draft.start), start); XCTAssertEqual(stamp(draft.end), end)
            XCTAssertEqual(draft.isAllDay, allDay); XCTAssertEqual(draft.kind, mode.kind)
            XCTAssertNil(draft.validationError(at: now, calendar: calendar))
            XCTAssertNil(draft.plan.relativeDelay)
        }
        let lead = try await parser.parse("明天下午3點開會提前10分鐘提醒", mode: .event, now: now, calendar: calendar)
        XCTAssertEqual(lead.alarmOffset, -600); XCTAssertEqual(lead.title, "開會")
        let compoundLead = try await parser.parse("明天下午3點開會提前1小時30分鐘提醒", mode: .event, now: now, calendar: calendar)
        XCTAssertEqual(compoundLead.alarmOffset, -5400); XCTAssertEqual(compoundLead.title, "開會")
        let relative = try await parser.parse("30分鐘後喝水", mode: .reminder, now: now, calendar: calendar)
        XCTAssertEqual(relative.plan.resolved(at: now.addingTimeInterval(120)).start, relative.start)
        XCTAssertNotNil(relative.validationError(at: now.addingTimeInterval(1900), calendar: calendar))
        var invalid = lead; invalid.title = " "; XCTAssertNotNil(invalid.validationError(at: now, calendar: calendar))
        invalid = lead; invalid.end = invalid.start; XCTAssertNotNil(invalid.validationError(at: now, calendar: calendar))
        for input in ["", "開會", "明天下午開會", "每週一上午九點開會", "每個星期一上午9點開會", "每兩週一下午3點開會", "明天下午3點", "昨天上午9點交報告", "明天下午3點開會200小時", "明天上午9點開會 後天上午10點吃飯", "明天25:99開會", String(repeating: "字", count: 201)] {
            do { _ = try await parser.parse(input, mode: .event, now: now, calendar: calendar); preconditionFailure("Should reject: \(input)") }
            catch is NaturalTaskFailure { }
        }
        do { _ = try await parser.parse("明天下午3點到4點喝水", mode: .reminder, now: now, calendar: calendar); preconditionFailure("A reminder must not silently lose its time range") }
        catch is NaturalTaskFailure { }
        for command in ["cal", "CAL", "calendar", "行事曆", "行事历", "行程"] { XCTAssertEqual(TaskComposerMode.command(command), .event) }
        for command in ["提醒", "提醒事項", "提醒事项", "rem", "reminder"] { XCTAssertEqual(TaskComposerMode.command(command), .reminder) }
        for command in ["calendar app", "cal tomorrow", "提醒我", "cal.js"] { XCTAssertNil(TaskComposerMode.command(command)) }
    }

    func testSystemSettingsSearch() {
        let examples: [(String, String)] = [
            ("隱私與安全性", "com.apple.settings.PrivacySecurity.extension"),
            ("隐私安全性", "com.apple.settings.PrivacySecurity.extension"),
            ("隐私安全", "com.apple.settings.PrivacySecurity.extension"),
            ("Privacy & Security", "com.apple.settings.PrivacySecurity.extension"),
            ("wifi", "com.apple.wifi-settings-extension"), ("Wi‑Fi", "com.apple.wifi-settings-extension"),
            ("無線網絡", "com.apple.wifi-settings-extension"), ("開啟WiFi設定", "com.apple.wifi-settings-extension"),
            ("藍牙", "com.apple.BluetoothSettings"), ("蓝牙", "com.apple.BluetoothSettings"),
            ("Bluetooth", "com.apple.BluetoothSettings"), ("bt", "com.apple.BluetoothSettings"),
            ("System settings keyboard", "com.apple.Keyboard-Settings.extension"),
            ("存储空间", "com.apple.settings.Storage"), ("登入項目", "com.apple.LoginItems-Settings.extension")
        ]
        for (query, identifier) in examples {
            let result = SystemSettingsCatalog.results(query: query).first
            XCTAssertEqual(result?.id, "quick:system-settings:" + identifier)
            if case .open(let url) = result?.action { XCTAssertEqual(url.absoluteString, "x-apple.systempreferences:" + identifier) }
            else { preconditionFailure("Settings must open a fixed pane URL") }
        }
        XCTAssertEqual(QuickProvider.results(query: "WiFi").first?.id, "quick:system-settings:com.apple.wifi-settings-extension")
        XCTAssertEqual(SystemSettingsCatalog.results(query: "系統設定").first?.id, "quick:settings")
        for query in ["", "a", "my-private-video.mp4", "wifi unknownword", "wifi?injected=true", "3000tb rmb"] {
            XCTAssertTrue(SystemSettingsCatalog.results(query: query).isEmpty)
        }
    }

    func testSystemShortcutPreferences() {
        let commandSpace: [String: Any] = ["enabled": true, "value": ["parameters": [32, 49, 1048576]]]
        let binding = SystemShortcutPreference.enabledBinding(commandSpace)
        XCTAssertNotNil(binding)
        XCTAssertTrue(SystemShortcutPreference.sameKeys(binding!, .commandSpace))
        XCTAssertNil(SystemShortcutPreference.enabledBinding(["enabled": false, "value": ["parameters": [32, 49, 1048576]]]))
        XCTAssertNil(SystemShortcutPreference.enabledBinding(["enabled": true, "value": ["parameters": [32, 49]]]))
        XCTAssertNil(SystemShortcutPreference.enabledBinding(["enabled": true, "value": ["parameters": [32, -1, 1048576]]]))
        let changed: [String: Any] = ["enabled": true, "value": ["parameters": [32, 49, 786432]]]
        XCTAssertTrue(SystemShortcutPreference.sameKeys(SystemShortcutPreference.enabledBinding(changed)!, .standard))
        XCTAssertFalse(SystemShortcutPreference.sameKeys(binding!, .standard))
        XCTAssertEqual(SearchMode.shortcuts.rawValue, "捷徑")
    }

    func testSourceConnectionQueue() {
        var queue = SourceConnectionQueue()
        XCTAssertTrue(queue.enqueue(.notes, allowPrompt: false))
        XCTAssertTrue(queue.enqueue(.contacts, allowPrompt: false))
        XCTAssertFalse(queue.enqueue(.contacts, allowPrompt: true))
        XCTAssertEqual(queue.next()?.source, .notes)
        XCTAssertNil(queue.next())
        XCTAssertFalse(queue.enqueue(.notes, allowPrompt: true))
        queue.finish()
        let contacts = queue.next()
        XCTAssertEqual(contacts?.source, .contacts)
        XCTAssertEqual(contacts?.allowPrompt, true)
        queue.enqueue(.reminders, allowPrompt: true)
        XCTAssertEqual(queue.discardPending().map(\.source), [.reminders])
        XCTAssertEqual(queue.active?.source, .contacts)
        XCTAssertNil(queue.next())
        queue.enqueue(.reminders, allowPrompt: true)
        queue.cancelAll()
        XCTAssertNil(queue.active); XCTAssertTrue(queue.pending.isEmpty); XCTAssertNil(queue.next())
        queue.enqueue(.calendar, allowPrompt: true)
        XCTAssertEqual(queue.next()?.source, .calendar)
    }

    @MainActor func testBoundedSystemCallbacks() async throws {
        let result: Int = try await TimedCallback.wait(timeout: 1) { reply in
            reply(.success(7)); reply(.success(9))
        }
        XCTAssertEqual(result, 7)
        for _ in 0..<25 {
            do {
                let _: Int = try await TimedCallback.wait(timeout: 0) { reply in reply(.success(99)) }
                preconditionFailure("An expired deadline must reject a reply even before the watchdog runs")
            } catch CallbackFailure.timedOut { }
        }
        let start = Date()
        do {
            let _: Int = try await TimedCallback.wait(timeout: 0.03) { reply in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) { reply(.success(99)) }
            }
            preconditionFailure("Missing callback should time out")
        } catch CallbackFailure.timedOut { }
        XCTAssertTrue(Date().timeIntervalSince(start) < 2)
        let pending = Task { @MainActor in
            try await TimedCallback.wait(timeout: 5) { (_: @escaping @Sendable (Result<Int, Error>) -> Void) in }
        }
        await Task.yield(); pending.cancel()
        do { _ = try await pending.value; preconditionFailure("Cancelled callback should stop") }
        catch is CancellationError { }
        // Allow the deliberately late callback to arrive and prove it cannot resume twice.
        try await Task.sleep(for: .milliseconds(100))
    }

    func testCancellableStreamingProcesses() throws {
        var lines: [String] = []
        let bytes = try ProcessRunner.run("/bin/sh", ["-c", "printf 'one\\ntwo\\nlast'"]) { lines.append(String(decoding: $0, as: UTF8.self)) }
        XCTAssertEqual(lines, ["one", "two", "last"])
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "one\ntwo\nlast")
        let start = Date()
        do {
            _ = try ProcessRunner.run("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 30"], timeout: 0.15)
            preconditionFailure("An unresponsive child should time out")
        } catch is ProcessFailure { }
        XCTAssertTrue(Date().timeIntervalSince(start) < 3)
        let cancellation = ProcessCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { cancellation.cancel() }
        do {
            _ = try ProcessRunner.run("/bin/sleep", ["30"], timeout: 10, cancellation: cancellation)
            preconditionFailure("Cancelled child should stop")
        } catch is CancellationError { }
        XCTAssertTrue(Date().timeIntervalSince(start) < 3)
    }

    func testAppAndFilenameAcrossScripts() {
        XCTAssertTrue(ChineseSearch.matches("红果短剧", query: "紅果短劇"))
        XCTAssertTrue(ChineseSearch.matches("教會活動紀錄.docx", query: "教会 活动"))
        XCTAssertTrue(ChineseSearch.matches("电脑課程.docx", query: "電腦課程"))
        XCTAssertFalse(ChineseSearch.matches("教會活動", query: "財務報表"))
        XCTAssertFalse(ChineseSearch.matches("任何文件", query: "  "))
    }

    func testNormalizationAvoidsOneSimplifiedToManyTraditionalMisses() {
        let document = IndexedDocument(url: URL(fileURLWithPath: "/fixture/紀錄.docx"), text: "新的發展計畫。\n她正在整理頭髮。")
        XCTAssertNotNil(document.match(query: "发展", mode: .contents))
        XCTAssertNotNil(document.match(query: "头发", mode: .contents))
        XCTAssertNotNil(document.match(query: "頭髮", mode: .contents))
        XCTAssertNil(document.match(query: "頭髮", mode: .names))
        XCTAssertEqual(document.match(query: "头发", mode: .contents)?.excerpt, "她正在整理頭髮。")
    }

    func testMetadataPredicateTreatsInputAsData() {
        let predicate = ChineseSearch.predicate("教會活動", mode: .contents)
        XCTAssertTrue(predicate.contains("教会活动"))
        XCTAssertTrue(predicate.contains("教會活動"))
        XCTAssertFalse(predicate.contains("kMDItemDisplayName"))
        XCTAssertEqual(ChineseSearch.escape("a\"b\\c*?"), "a\\\"b\\\\c\\*\\?")
    }

    func testMergeDeduplicatesAndKeepsPreview() {
        let url = URL(fileURLWithPath: "/fixture/教會活動.docx")
        let spotlight = SearchItem(url: url, source: "Spotlight")
        let local = SearchItem(url: url, source: "資料夾・內容", excerpt: "教会活动安排")
        let results = SearchService.merge([local, spotlight], query: "教會活動")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.excerpt, "教会活动安排")
    }

    func testRealDocxExtractionAndCrossScriptContent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let textURL = folder.appendingPathComponent("課程.txt")
        let docxURL = folder.appendingPathComponent("简体资料.docx")
        try "本周教会活动安排：电脑课程。".write(to: textURL, atomically: true, encoding: .utf8)
        _ = try ProcessRunner.run("/usr/bin/textutil", ["-convert", "docx", "-output", docxURL.path, textURL.path])
        try FileManager.default.removeItem(at: textURL)
        let indexed = SearchService.index(folder: folder)
        XCTAssertEqual(indexed.documents.count, 1)
        XCTAssertEqual(indexed.skippedText, 0)
        let hit = indexed.documents.first?.match(query: "教會活動", mode: .contents)
        XCTAssertEqual(hit?.url.resolvingSymlinksInPath(), docxURL.resolvingSymlinksInPath())
        XCTAssertTrue(hit?.excerpt.contains("教会活动") == true)
        XCTAssertNotNil(indexed.documents.first?.match(query: "簡體資料", mode: .names))
        XCTAssertNotNil(indexed.documents.first?.match(query: "電腦課程", mode: .contents))
    }

    func testRealSpotlightQueryDoesNotError() throws {
        // An empty index is valid; this asserts only that macOS accepts the generated grammar.
        _ = try ProcessRunner.run("/usr/bin/mdfind", ["-0", ChineseSearch.predicate("教會活動", mode: .all)])
    }

    func testCalculator() throws {
        for (text, expected) in [("2+3*4", 14.0), ("(1200+300)*0.9", 1350), ("200*10%", 20), ("2^3^2", 512), ("-2^2", -4), ("2^-2", 0.25), ("√144", 12), ("sqrt(16)+abs(-3)", 7), ("1e3/4", 250), ("=0.1+0.2", 0.3)] {
            XCTAssertTrue(abs(try Calculator.evaluate(text) - expected) < 1e-9)
        }
        for invalid in ["1/0", "sqrt(-1)", "2+", "FUNCTION('x')", String(repeating: "(", count: 60) + "1" + String(repeating: ")", count: 60)] {
            do { _ = try Calculator.evaluate(invalid); preconditionFailure("Accepted invalid expression") } catch {}
        }
        XCTAssertEqual(Calculator.format(0.1+0.2), "0.3")
    }

    func testConversions() {
        XCTAssertEqual(UnitConverter.convert("5 km to m"), "5000 m")
        XCTAssertEqual(UnitConverter.convert("32°F in Celsius"), "0 Celsius")
        XCTAssertEqual(UnitConverter.convert("2 h to min"), "120 min")
        XCTAssertEqual(UnitConverter.convert("1 GiB to MiB"), "1024 MiB")
        XCTAssertNil(UnitConverter.convert("1 kg to km"))
        XCTAssertNil(UnitConverter.convert("200 USD to TWD"))
    }

    func testIndependentFilenameCatalog() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["主日讲道.mp4", "主日講道.docx", "redacted.txt"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let catalog = FileCatalog.scan(roots: [folder])
        XCTAssertEqual(catalog.entries.count, 3)
        let hits = FileCatalog.search(catalog.entries, query: "主日講道", mode: .videos)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.name, "主日讲道.mp4")
        let cache = folder.appendingPathComponent("cache.json")
        try FileCatalog.save(catalog, to: cache)
        XCTAssertEqual(FileCatalog.load(from: cache)?.entries.count, 3)
        let dependencies = folder.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: dependencies, withIntermediateDirectories: true)
        try Data().write(to: dependencies.appendingPathComponent("dependency.mp4"))
        XCTAssertFalse(FileCatalog.scan(roots: [folder]).entries.contains { $0.name == "dependency.mp4" })
        // Search still uses the catalog without invoking Spotlight or reading file bodies.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("主日讲道.mp4"))
        XCTAssertEqual(FileCatalog.search(catalog.entries, query: "主日講道", mode: .videos).count, 1)
        XCTAssertTrue(FileCatalog.scan(roots: [folder]).entries.allSatisfy { $0.name != "主日讲道.mp4" })
    }

    func testPersonalRecordCrossScriptMatching() {
        let record = PersonalRecord(id: "fixture", title: "周报", subtitle: "備忘錄", text: "本周教会活动", symbol: "note.text", mode: .notes, action: .note("fixture-id"))
        XCTAssertNotNil(record.result(query: "教會活動", mode: .notes))
        XCTAssertNil(record.result(query: "教會活動", mode: .mail))
    }

    func testSafeQuickActions() {
        XCTAssertEqual(QuickProvider.results(query: "120*1.08").first?.title, "129.6")
        XCTAssertEqual(QuickProvider.results(query: "(1200+300)*0.9").count, 1)
        XCTAssertEqual(QuickProvider.results(query: "github.com").count, 1)
        XCTAssertTrue(QuickProvider.results(query: "report.docx").isEmpty)
        XCTAssertFalse(Calculator.looksLikeExpression("2026-10-19"))
        XCTAssertTrue(QuickProvider.results(query: "javascript:alert(1)").isEmpty)
        if case .open(let url) = QuickProvider.webSearch(query: "a&b #中文")?.action {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.queryItems?.first?.value, "a&b #中文")
        } else { preconditionFailure("Missing web action") }
    }
    func testTaskCommands() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8, minute: 0))!
        let alarm = TaskCommandParser.parse("設定30分鐘後的鬧鐘", now: now, calendar: calendar)!
        XCTAssertEqual(alarm.kind, .alarm)
        XCTAssertEqual(alarm.start.timeIntervalSince(now), 1800)
        XCTAssertEqual(alarm.resolved(at: now.addingTimeInterval(60)).start.timeIntervalSince(now), 1860)
        XCTAssertEqual(TaskCommandParser.parse("設定半小時後的鬧鐘", now: now, calendar: calendar)?.relativeDelay, 1800)
        XCTAssertNil(TaskCommandParser.parse("倒數半小時", now: now, calendar: calendar))
        let reminder = TaskCommandParser.parse("提醒我10分鐘後喝水", now: now, calendar: calendar)!
        XCTAssertEqual(reminder.kind, .reminder); XCTAssertEqual(reminder.title, "喝水")
        let event = TaskCommandParser.parse("明天下午3點開會30分鐘", now: now, calendar: calendar)!
        XCTAssertEqual(event.kind, .event); XCTAssertEqual(event.title, "開會"); XCTAssertEqual(event.duration, 1800)
        XCTAssertEqual(calendar.component(.day, from: event.start), 20)
        XCTAssertEqual(calendar.component(.hour, from: event.start), 15)
        let tomorrow = TaskCommandParser.parse("提醒我明天上午9點交報告", now: now, calendar: calendar)!
        XCTAssertEqual(tomorrow.kind, .reminder); XCTAssertEqual(tomorrow.title, "交報告")
        for invalid in ["2027-2-30下午3點開會", "今天上午7點的鬧鐘", "明天25:00開會", "設定0分鐘後的鬧鐘", "設定1小時30分鐘後的鬧鐘"] {
            XCTAssertNil(TaskCommandParser.parse(invalid, now: now, calendar: calendar))
        }
        let rounded = try ClockAlarmRequest.date(for: TaskPlan(kind: .alarm, title: "test", start: now.addingTimeInterval(1801)), now: now, calendar: calendar)
        XCTAssertEqual(rounded.timeIntervalSince(now), 1860)
        let afterMidnight = TaskPlan(kind: .alarm, title: "test", start: now.addingTimeInterval(18 * 3600))
        XCTAssertEqual(try ClockAlarmRequest.date(for: afterMidnight, now: now, calendar: calendar), afterMidnight.start)
        do {
            _ = try ClockAlarmRequest.date(for: TaskPlan(kind: .alarm, title: "test", start: now.addingTimeInterval(25 * 3600)), now: now, calendar: calendar)
            preconditionFailure("Clock cannot schedule a dated alarm beyond the next occurrence")
        } catch {}
    }

    func testCurrencyCountryNames() {
        for name in ["马来西亚", "馬來西亞", "马来", "馬來", "大马", "Malaysia", "mAlAySiA", "Malay", "Msia", "MY", "令吉", "Malaysian Ringgit"] {
            for query in ["3000Nt = " + name, "3000nt " + name] {
                let parsed = CurrencyQuery.parse(query)
                XCTAssertEqual(parsed?.source, "TWD"); XCTAssertEqual(parsed?.target, "MYR"); XCTAssertEqual(parsed?.amount, 3000)
            }
        }
        let examples = [("New Zealand", "NZD"), ("紐西蘭", "NZD"), ("新西兰", "NZD"), ("United States", "USD"), ("United States of America", "USD"), ("美国", "USD"), ("United Kingdom", "GBP"), ("英國", "GBP"), ("South Korea", "KRW"), ("韓國", "KRW"), ("南韓", "KRW"), ("日本", "JPY"), ("Japan", "JPY"), ("新加坡", "SGD"), ("Singapore", "SGD"), ("法國", "EUR"), ("Germany", "EUR")]
        for (country, code) in examples { XCTAssertEqual(CurrencyQuery.parse("3000 NT = " + country)?.target, code) }
        XCTAssertEqual(CurrencyQuery.parse("Malaysia 100 = 台灣")?.source, "MYR")
        XCTAssertEqual(CurrencyQuery.parse("100 United States to Malaysia")?.source, "USD")
        XCTAssertEqual(CurrencyQuery.requests("3000NT = 馬來, New Zealand, United States", defaultTargets: []).map(\.target), ["MYR", "NZD", "USD"])
        XCTAssertEqual(CurrencyQuery.requests("3000NT Malaysia New Zealand South Korea", defaultTargets: []).map(\.target), ["MYR", "NZD", "KRW"])
        XCTAssertEqual(CurrencyQuery.requests("3000NT = 馬來/Malaysia/MYR/日本", defaultTargets: []).map(\.target), ["MYR", "JPY"])
        XCTAssertEqual(CurrencyQuery.cleanTargets(["馬來", "Malaysia", "New  Zealand", "美國"]), ["MYR", "NZD", "USD"])
        let conversion = CurrencyQuery.parse("3000Nt=馬來")?.converted(using: ["TWD": 30, "MYR": 4.5])
        XCTAssertEqual(conversion?.amount, 450) // Deliberately synthetic rates, not live market data.
        for invalid in ["3000NT = Malaysia unknown", "3000NT = New", "3000NT = South", "3000NT = 歐盟", "3000NT = Europe", "3000NT = United States nonsense", "1 TB to GB"] {
            XCTAssertTrue(CurrencyQuery.requests(invalid, defaultTargets: ["CNY"]).isEmpty)
        }
    }

    func testSearchHighlights() {
        func highlighted(_ text: String, _ query: String) -> [String] {
            SearchHighlight.ranges(in: text, query: query).map { range in
                guard let source = Range(range, in: text) else { preconditionFailure("Invalid original Unicode range") }
                return String(text[source])
            }
        }
        XCTAssertEqual(highlighted("🎬鼎達叔叔來了，鼎达叔叔也來了", "鼎达叔叔"), ["鼎達叔叔", "鼎达叔叔"])
        XCTAssertEqual(highlighted("鼎達叔叔", "鼎达 叔叔"), ["鼎達叔叔"])
        XCTAssertEqual(highlighted("叔叔叔", "叔叔"), ["叔叔叔"])
        XCTAssertEqual(highlighted("Hello，HELLO", "hello"), ["Hello", "HELLO"])
        XCTAssertEqual(highlighted("Ｈｅｌｌｏ", "hello"), ["Ｈｅｌｌｏ"])
        XCTAssertEqual(highlighted("Cafe\u{301} ﬃ 乾坤乾杯", "café ffi 乾坤干杯"), ["Cafe\u{301}", "ﬃ", "乾坤乾杯"])
        XCTAssertEqual(highlighted("檔案[1]*.txt", "[1]*"), ["[1]*"])
        XCTAssertTrue(SearchHighlight.ranges(in: "不相符", query: "鼎達叔叔").isEmpty)
        XCTAssertTrue(SearchHighlight.ranges(in: "鼎達叔叔", query: "  ").isEmpty)
        let body = String(repeating: "沒有命中的前言", count: 100) + "鼎達叔叔帶來內容" + String(repeating: "後文", count: 100)
        let snippet = SearchHighlight.excerpt(in: body, query: "鼎达叔叔")
        XCTAssertTrue(snippet.contains("鼎達叔叔")); XCTAssertTrue(snippet.hasPrefix("…")); XCTAssertTrue(snippet.count <= 162)
        XCTAssertEqual(highlighted(snippet, "鼎达叔叔"), ["鼎達叔叔"])
        let longNeedle = String(repeating: "鼎", count: 170) + "達"
        XCTAssertTrue(SearchHighlight.excerpt(in: String(repeating: "前", count: 100) + longNeedle + "後文", query: longNeedle).contains(longNeedle))
        let document = IndexedDocument(url: URL(fileURLWithPath: "/test/highlight.docx"), text: body)
        XCTAssertTrue(document.match(query: "鼎达叔叔", mode: .contents)?.excerpt.contains("鼎達叔叔") == true)
        let note = PersonalRecord(id: "note:highlight-test", title: "測試筆記", subtitle: "開頭摘要", text: body, symbol: "note.text", mode: .notes, action: .note("highlight-test"))
        XCTAssertTrue(note.result(query: "鼎达叔叔", mode: .all)?.subtitle.contains("鼎達叔叔") == true)
    }

    func testCurrencyQueries() {
        let examples = ["3000台幣=rmb", "nt3000 = rmb", "3000nt = rmb", "NT$3,000 = 人民币", "3000新臺幣換成RMB", "3,000 TWD to CNY", "3000tb=rmb", "3000tb rmb", "3000 tb RMB"]
        let rates = ["USD": 1.0, "TWD": 30.0, "CNY": 6.9]
        for text in examples {
            guard let query = CurrencyQuery.parse(text) else { preconditionFailure("Currency parser rejected \(text)") }
            XCTAssertEqual(query.amount, 3000); XCTAssertEqual(query.source, "TWD"); XCTAssertEqual(query.target, "CNY")
            XCTAssertTrue(abs(query.converted(using: rates)!.amount - 690) < 1e-9)
        }
        XCTAssertEqual(CurrencyQuery.parse("RMB100=NT")?.target, "TWD")
        let defaults = CurrencyQuery.requests("3000tb", defaultTargets: ["CNY", "USD", "JPY"])
        XCTAssertEqual(defaults.map(\.target), ["CNY", "USD", "JPY"])
        XCTAssertTrue(defaults.allSatisfy { $0.source == "TWD" && $0.amount == 3000 })
        XCTAssertEqual(CurrencyQuery.requests("3000台幣", defaultTargets: ["JPY", "USD"]).map(\.target), ["JPY", "USD"])
        XCTAssertEqual(CurrencyQuery.requests("3000tb=rmb,usd,jpy", defaultTargets: ["EUR"]).map(\.target), ["CNY", "USD", "JPY"])
        XCTAssertEqual(CurrencyQuery.requests("3000tb rmb usd", defaultTargets: ["EUR"]).map(\.target), ["CNY", "USD"])
        XCTAssertEqual(CurrencyQuery.requests("3000tb=rmb,cny", defaultTargets: []).map(\.target), ["CNY"])
        XCTAssertEqual(CurrencyQuery.requests("3000tb rmb", defaultTargets: ["EUR"]).map(\.target), ["CNY"])
        XCTAssertEqual(CurrencyQuery.cleanTargets(["rmb", "CNY", "not-currency", "usd"]), ["CNY", "USD"])
        XCTAssertTrue(CurrencyQuery.isCurrencyQuery("3000tb"))
        XCTAssertTrue(CurrencyQuery.requests("1 TB to GB", defaultTargets: ["CNY"]).isEmpty)
        XCTAssertTrue(CurrencyQuery.requests("3000tb = RMB nonsense", defaultTargets: ["CNY"]).isEmpty)
        XCTAssertEqual(CurrencyQuery.money(690, code: "CNY"), "CNY 690.00")
        for invalid in ["nt3000nt=rmb", "3000nt=1rmb", "3000nt=rmb extra", "report3000nt=rmb", "1,2nt=rmb", "3000nt", "nanTWD=CNY", "100 XYZ to CNY", "1e1000TWD=CNY"] {
            XCTAssertNil(CurrencyQuery.parse(invalid))
        }
        XCTAssertNil(CurrencyQuery.parse("3000nt=rmb")?.converted(using: ["TWD": 0, "CNY": 1]))
        XCTAssertNil(CurrencyQuery.parse("3000nt=rmb")?.converted(using: ["TWD": 30]))
    }
    func testShortcutBindings() throws {
        XCTAssertTrue(ShortcutBinding.standard.isValid)
        XCTAssertTrue(ShortcutBinding.commandSpace.isValid)
        XCTAssertEqual(ShortcutBinding.standard.display, "⌃⌥Space")
        XCTAssertEqual(ShortcutBinding.commandSpace.display, "⌘Space")
        XCTAssertFalse(ShortcutBinding(keyCode: 49, modifiers: 0, keyLabel: "Space").isValid)
        XCTAssertFalse(ShortcutBinding(keyCode: 49, modifiers: 512, keyLabel: "Space").isValid)
        XCTAssertFalse(ShortcutBinding(keyCode: 500, modifiers: 256, keyLabel: "bad").isValid)
        let binding = ShortcutBinding(keyCode: 40, modifiers: 256 | 512, keyLabel: "K")
        XCTAssertEqual(try JSONDecoder().decode(ShortcutBinding.self, from: JSONEncoder().encode(binding)), binding)
    }

    func testLauncherVisibilityAfterSwitchingApps() {
        var state = LauncherPresentation()
        XCTAssertEqual(state.toggle(applicationActive: false, windowVisible: false), .show)
        XCTAssertEqual(state.toggle(applicationActive: true, windowVisible: true), .hide)
        XCTAssertEqual(state.toggle(applicationActive: true, windowVisible: false), .show)
        // Regression: AppKit can report the old panel as visible after switching to a different app.
        XCTAssertEqual(state.toggle(applicationActive: false, windowVisible: true), .show)
        XCTAssertEqual(state.toggle(applicationActive: true, windowVisible: true), .hide)
        state.show(); state.hide() // Explicit deactivation resets presentation before the next hotkey.
        XCTAssertEqual(state.toggle(applicationActive: false, windowVisible: true), .show)
    }

}
