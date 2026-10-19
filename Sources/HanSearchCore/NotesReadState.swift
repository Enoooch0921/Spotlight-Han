import Foundation

/// An in-memory scan uses stable Notes identifiers, so each short worker can resume
/// without depending on a changing list order or rereading the first few hundred notes.
public struct NotesReadState: Sendable {
    public let identifiers: [String]
    public let capped: Bool
    public private(set) var pending: [String]
    private var items: [String: PersonalRecord] = [:]
    private var locked = Set<String>()
    private var unreadable = Set<String>()
    private var truncated = Set<String>()
    private var timeouts: [String: Int] = [:]
    public private(set) var textCount = 0
    public init(identifiers: [String], capped: Bool = false) {
        var seen = Set<String>()
        self.identifiers = Array(identifiers.filter { seen.insert($0).inserted }.prefix(2000))
        self.pending = self.identifiers
        self.capped = capped || identifiers.count > 2000
    }
    public var total: Int { identifiers.count }
    public var processed: Int { total - pending.count }
    public var hasMore: Bool { !pending.isEmpty }
    public var records: [PersonalRecord] { identifiers.compactMap { items[$0] } }
    public var protectedCount: Int { locked.count }
    public var incompleteCount: Int { unreadable.union(truncated).count }
    public var complete: Bool { !hasMore && incompleteCount == 0 }
    public mutating func receive(id: String, title: String, text: String, isTruncated: Bool) {
        guard pending.contains(id) else { return }
        let body = isTruncated || text.count > 100000 || textCount + text.count > 16000000 ? "" : text
        if isTruncated || body.count != text.count { truncated.insert(id) }
        textCount += body.count
        items[id] = PersonalRecord(id: "note:" + id, title: title, subtitle: String(body.replacingOccurrences(of: "\n", with: " ").prefix(100)), text: body, symbol: "note.text", mode: .notes, action: .note(id))
        pending.removeAll { $0 == id }
    }
    public mutating func skip(id: String, protected: Bool) {
        guard pending.contains(id) else { return }
        if protected { locked.insert(id) } else { unreadable.insert(id) }
        pending.removeAll { $0 == id }
    }
    /// A single stuck note moves behind the rest, then stops retrying after two timeouts.
    /// Other notes can finish; the final status remains explicitly incomplete.
    public mutating func timedOut(id: String) {
        guard pending.contains(id) else { return }
        timeouts[id, default: 0] += 1
        if timeouts[id, default: 0] >= 2 { skip(id: id, protected: false) }
        else { pending.removeAll { $0 == id }; pending.append(id) }
    }
}
