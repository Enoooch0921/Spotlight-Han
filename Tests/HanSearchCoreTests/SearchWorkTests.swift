import Foundation
import HanSearchCore

extension ChineseSearchTests {
    func testSearchWorkBoundaries() async throws {
        for (input, expected) in [("DL32", "dl32"), (" DL - 32 ", "dl32"), ("DL32 ", "dl32"), ("X32-RACK", "x32rack"), ("a1_b2.c3", "a1b2c3")] {
            precondition(ModelSearch.key(input) == expected)
        }
        for input in ["", "32", "Logic", "DL32 manual", "DL32-", "DL32 7", "DL三十二", "ＤＬ３２"] {
            precondition(ModelSearch.key(input) == nil)
        }
        // These near-misses used to trap ICU in exponential backtracking even
        // though the query was shorter than the existing 40-character limit.
        let hostile = "DL" + String(repeating: "1", count: 36) + ":"
        let start = Date()
        for _ in 0..<1000 { precondition(ModelSearch.key(hostile) == nil) }
        let keyElapsed = Date().timeIntervalSince(start)
        precondition(keyElapsed < 2, "Identifier validation must have bounded work")
        precondition(ModelSearch.key("D" + String(repeating: "1", count: 39)) != nil)
        precondition(ModelSearch.key("D" + String(repeating: "1", count: 40)) == nil)

        func record(_ id: String, _ text: String, mode: SearchMode = .notes, date: Date? = nil) -> PersonalRecord {
            PersonalRecord(id: id, title: "Fixture " + id, subtitle: "", text: text, symbol: "note", mode: mode, action: .details(id), startDate: date)
        }
        let original = record("direct", "列印說明"), alternative = record("related", "打印說明")
        let aliases = record("alias", "Unrelated")
        let inputs = Array(repeating: alternative, count: 60) + [original, aliases]
        let hits = try PersonalRecord.search(inputs, query: "列印", mode: .all, aliasTargets: ["quick:alias"], limit: 2)
        precondition(hits.map(\.id) == ["quick:direct", "quick:alias"], "Exact/alias matches must precede early supplementary matches")
        precondition(hits.allSatisfy { $0.supplement == nil })
        let related = try PersonalRecord.search([alternative], query: "列印", mode: .notes)
        precondition(related.first?.supplement != nil && related.first?.subtitle.contains("打印") == true)
        let contactHits = try PersonalRecord.search(inputs, query: "列印", mode: .contacts)
        precondition(contactHits.isEmpty)
        let modelHits = try PersonalRecord.search([record("model", "DL-32"), record("wrong", "DL320")], query: "dl32", mode: .all)
        precondition(modelHits.map(\.id) == ["quick:model"])
        let now = Date()
        let events = [record("later", "Meeting", mode: .calendar, date: now.addingTimeInterval(7200)), record("sooner", "Meeting", mode: .calendar, date: now.addingTimeInterval(3600))]
        let eventHits = try PersonalRecord.search(events, query: "Meeting", mode: .calendar)
        precondition(eventHits.map(\.id) == ["quick:sooner", "quick:later"])

        let cancelled = ProcessCancellation(); cancelled.cancel()
        do {
            _ = try PersonalRecord.search(inputs, query: hostile, mode: .all, cancellation: cancelled)
            preconditionFailure("A cancelled search must not start matching")
        } catch is CancellationError {}
        // Shared synthetic records make a deliberately long no-hit scan without
        // touching a user's Notes or retaining many copies of the body text.
        let large = Array(repeating: record("large", String(repeating: "a", count: 100_000)), count: 100_000)
        let worker = Task.detached { try PersonalRecord.search(large, query: "zzzz", mode: .notes) }
        try await Task.sleep(for: .milliseconds(30))
        let cancelledAt = Date()
        worker.cancel()
        do { _ = try await worker.value; preconditionFailure("Obsolete matching must stop") }
        catch is CancellationError {}
        let cancellationElapsed = Date().timeIntervalSince(cancelledAt)
        precondition(cancellationElapsed < 2, "Cancellation must stop work between records")
        let records = (0..<10_000).map { record(String($0), "Synthetic inventory text") }
        let batchStart = Date()
        let hostileHits = try PersonalRecord.search(records, query: hostile, mode: .all)
        precondition(hostileHits.isEmpty)
        print(String(format: "PASS: bounded identifier validation (1,000 near-misses %.2f ms), prepared personal search (10,000 records %.2f ms), cancellation %.2f ms, exact-first supplements, aliases, scope and calendar ordering", keyElapsed * 1000, Date().timeIntervalSince(batchStart) * 1000, cancellationElapsed * 1000))
    }
}
