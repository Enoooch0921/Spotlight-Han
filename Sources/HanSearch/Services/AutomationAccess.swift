import AppKit
import CoreServices
import HanSearchCore
import OSLog

/// Queries/request permissions from Han itself. No notes, messages, or other
/// application data is read to provoke a consent prompt.
enum AutomationAccess {
    enum State: Equatable, Sendable {
        case authorized, requiresConsent, denied, targetNotRunning, failed(OSStatus)
        init(code: OSStatus) {
            switch code {
            case noErr: self = .authorized
            case OSStatus(errAEEventWouldRequireUserConsent): self = .requiresConsent
            case OSStatus(errAEEventNotPermitted): self = .denied
            case OSStatus(procNotFound): self = .targetNotRunning
            default: self = .failed(code)
            }
        }
        var permissionStatus: EventAccessState.Status {
            self == .denied ? .denied : .notDetermined
        }
        func failure(source: String) -> Error {
            switch self {
            case .denied, .requiresConsent: return SourceAccessFailure(source: source, status: permissionStatus)
            case .targetNotRunning: return ProcessFailure.failed(L.format("無法連接%@，請先開啟該 App，再按「連接」。", source))
            case .failed(let code): return ProcessFailure.failed(L.format("無法確認%@的自動化授權（錯誤 %@）；請稍後重新連接。", source, String(code)))
            case .authorized: return ProcessFailure.failed(L.format("%@已授權，請重新讀取資料。", source))
            }
        }
    }
    static func bundleID(for source: SearchMode) -> String? {
        switch source { case .notes: return "com.apple.Notes"; case .mail: return "com.apple.mail"; default: return nil }
    }
    static func determine(bundleID: String, ask: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let code = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), ask)
        if ask { Logger(subsystem: "local.hansearch.mac", category: "automation").info("Consent request returned OSStatus \(code)") }
        return State(code: code)
    }
    static func state(_ source: SearchMode) -> State {
        guard let id = bundleID(for: source) else { return .failed(OSStatus(paramErr)) }
        return determine(bundleID: id, ask: false)
    }

    @MainActor static func authorize(_ source: SearchMode) async throws {
        guard let id = bundleID(for: source) else { return }
        try await authorize(source: source.rawValue, ensureRunning: { try await ensureRunning(bundleID: id, source: source.rawValue) },
                            probe: { determine(bundleID: id, ask: false) }, request: {
            // The system call may wait for a person's answer. Never block AppKit's
            // main thread, so Allow/Don't Allow remain clickable.
            try await TimedCallback.wait(timeout: 120) { reply in
                DispatchQueue.global(qos: .userInitiated).async {
                    reply(.success(determine(bundleID: id, ask: true)))
                }
            }
        })
    }
    /// Injectable sequencing for checks that never open personal apps or request consent.
    @MainActor static func authorize(source: String, ensureRunning: () async throws -> Void,
                                     probe: () -> State, request: () async throws -> State) async throws {
        try Task.checkCancellation()
        try await ensureRunning()
        try Task.checkCancellation()
        let initial = probe()
        if initial == .authorized { return }
        if initial == .denied { throw initial.failure(source: source) }
        guard initial == .requiresConsent else { throw initial.failure(source: source) }
        let result = try await request()
        try Task.checkCancellation()
        // The direct system result is evidence; do not replace a successful answer
        // with a second potentially stale probe.
        guard result == .authorized else { throw result.failure(source: source) }
    }
    @MainActor private static func ensureRunning(bundleID: String, source: String) async throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ProcessFailure.failed(L.format("找不到%@ App，請確認系統 App 仍可開啟。", source))
        }
        let config = NSWorkspace.OpenConfiguration(); config.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
