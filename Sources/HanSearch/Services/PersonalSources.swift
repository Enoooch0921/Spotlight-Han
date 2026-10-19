import Foundation
import Contacts
import EventKit
import CoreServices
import HanSearchCore

struct PersonalLoad: Sendable {
    let records: [PersonalRecord]
    let status: String
    var complete: Bool = true
    var notesCheckpoint: NotesReadState? = nil
}

enum PersonalSources {
    // A permission dialog may outlive our timeout. Keep its EventKit owner alive until the app exits.
    @MainActor private static let contactAuthorizationStore = CNContactStore()
    @MainActor static func isAuthorized(_ source: SearchMode) -> Bool {
        switch source {
        case .contacts:
            let status = CNContactStore.authorizationStatus(for: .contacts)
            return status == .authorized || status.rawValue == 4
        case .calendar: return EventKitAccess.hasAccess(.event)
        case .reminders: return EventKitAccess.hasAccess(.reminder)
        case .notes, .mail:
            let target = NSAppleEventDescriptor(bundleIdentifier: source == .notes ? "com.apple.Notes" : "com.apple.mail")
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
        default: return true
        }
    }

    @MainActor static func permissionFailure(_ source: SearchMode) -> SourceAccessFailure {
        if source == .calendar { return EventKitAccess.permissionFailure(.event) }
        if source == .reminders { return EventKitAccess.permissionFailure(.reminder) }
        if source == .contacts {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            return SourceAccessFailure(source: source.rawValue, status: status == .denied ? .denied : status == .restricted ? .restricted : .notDetermined)
        }
        if source == .notes || source == .mail {
            let target = NSAppleEventDescriptor(bundleIdentifier: source == .notes ? "com.apple.Notes" : "com.apple.mail")
            let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
            return SourceAccessFailure(source: source.rawValue, status: result == errAEEventNotPermitted ? .denied : .notDetermined)
        }
        return SourceAccessFailure(source: source.rawValue)
    }

