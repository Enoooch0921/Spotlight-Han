import Foundation

/// Every startup refresh, individual connection and setup batch shares one queue.
public struct SourceConnectionQueue: Sendable {
    public struct Request: Sendable {
        public let source: SearchMode
        public var allowPrompt: Bool
    }
    public private(set) var pending: [Request] = []
    public private(set) var active: Request?
    public init() {}
    @discardableResult public mutating func enqueue(_ source: SearchMode, allowPrompt: Bool) -> Bool {
        guard active?.source != source else { return false }
        if let index = pending.firstIndex(where: { $0.source == source }) {
            pending[index].allowPrompt = pending[index].allowPrompt || allowPrompt
            return false
        }
        pending.append(Request(source: source, allowPrompt: allowPrompt)); return true
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
