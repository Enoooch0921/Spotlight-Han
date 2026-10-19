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
        // In All, keep the chosen calendar chronology within calendar result slots.
        let calendarIDs = candidates.filter { $0.kind == .calendar }.map(\.id)
        let calendarSet = Set(calendarIDs)
        var iterator = calendarIDs.makeIterator()
        ranked = ranked.map { calendarSet.contains($0) ? iterator.next()! : $0 }
        return fixed + ranked
    }
    func recordHabit(_ candidate: HabitCandidate?, query: String) {
        guard let candidate else { return }
        habits.record(query: query, identity: candidate.identity, kind: candidate.kind)
    }
}
