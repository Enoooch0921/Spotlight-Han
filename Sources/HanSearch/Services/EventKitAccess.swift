import Foundation
import EventKit
import OSLog
import HanSearchCore

/// EventKit objects stay on the main actor. Requests, metadata, reads and writes use
/// the same long-lived store. Plain Sendable search records can be processed elsewhere.
@MainActor
enum EventKitAccess {
    static let store = EKEventStore()
    private static var events = EventAccessState()
    private static var reminders = EventAccessState()
    private static let log = Logger(subsystem: "local.hansearch.mac", category: "eventkit-access")
    static func hasAccess(_ type: EKEntityType) -> Bool {
        let raw = EKEventStore.authorizationStatus(for: type).rawValue
        let status = EventAccessState.Status(rawValue: raw)
        return type == .event ? events.observe(status) : reminders.observe(status)
    }
    static func require(_ type: EKEntityType) throws {
        guard hasAccess(type) else { throw permissionFailure(type) }
    }
    static func permissionFailure(_ type: EKEntityType) -> SourceAccessFailure {
        SourceAccessFailure(source: type == .event ? "行事曆" : "提醒事項", status: EventAccessState.Status(rawValue: EKEventStore.authorizationStatus(for: type).rawValue))
    }
    static func authorize(_ type: EKEntityType) async throws {
        if hasAccess(type) { return }
        let granted: Bool = try await TimedCallback.wait(timeout: 120) { reply in
            let completion: @Sendable (Bool, Error?) -> Void = { granted, error in
                if let error { reply(.failure(error)) } else { reply(.success(granted)) }
            }
            if type == .event { store.requestFullAccessToEvents(completion: completion) }
            else { store.requestFullAccessToReminders(completion: completion) }
        }
        if type == .event { events.completed(granted: granted) }
        else { reminders.completed(granted: granted) }
        log.info("EventKit request completed; entity=\(type.rawValue, privacy: .public), granted=\(granted, privacy: .public), reportedStatus=\(EKEventStore.authorizationStatus(for: type).rawValue, privacy: .public)")
        guard granted, hasAccess(type) else { throw permissionFailure(type) }
    }
}
