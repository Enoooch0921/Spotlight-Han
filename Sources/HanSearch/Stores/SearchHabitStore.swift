import Foundation
import Combine
import HanSearchCore

@MainActor final class SearchHabitStore: ObservableObject {
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "searchHabits.enabled.v1") } }
    @Published private(set) var history: SearchHabitHistory
    @Published private(set) var saveFailed = false
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "searchHabits.enabled.v1") as? Bool ?? true
        history = defaults.data(forKey: "searchHabits.history.v1").flatMap { try? JSONDecoder().decode(SearchHabitHistory.self, from: $0) } ?? SearchHabitHistory()
        history.prune()
        if defaults.data(forKey: "searchHabits.history.v1") != nil { save() }
    }
    func record(query: String, identity: String, kind: SearchResultKind, now: Date = Date()) {
        guard enabled else { return }
        history.record(query: query, identity: identity, kind: kind, now: now)
        save()
    }
    func ordered(_ candidates: [HabitCandidate], query: String) -> [String] {
        enabled ? history.ordered(candidates, query: query) : candidates.map(\.id)
    }
    func clear() { history = SearchHabitHistory(); defaults.removeObject(forKey: "searchHabits.history.v1"); saveFailed = false }
    private func save() {
        do { let data = try JSONEncoder().encode(history); defaults.set(data, forKey: "searchHabits.history.v1"); saveFailed = false }
        catch { saveFailed = true }
    }
}
