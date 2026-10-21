import Foundation
import HanSearchCore

/// Bridges UI preferences to the serial index worker without accessing actor-isolated state there.
final class OCRResourcePolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var allowBattery: Bool
    private var idleOnly: Bool
    private let state: @Sendable () -> OCRResourceState
    init(allowBattery: Bool, idleOnly: Bool, state: @escaping @Sendable () -> OCRResourceState) {
        self.allowBattery = allowBattery; self.idleOnly = idleOnly; self.state = state
    }
    func configure(allowBattery: Bool, idleOnly: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.allowBattery = allowBattery; self.idleOnly = idleOnly
    }
    func decision() -> OCRWorkDecision {
        lock.lock(); let battery = allowBattery, idle = idleOnly; lock.unlock()
        return .evaluate(state(), allowBattery: battery, idleOnly: idle)
    }
}
