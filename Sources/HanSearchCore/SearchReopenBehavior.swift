import Foundation

public enum SearchReopenBehavior: String, CaseIterable, Sendable {
    case timed, reset, keep
    public var title: String {
        switch self {
        case .timed: return "短時間內接續，逾時回到預設"
        case .reset: return "每次回到預設搜尋"
        case .keep: return "保留上次搜尋"
        }
    }
    public func shouldReset(lastDismissed: Date?, now: Date, retention: TimeInterval) -> Bool {
        switch self {
        case .reset: return true
        case .keep: return lastDismissed == nil
        case .timed:
            guard let lastDismissed else { return true }
            return now.timeIntervalSince(lastDismissed) >= max(0, retention)
        }
    }
}