    private static func automationIsAuthorized(_ source: SearchMode) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: source == .notes ? "com.apple.Notes" : "com.apple.mail")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
    }

    @MainActor static func authorize(_ source: SearchMode) async throws {
        if isAuthorized(source) { return }
        let granted: Bool
        switch source {
        case .contacts:
            let store = contactAuthorizationStore
            granted = try await TimedCallback.wait(timeout: 120) { reply in
                store.requestAccess(for: .contacts) { allowed, error in
                    if let error { reply(.failure(error)) } else { reply(.success(allowed)) }
                }
            }
        case .calendar:
            try await EventKitAccess.authorize(.event); return
        case .reminders:
            try await EventKitAccess.authorize(.reminder); return
        case .notes, .mail:
            let target = source == .notes ? "com.apple.Notes" : "com.apple.mail"
            let cancellation = ProcessCancellation()
            let worker = Task.detached(priority: .userInitiated) {
                // Ask using an application-name read, then release the consent UI before slow content indexing.
                try ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", "function run(a) { return Application(a[0]).name(); }", target], timeout: 120, cancellation: cancellation)
            }
            do {
                _ = try await withTaskCancellationHandler { try await worker.value }
                    onCancel: { cancellation.cancel(); worker.cancel() }
            } catch {
                let permission = permissionFailure(source)
                if !Task.isCancelled, permission.status == .denied { throw permission }
                throw error
            }
            granted = isAuthorized(source)
        default: return
        }
        guard granted else { throw permissionFailure(source) }
    }

    static func contacts() async throws -> PersonalLoad {
        guard await isAuthorized(.contacts) else { throw await permissionFailure(.contacts) }
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var records: [PersonalRecord] = []
        try store.enumerateContacts(with: request) { contact, stop in
            if Task.isCancelled { stop.pointee = true; return }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "未命名聯絡人"
            let details = contact.phoneNumbers.map { $0.value.stringValue } + contact.emailAddresses.map { String($0.value) }
            let text = ([name] + details).joined(separator: "\n")
            records.append(PersonalRecord(id: "contact:" + contact.identifier, title: name, subtitle: details.first ?? "聯絡人", text: text, symbol: "person.crop.circle", mode: .contacts, action: .details(text)))
        }
        try Task.checkCancellation()
        return PersonalLoad(records: records, status: "已連接 \(records.count) 位聯絡人")
    }

    @MainActor static func calendar() async throws -> PersonalLoad {
        try EventKitAccess.require(.event)
        let store = EventKitAccess.store
        let calendar = Calendar.current, now = Date()
        let start = calendar.date(byAdding: .year, value: -1, to: now)!
        let end = calendar.date(byAdding: .year, value: 1, to: now)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        let ordered = events.sorted { CalendarResultSort.upcoming.precedes(start: $0.startDate, end: $0.endDate, id: $0.eventIdentifier ?? "", start: $1.startDate, end: $1.endDate, id: $1.eventIdentifier ?? "", now: now) }
        let snapshots = ordered.prefix(10000).map { event in
            EventSnapshot(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "未命名行程", start: event.startDate, end: event.endDate, allDay: event.isAllDay, calendar: event.calendar.title, location: event.location ?? "", notes: event.notes ?? "")
        }
        // EventKit objects stay with their store; Chinese folding runs off the UI actor.
        return await Task.detached(priority: .utility) {
            let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
            let records = snapshots.map { event -> PersonalRecord in
                let date = formatter.string(from: event.start)
                let timing = event.allDay ? event.start.formatted(date: .abbreviated, time: .omitted) + " · " + L.text("全天") : date + " – " + formatter.string(from: event.end)
                let subtitle = timing + " · " + event.calendar
                let details = [event.title, subtitle, event.location, event.notes].filter { !$0.isEmpty }.joined(separator: "\n")
                return PersonalRecord(id: "event:" + event.id + date, title: event.title, subtitle: subtitle, text: details, symbol: "calendar", mode: .calendar, action: .details(details), startDate: event.start, endDate: event.end)
            }
            return PersonalLoad(records: records, status: "已連接 \(records.count) 個行程（前後各一年）")
        }.value
    }

    @MainActor static func reminders() async throws -> PersonalLoad {
        try EventKitAccess.require(.reminder)
        let store = EventKitAccess.store
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = try await TimedCallback.wait(timeout: 45) { reply in
            store.fetchReminders(matching: predicate) { reply(.success($0 ?? [])) }
        }
        try EventKitAccess.require(.reminder)
        let snapshots = reminders.prefix(10000).map { reminder in
            ReminderSnapshot(id: reminder.calendarItemIdentifier, title: reminder.title ?? "未命名提醒事項", due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }, calendar: reminder.calendar.title, notes: reminder.notes ?? "")
        }
        return await Task.detached(priority: .utility) {
            let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
            let records = snapshots.map { reminder -> PersonalRecord in
                let date = reminder.due.map { formatter.string(from: $0) } ?? "未設定時間"
                let details = [reminder.title, date, reminder.calendar, reminder.notes].joined(separator: "\n")
                return PersonalRecord(id: "reminder:" + reminder.id, title: reminder.title, subtitle: date + " · " + reminder.calendar, text: details, symbol: "checklist", mode: .reminders, action: .details(details))
            }
            return PersonalLoad(records: records, status: "已連接 \(records.count) 個未完成提醒事項（10,000 筆上限）")
        }.value
    }

    private struct EventSnapshot: Sendable {
        let id: String; let title: String; let start: Date; let end: Date; let allDay: Bool; let calendar: String; let location: String; let notes: String
    }
    private struct ReminderSnapshot: Sendable {
        let id: String; let title: String; let due: Date?; let calendar: String; let notes: String
    }

    private struct RawItem: Decodable { let id: String; let title: String; let text: String; let detail: String }
    private struct RawLoad: Decodable { let items: [RawItem]; let skipped: Int; let capped: Bool }

    static func notes(checkpoint: NotesReadState?, cancellation: ProcessCancellation, progress: @escaping @Sendable (PersonalLoad) -> Void) throws -> PersonalLoad {
        do { return try NotesReader.read(checkpoint: checkpoint, cancellation: cancellation, progress: progress) }
        catch is CancellationError { throw CancellationError() }
        catch {
            guard automationIsAuthorized(.notes) else { throw SourceAccessFailure(source: "備忘錄", status: .denied) }
            throw error
        }
    }

    static func mail(cancellation: ProcessCancellation) throws -> PersonalLoad {
        let script = #"""
        function run() {
            const app = Application('Mail'), all = app.inbox.messages(), items = [];
            let skipped = 0;
            for (let i = 0; i < Math.min(all.length, 200); i++) {
                try {
                    const m = all[i];
                    items.push({id:m.messageId(), title:m.subject(), text:m.content().slice(0,16000), detail:m.sender()});
                } catch (e) { skipped++; }
            }
            return JSON.stringify({items:items, skipped:skipped, capped:all.length > 200});
        }
        """#
        let data = try ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script], timeout: 90, cancellation: cancellation)
        let load = try JSONDecoder().decode(RawLoad.self, from: data)
        let records = load.items.map { item -> PersonalRecord in
            let id = "<" + item.id.trimmingCharacters(in: CharacterSet(charactersIn: "<>")) + ">"
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            return PersonalRecord(id: "mail:" + item.id, title: item.title, subtitle: item.detail, text: item.text, symbol: "envelope", mode: .mail, action: .open(URL(string: "message://" + encoded)!))
        }
        return PersonalLoad(records: records, status: "已連接 Mail 收件匣 \(records.count) 封（前 200 封，內文前 16,000 字）" + (load.skipped > 0 ? "；\(load.skipped) 封無法讀取" : ""), complete: load.skipped == 0)
    }

    static func shortcuts() throws -> PersonalLoad {
        let data = try ProcessRunner.run("/usr/bin/shortcuts", ["list"], timeout: 30)
        let names = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        let records = names.map { PersonalRecord(id: "shortcut:" + $0, title: $0, subtitle: "捷徑 · 執行前確認", text: $0, symbol: "square.stack.3d.up", mode: .shortcuts, action: .shortcut($0)) }
        return PersonalLoad(records: records, status: "已連接 \(records.count) 個捷徑")
    }

    static func openNote(_ identifier: String) throws {
        // The identifier is passed as an argument, never interpolated as JavaScript source.
        let script = "function run(a) { const n=Application('Notes'); n.show(n.notes.byId(a[0])); n.activate(); }"
        _ = try ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script, identifier], timeout: 15)
    }

    static func definition(_ word: String) -> String? {
        DCSCopyTextDefinition(nil, word as CFString, CFRange(location: 0, length: (word as NSString).length))?.takeRetainedValue() as String?
    }
}
