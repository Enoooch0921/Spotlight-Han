import Foundation
import HanSearchCore

extension SearchStore {
    func habitCandidate(_ item: SearchItem) -> HabitCandidate {
        let identity = item.isApplication ? "app:" + (item.applicationIdentifier ?? item.url.path) : "file:" + item.id
        return HabitCandidate(id: item.id, identity: identity, title: item.name, kind: item.isApplication ? .app : .file, aliases: (item.isApplication ? ApplicationAliases.aliases(name: item.name, bundleID: item.applicationIdentifier) : []) + aliases.aliases(for: identity))
    }
    func habitCandidate(_ item: QuickResult) -> HabitCandidate? {
        let kinds: [(String, SearchResultKind)] = [("note:", .note), ("contact:", .contact), ("event:", .calendar), ("reminder:", .reminder), ("mail:", .mail), ("shortcut:", .shortcut)]
        guard let kind = kinds.first(where: { item.id.hasPrefix("quick:" + $0.0) })?.1 else { return nil }
        return HabitCandidate(id: item.id, identity: item.id, title: item.title, kind: kind, aliases: aliases.aliases(for: item.id))
    }
    var orderedSearchIDs: [String] {
        let original = allQuickResults.map(\.id) + results.map(\.id)
        // Explicit calendar chronology and clipboard order remain authoritative.
        guard mode != .calendar && mode != .clipboard else { return original }
        let candidates = allQuickResults.compactMap { habitCandidate($0) } + results.map { habitCandidate($0) }
        let eligible = Set(candidates.map(\.id))
        let fixed = allQuickResults.filter { !eligible.contains($0.id) }.map(\.id)
        var ranked = habits.ordered(candidates, query: query)
        let model = ModelSearch.Query(query)
        if model.isIdentifier {
            var tiers: [String: Int] = [:]
            for item in results {
                let verified: Bool = { if case .match = documentPreviews[item.id] { return true }; return false }()
                tiers[item.id] = model.matches(item.name) ? 0 : (verified || model.matches(item.excerpt)) ? 1 : 2
            }
            for item in allQuickResults { tiers[item.id] = model.matches(item.title) ? 0 : model.matches(item.subtitle) ? 1 : 2 }
            ranked = ranked.enumerated().sorted { a, b in
                let left = tiers[a.element] ?? 2, right = tiers[b.element] ?? 2
                return left == right ? a.offset < b.offset : left < right
            }.map(\.element)
        }
        // In All, keep the chosen calendar chronology within calendar result slots.
        let calendarIDs = candidates.filter { $0.kind == .calendar }.map(\.id)
        let calendarSet = Set(calendarIDs)
        var iterator = calendarIDs.makeIterator()
        ranked = ranked.map { calendarSet.contains($0) ? iterator.next()! : $0 }
        let otherIndexed = Set(results.filter { isOtherIndexedResult($0) }.map(\.id))
        let confirmed = fileDateOrder(ranked.filter { !otherIndexed.contains($0) })
        ranked = confirmed + (showOtherIndexedResults ? fileDateOrder(ranked.filter { otherIndexed.contains($0) }) : [])
        return fixed + ranked
    }
    func recordHabit(_ candidate: HabitCandidate?, query: String) {
        guard let candidate else { return }
        habits.record(query: query, identity: candidate.identity, kind: candidate.kind)
    }
}
