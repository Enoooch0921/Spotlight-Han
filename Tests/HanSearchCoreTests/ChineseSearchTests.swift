import Foundation
import HanSearchCore

private func XCTAssertTrue(_ condition: Bool) { precondition(condition) }
private func XCTAssertFalse(_ condition: Bool) { precondition(!condition) }
private func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
private func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
private func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Expected \(rhs), received \(lhs)") }

@main
struct CheckRunner {
    static func main() throws {
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
        print("PASS: 11 check groups — Chinese matching, ambiguous characters, escaping, deduplication, real DOCX extraction, Spotlight grammar, calculator, unit conversion, independent filename cache, personal-record matching, safe URL actions.")
    }
}

final class ChineseSearchTests {
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
}
