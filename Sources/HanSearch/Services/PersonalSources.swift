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
    static func contacts() async throws -> PersonalLoad {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else { throw ProcessFailure.failed("聯絡人未授權，可在系統設定的隱私權中調整。") }
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var records: [PersonalRecord] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "未命名聯絡人"
            let details = contact.phoneNumbers.map { $0.value.stringValue } + contact.emailAddresses.map { String($0.value) }
            let text = ([name] + details).joined(separator: "\n")
            records.append(PersonalRecord(id: "contact:" + contact.identifier, title: name, subtitle: details.first ?? "聯絡人", text: text, symbol: "person.crop.circle", mode: .contacts, action: .details(text)))
        }
        return PersonalLoad(records: records, status: "已連接 \(records.count) 位聯絡人")
    }

    static func calendar() async throws -> PersonalLoad {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw ProcessFailure.failed("行事曆未授權。") }
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

    private struct RawItem: Decodable { let id: String; let title: String; let text: String; let detail: String }
    private struct RawLoad: Decodable { let items: [RawItem]; let skipped: Int; let capped: Bool }

    static func notes() throws -> PersonalLoad {
        // These are read-only Apple events. Password-protected notes are deliberately skipped.
        let script = #"""
        function run() {
            const app = Application('Notes'), all = app.notes(), items = [];
            let skipped = 0, bytes = 0, capped = all.length > 2000;
            for (let i = 0; i < Math.min(all.length, 2000); i++) {
                try {
                    const n = all[i];
                    if (n.passwordProtected()) { skipped++; continue; }
                    const title = n.name(), id = n.id();
                    let text = n.plaintext();
                    if (text.length > 100000 || bytes + text.length > 16000000) { text = ''; skipped++; }
                    bytes += text.length;
                    items.push({id:id, title:title, text:text, detail:'備忘錄'});
                } catch (e) { skipped++; }
            }
            return JSON.stringify({items:items, skipped:skipped, capped:capped});
        }
        """#
        let data = try ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script], timeout: 90)
        let load = try JSONDecoder().decode(RawLoad.self, from: data)
        let records = load.items.map { PersonalRecord(id: "note:" + $0.id, title: $0.title, subtitle: String($0.text.replacingOccurrences(of: "\n", with: " ").prefix(100)), text: $0.text, symbol: "note.text", mode: .notes, action: .note($0.id)) }
        return PersonalLoad(records: records, status: "已連接 \(records.count) 則備忘錄" + (load.skipped > 0 ? "；\(load.skipped) 則受保護或無法完整讀取" : "") + (load.capped ? "（2,000 則上限）" : ""))
    }

    static func mail() throws -> PersonalLoad {
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
        let data = try ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script], timeout: 90)
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
