import Foundation

/// A request callback belongs to the store that received it. Some macOS installations
/// keep the class-level query at notDetermined after a successful callback. Preserve that
/// in-process evidence, but never override an explicit denial, restriction or downgrade.
public struct EventAccessState: Sendable {
    public enum Status: Int, Sendable { case notDetermined = 0, restricted, denied, fullAccess, writeOnly }
    private var callbackGranted = false
    private var observedFullAccess = false
    public init() {}
    public mutating func completed(granted: Bool) { callbackGranted = granted; if !granted { observedFullAccess = false } }
    public mutating func observe(_ status: Status?) -> Bool {
        switch status {
        case .fullAccess: observedFullAccess = true; return true
        case .notDetermined:
            if observedFullAccess { callbackGranted = false; observedFullAccess = false }
            return callbackGranted
        default: callbackGranted = false; observedFullAccess = false; return false
        }
    }
}

public struct SourceAccessFailure: Error, LocalizedError, Sendable {
    public let source: String
    public let status: EventAccessState.Status?
    public init(source: String, status: EventAccessState.Status? = nil) { self.source = source; self.status = status }
    public var errorDescription: String? {
        switch status {
        case .denied: return "\(source)存取已被拒絕，請到系統隱私權設定允許後重新連接。"
        case .restricted: return "\(source)存取受到系統限制，請檢查螢幕使用時間或裝置管理設定。"
        case .writeOnly: return "\(source)目前僅允許新增；搜尋需要完整存取，請到系統隱私權設定更改。"
        default: return "\(source)尚未完成授權，請按「連接」並完成系統提示。"
        }
    }
}
