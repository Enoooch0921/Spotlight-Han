import Foundation

public enum CalendarResultSort: String, CaseIterable, Sendable {
    case upcoming, newest, oldest
    public var title: String {
        switch self { case .upcoming: return "即將到來優先"; case .newest: return "日期由新到舊"; case .oldest: return "日期由舊到新" }
    }
    public func precedes(start lhs: Date?, end lhsEnd: Date?, id lhsID: String, start rhs: Date?, end rhsEnd: Date?, id rhsID: String, now: Date) -> Bool {
        guard let lhs else { return rhs == nil && lhsID < rhsID }
        guard let rhs else { return true }
        if self == .upcoming {
            let futureL = (lhsEnd ?? lhs) >= now, futureR = (rhsEnd ?? rhs) >= now
            if futureL != futureR { return futureL }
            if lhs != rhs { return futureL ? lhs < rhs : lhs > rhs }
        } else if lhs != rhs { return self == .oldest ? lhs < rhs : lhs > rhs }
        return lhsID < rhsID
    }
    /// Sort only calendar slots, keeping other personal source categories in place.
    public func sorted(_ records: [PersonalRecord], now: Date = Date()) -> [PersonalRecord] {
        let events = records.filter { $0.mode == .calendar }.sorted {
            precedes(start: $0.startDate, end: $0.endDate, id: $0.id, start: $1.startDate, end: $1.endDate, id: $1.id, now: now)
        }
        var iterator = events.makeIterator()
        return records.map { $0.mode == .calendar ? iterator.next()! : $0 }
    }
}
