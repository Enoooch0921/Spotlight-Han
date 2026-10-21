import Foundation
import HanSearchCore

/// Bridges UI preferences and cached work metadata to the serial index worker.
final class OCRResourcePolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var allowBattery: Bool
    private var idleOnly: Bool
    private var protectWork: Bool
    private var protectAudio: Bool
    private let state: @Sendable () -> OCRResourceState
    private let activity: @Sendable () -> OCRWorkActivity
    init(allowBattery: Bool, idleOnly: Bool, protectWork: Bool = true, protectAudio: Bool = true,
         state: @escaping @Sendable () -> OCRResourceState,
         activity: @escaping @Sendable () -> OCRWorkActivity = { OCRWorkActivity() }) {
        self.allowBattery = allowBattery; self.idleOnly = idleOnly; self.protectWork = protectWork; self.protectAudio = protectAudio
        self.state = state; self.activity = activity
    }
    func configure(allowBattery: Bool, idleOnly: Bool, protectWork: Bool, protectAudio: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.allowBattery = allowBattery; self.idleOnly = idleOnly; self.protectWork = protectWork; self.protectAudio = protectAudio
    }
    var workActivity: OCRWorkActivity { activity() }
    func decision() -> OCRWorkDecision {
        lock.lock(); let battery = allowBattery, idle = idleOnly, work = protectWork, audio = protectAudio; lock.unlock()
        var current = state(); current.workActivity = activity()
        return .evaluate(current, allowBattery: battery, idleOnly: idle, protectWork: work, protectAudio: audio)
    }
}
