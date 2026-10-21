import Foundation
import CoreGraphics
import IOKit.ps

/// Only reads power/thermal state and elapsed idle time; never captures input events.
public struct OCRResourceState: Sendable {
    public enum Power: Sendable { case external, battery, unknown }
    public var power: Power
    public var batteryPercent: Int?
    public var idleSeconds: TimeInterval
    public var lowPower: Bool
    public var thermalElevated: Bool
    public init(power: Power, batteryPercent: Int? = nil, idleSeconds: TimeInterval = 0, lowPower: Bool = false, thermalElevated: Bool = false) {
        self.power = power; self.batteryPercent = batteryPercent; self.idleSeconds = idleSeconds
        self.lowPower = lowPower; self.thermalElevated = thermalElevated
    }
    public static func current() -> Self {
        var power: Power = .unknown, battery: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
                if source == kIOPSACPowerValue { power = .external }
                else if source == kIOPSBatteryPowerValue { power = .battery }
            }
            if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
                for source in sources {
                    guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                          description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                          let current = description[kIOPSCurrentCapacityKey] as? Int,
                          let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                    battery = max(0, min(100, Int(Double(current) / Double(maximum) * 100)))
                }
            }
        }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        return Self(power: power, batteryPercent: battery, idleSeconds: idle,
                    lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    thermalElevated: ProcessInfo.processInfo.thermalState != .nominal)
    }
}

public enum OCRWorkDecision: Equatable, Sendable {
    case waitingForPower, unknownPower, lowBattery, lowPower, cooling, waitingForIdle
    case active, idle, batteryIdle
    public var canRun: Bool { interval != nil }
    public var interval: TimeInterval? {
        switch self { case .active: return 3; case .idle: return 0.1; case .batteryIdle: return 6; default: return nil }
    }
    public var title: String {
        switch self {
        case .waitingForPower: return "節能等待：接上電源後自動繼續"
        case .unknownPower: return "節能等待：暫時無法確認電源狀態"
        case .lowBattery: return "節能等待：電量低於或等於 30%，或無法確認電量"
        case .lowPower: return "節能等待：系統已開啟低耗電模式"
        case .cooling: return "節能等待：機身溫度升高"
        case .waitingForIdle: return "節能等待：閒置 90 秒後自動繼續"
        case .active: return "接電使用中：降低 OCR 處理頻率"
        case .idle: return "接電且閒置：加快背景 OCR"
        case .batteryIdle: return "電池且閒置：低速背景 OCR"
        }
    }
    public static func evaluate(_ state: OCRResourceState, allowBattery: Bool = false, idleOnly: Bool = false) -> Self {
        if state.lowPower { return .lowPower }
        if state.thermalElevated { return .cooling }
        switch state.power {
        case .unknown: return .unknownPower
        case .battery:
            guard allowBattery else { return .waitingForPower }
            guard let percent = state.batteryPercent, percent > 30 else { return .lowBattery }
            return state.idleSeconds >= 90 ? .batteryIdle : .waitingForIdle
        case .external:
            if state.idleSeconds >= 90 { return .idle }
            return idleOnly ? .waitingForIdle : .active
        }
    }
}

/// One serial worker calls this at page boundaries. Long waits exit the indexer so no
/// write lock or worker is kept alive waiting for a charger. No power/sleep assertions.
public final class OCRWorkScheduler: @unchecked Sendable {
    private let decision: @Sendable () -> OCRWorkDecision
    private var lastStart: TimeInterval?
    public init(decision: @escaping @Sendable () -> OCRWorkDecision) { self.decision = decision }
    public func prepare(cancellation: ProcessCancellation) throws {
        while true {
            guard !cancellation.isCancelled else { throw CancellationError() }
            let current = decision()
            guard let interval = current.interval else { throw DocumentReadReason.ocrDeferred }
            let now = ProcessInfo.processInfo.systemUptime
            if let lastStart, now - lastStart < interval {
                Thread.sleep(forTimeInterval: min(0.1, interval - (now - lastStart)))
            } else { lastStart = now; return }
        }
    }
}
