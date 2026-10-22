import Foundation
import CoreServices
import HanSearchCore

@main struct AutomationAccessChecks {
    @MainActor static func main() async throws {
        precondition(AutomationAccess.State(code: noErr) == .authorized)
        precondition(AutomationAccess.State(code: OSStatus(errAEEventWouldRequireUserConsent)) == .requiresConsent)
        precondition(AutomationAccess.State(code: OSStatus(errAEEventNotPermitted)) == .denied)
        precondition(AutomationAccess.State(code: OSStatus(procNotFound)) == .targetNotRunning)
        precondition(AutomationAccess.State(code: -50) == .failed(-50))
        precondition(AutomationAccess.bundleID(for: .notes) == "com.apple.Notes")
        precondition(AutomationAccess.bundleID(for: .mail) == "com.apple.mail")
        precondition(AutomationAccess.bundleID(for: .calendar) == nil)
        var order: [String] = []
        try await AutomationAccess.authorize(source: "Notes", ensureRunning: { order.append("launch") }, probe: {
            order.append("probe"); return .requiresConsent
        }, request: { order.append("request"); return .authorized })
        precondition(order == ["launch", "probe", "request"], "Launch before probing; accept direct success without a stale recheck")
        for state: AutomationAccess.State in [.authorized, .denied, .targetNotRunning, .failed(-50)] {
            order = []
            do {
                try await AutomationAccess.authorize(source: "Notes", ensureRunning: { order.append("launch") },
                    probe: { order.append("probe"); return state }, request: { preconditionFailure("No unnecessary consent request") })
                precondition(state == .authorized)
            } catch {
                precondition(state != .authorized)
                if state == .denied { precondition((error as? SourceAccessFailure)?.status == .denied) }
                else { precondition(!(error is SourceAccessFailure), "System errors must not pretend consent is missing") }
            }
            precondition(order == ["launch", "probe"])
        }
        for state: AutomationAccess.State in [.denied, .requiresConsent, .targetNotRunning, .failed(-50)] {
            do {
                try await AutomationAccess.authorize(source: "Notes", ensureRunning: {}, probe: { .requiresConsent }, request: { state })
                preconditionFailure("A failed request must not start data reads")
            } catch {
                if state == .denied { precondition((error as? SourceAccessFailure)?.status == .denied) }
                if state == .requiresConsent { precondition((error as? SourceAccessFailure)?.status == .notDetermined) }
            }
        }
        do {
            try await AutomationAccess.authorize(source: "Notes", ensureRunning: { throw CancellationError() },
                probe: { preconditionFailure("Do not probe after launch failure") }, request: { preconditionFailure() })
            preconditionFailure()
        } catch is CancellationError {} catch { preconditionFailure() }
        do {
            try await AutomationAccess.authorize(source: "Notes", ensureRunning: {}, probe: { .requiresConsent }, request: { throw CallbackFailure.timedOut })
            preconditionFailure()
        } catch is CallbackFailure {} catch { preconditionFailure() }
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await AutomationAccess.authorize(source: "Notes", ensureRunning: { preconditionFailure("Cancelled request must not launch apps") },
                probe: { preconditionFailure() }, request: { preconditionFailure() })
        }
        do { try await task.value; preconditionFailure() } catch is CancellationError {} catch { preconditionFailure() }
        print("PASS: automation status mapping, launch-before-consent, no redundant prompts, denial/system-error distinction, cancellation and timeout; injected callbacks only, no personal apps or permissions accessed")
    }
}
