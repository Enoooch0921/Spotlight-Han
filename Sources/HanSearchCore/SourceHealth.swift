import Foundation

public struct SourceHealth: Equatable, Sendable {
    public enum Phase: Sendable { case queued, authorizing, loading, ready, failed, incomplete, stopped, needsPermission }
    public var phase: Phase
    public var lastSuccess: Date?
    public var partialUpdate: Date?
    public var invalidated: Bool
    public var lastAttempt: Date?
    public init(phase: Phase = .queued, lastSuccess: Date? = nil, partialUpdate: Date? = nil, invalidated: Bool = false, lastAttempt: Date? = nil) {
        self.phase = phase; self.lastSuccess = lastSuccess; self.partialUpdate = partialUpdate; self.invalidated = invalidated
        self.lastAttempt = lastAttempt
    }
    public func isStale(at now: Date, maxAge: TimeInterval = 15 * 60) -> Bool {
        invalidated || (lastSuccess.map { now.timeIntervalSince($0) >= maxAge } ?? false)
    }
    public func needsAttention(at now: Date) -> Bool {
        switch phase {
        case .failed, .incomplete, .stopped, .needsPermission: return true
        case .ready: return isStale(at: now)
        default: return false
        }
    }
    public var hasSnapshot: Bool { lastSuccess != nil || partialUpdate != nil }
    public func shouldRefresh(at now: Date, interval: TimeInterval, force: Bool = false) -> Bool {
        if [.queued, .authorizing, .loading].contains(phase) { return false }
        if force && ![.failed, .incomplete, .stopped].contains(phase) { return true }
        let since = [lastAttempt, lastSuccess].compactMap { $0 }.max()
        // Failed, partial and stopped reads back off at least 15 minutes.
        let delay = [.failed, .incomplete, .stopped].contains(phase) ? max(interval, 900) : interval
        return since.map { now.timeIntervalSince($0) >= delay } ?? true
    }
    public mutating func succeeded(at date: Date) { phase = .ready; lastSuccess = date; lastAttempt = date; partialUpdate = nil; invalidated = false }
}
