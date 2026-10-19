import Foundation

/// Consent, startup reads and scripting batches share one queue. Already-authorised
/// EventKit refreshes can run independently of this potentially slow scripting lane.
public struct SourceConnectionQueue: Sendable {
    public struct Request: Sendable {
        public let source: SearchMode
        public var allowPrompt: Bool
    }
    public private(set) var pending: [Request] = []
    public private(set) var active: Request?
    public init() {}
    @discardableResult public mutating func enqueue(_ source: SearchMode, allowPrompt: Bool, priority: Bool = false) -> Bool {
        guard active?.source != source else { return false }
        if let index = pending.firstIndex(where: { $0.source == source }) {
            pending[index].allowPrompt = pending[index].allowPrompt || allowPrompt
            if priority { pending.insert(pending.remove(at: index), at: 0) }
            return false
        }
        let request = Request(source: source, allowPrompt: allowPrompt)
        if priority { pending.insert(request, at: 0) } else { pending.append(request) }
        return true
    }
    public mutating func next() -> Request? {
        guard active == nil, !pending.isEmpty else { return nil }
        active = pending.removeFirst(); return active
    }
    public mutating func finish() { active = nil }
    @discardableResult public mutating func discardPending() -> [Request] {
        let discarded = pending; pending.removeAll(); return discarded
    }
    public mutating func cancelAll() { active = nil; pending.removeAll() }
}
