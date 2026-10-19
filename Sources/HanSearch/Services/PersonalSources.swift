import Foundation
import Contacts
import EventKit
import CoreServices
import HanSearchCore

struct PersonalLoad: Sendable {
    let records: [PersonalRecord]
    let status: String
}

enum PersonalSources {
    // A permission dialog may outlive our timeout. Keep its EventKit owner alive until the app exits.
    @MainActor private static let contactAuthorizationStore = CNContactStore()
    @MainActor private static let calendarAuthorizationStore = EKEventStore()
    @MainActor private static let reminderAuthorizationStore = EKEventStore()
    static func isAuthorized(_ source: SearchMode) -> Bool {
        switch source {
        case .contacts:
            let status = CNContactStore.authorizationStatus(for: .contacts)
            return status == .authorized || status.rawValue == 4
        case .calendar: return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .reminders: return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        case .notes, .mail:
            let target = NSAppleEventDescriptor(bundleIdentifier: source == .notes ? "com.apple.Notes" : "com.apple.mail")
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
        default: return true
        }
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
            let store = calendarAuthorizationStore
            granted = try await TimedCallback.wait(timeout: 120) { reply in
                store.requestFullAccessToEvents { allowed, error in
                    if let error { reply(.failure(error)) } else { reply(.success(allowed)) }
                }
            }
        case .reminders:
            let store = reminderAuthorizationStore
            granted = try await TimedCallback.wait(timeout: 120) { reply in
                store.requestFullAccessToReminders { allowed, error in
                    if let error { reply(.failure(error)) } else { reply(.success(allowed)) }
                }
            }
        case .notes, .mail:
            let target = source == .notes ? "com.apple.Notes" : "com.apple.mail"
            let cancellation = ProcessCancellation()
            let worker = Task.detached(priority: .userInitiated) {
                // Ask using an application-name read, then release the consent UI before slow content indexing.
                try ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", "function run(a) { return Application(a[0]).name(); }", target], timeout: 120, cancellation: cancellation)
            }
            _ = try await withTaskCancellationHandler { try await worker.value }
                onCancel: { cancellation.cancel(); worker.cancel() }
            granted = isAuthorized(source)
        default: return
        }
        guard granted else { throw ProcessFailure.failed("\(source.rawValue)未授權，可在系統設定的隱私權中調整。") }
    }

    static func contacts() async throws -> PersonalLoad {
        guard isAuthorized(.contacts) else { throw ProcessFailure.failed("聯絡人尚未授權，請按連接。") }
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

    static func calendar() async throws -> PersonalLoad {
        guard isAuthorized(.calendar) else { throw ProcessFailure.failed("行事曆尚未授權，請按連接。") }
        let store = EKEventStore()
        let calendar = Calendar.current, now = Date()
        let start = calendar.date(byAdding: .year, value: -1, to: now)!
        let end = calendar.date(byAdding: .year, value: 1, to: now)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        let records = events.prefix(10000).map { event -> PersonalRecord in
            let title = event.title ?? "未命名行程"
            let date = formatter.string(from: event.startDate)
            let details = [title, date, event.location ?? "", event.notes ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
            return PersonalRecord(id: "event:" + (event.eventIdentifier ?? UUID().uuidString) + date, title: title, subtitle: date, text: details, symbol: "calendar", mode: .calendar, action: .details(details))
        }
        return PersonalLoad(records: records, status: "已連接 \(records.count) 個行程（前後各一年）")
    }

    static func reminders() async throws -> PersonalLoad {
        guard isAuthorized(.reminders) else { throw ProcessFailure.failed("提醒事項尚未授權，請按連接。") }
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = try await TimedCallback.wait(timeout: 45) { reply in
            store.fetchReminders(matching: predicate) { reply(.success($0 ?? [])) }
        }
        withExtendedLifetime(store) {}
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        let records = reminders.prefix(10000).map { reminder -> PersonalRecord in
            let title = reminder.title ?? "未命名提醒事項"
            let date = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map { formatter.string(from: $0) } ?? "未設定時間"
            let details = [title, date, reminder.calendar.title, reminder.notes ?? ""].joined(separator: "\n")
            return PersonalRecord(id: "reminder:" + reminder.calendarItemIdentifier, title: title, subtitle: date + " · " + reminder.calendar.title, text: details, symbol: "checklist", mode: .reminders, action: .details(details))
        }
        return PersonalLoad(records: records, status: "已連接 \(records.count) 個未完成提醒事項（10,000 筆上限）")
    }

    private struct RawItem: Decodable { let id: String; let title: String; let text: String; let detail: String }
    private struct RawLoad: Decodable { let items: [RawItem]; let skipped: Int; let capped: Bool }

    private struct NoteEvent: Decodable {
        let kind: String
        let total: Int?
        let capped: Bool?
        let item: RawItem?
        let truncated: Bool?
    }

    static func notes(cancellation: ProcessCancellation, progress: @escaping @Sendable (PersonalLoad) -> Void) throws -> PersonalLoad {
        // These are read-only Apple events. Password-protected notes are deliberately skipped.
        let script = #"""
        function run() {
            ObjC.import('Foundation');
            function emit(value) {
                $.NSFileHandle.fileHandleWithStandardOutput.writeData($(JSON.stringify(value)+'\n').dataUsingEncoding($.NSUTF8StringEncoding));
            }
            const app = Application('Notes'), all = app.notes();
            let bytes = 0, capped = all.length > 2000;
            emit({kind:'start', total:Math.min(all.length,2000), capped:capped});
            for (let i = 0; i < Math.min(all.length, 2000); i++) {
                try {
                    const n = all[i];
                    if (n.passwordProtected()) { emit({kind:'skip'}); continue; }
                    const title = n.name(), id = n.id();
                    let text = n.plaintext();
                    const truncated = text.length > 100000 || bytes + text.length > 16000000;
                    if (truncated) { text = ''; }
                    bytes += text.length;
                    emit({kind:'note', item:{id:id, title:title, text:text, detail:'備忘錄'}, truncated:truncated});
                } catch (e) { emit({kind:'skip'}); }
            }
            return '';
        }
        """#
        var records: [PersonalRecord] = [], total = 0, processed = 0, skipped = 0, capped = false, receivedHeader = false
        let decoder = JSONDecoder()
        do {
            _ = try ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script], timeout: 90, cancellation: cancellation) { line in
                guard let event = try? decoder.decode(NoteEvent.self, from: line) else { return }
                if event.kind == "start" { total = event.total ?? 0; capped = event.capped ?? false; receivedHeader = true }
                else {
                    processed += 1
                    if let item = event.item {
                        records.append(PersonalRecord(id: "note:" + item.id, title: item.title, subtitle: String(item.text.replacingOccurrences(of: "\n", with: " ").prefix(100)), text: item.text, symbol: "note.text", mode: .notes, action: .note(item.id)))
                        if event.truncated == true { skipped += 1 }
                    } else { skipped += 1 }
                }
                if processed <= 1 || processed % 10 == 0 || processed == total {
                    progress(PersonalLoad(records: records, status: "正在讀取備忘錄 \(processed)/\(total)；已載入 \(records.count) 則，可先搜尋"))
                }
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            guard isAuthorized(.notes) else { throw ProcessFailure.failed("備忘錄尚未授權，請在系統設定 → 隱私權與安全性 → 自動化中檢查 Han 對備忘錄的存取。") }
            guard !records.isEmpty else { throw ProcessFailure.failed("備忘錄讀取逾時或未完成。備忘錄資料多、iCloud 同步或系統等待授權時可能較久；請稍後重試。") }
            return PersonalLoad(records: records, status: "已連接 \(records.count) 則備忘錄（部分讀取；可按重新讀取）")
        }
        guard receivedHeader else { throw ProcessFailure.failed("備忘錄未回傳有效的讀取狀態，請稍後重試。") }
        return PersonalLoad(records: records, status: "已連接 \(records.count) 則備忘錄" + (skipped > 0 ? "；\(skipped) 則受保護或無法完整讀取" : "") + (capped ? "（2,000 則上限）" : ""))
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
        return PersonalLoad(records: records, status: "已連接 Mail 收件匣 \(records.count) 封（前 200 封，內文前 16,000 字）" + (load.skipped > 0 ? "；\(load.skipped) 封無法讀取" : ""))
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
