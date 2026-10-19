import Foundation
import HanSearchCore

enum NotesReader {
    // Read only. Identifiers and limits are data arguments, never executable script.
    static let script = #"""
    function run(args) {
        ObjC.import('Foundation');
        function emit(value) {
            $.NSFileHandle.fileHandleWithStandardOutput.writeData($(JSON.stringify(value)+'\n').dataUsingEncoding($.NSUTF8StringEncoding));
        }
        const app = Application('Notes'), request = JSON.parse(args[0]);
        if (request.mode === 'manifest') {
            const ids = app.notes.id();
            emit({kind:'manifest', ids:ids.slice(0,2000), capped:ids.length > 2000});
            return '';
        }
        const deadline = Date.now() + Math.min(12000, Math.max(0, request.budgetMs)), ids = request.ids.slice(0,50);
        let bytes = request.textCount || 0;
        for (let i = 0; i < ids.length; i++) {
            if (i > 0 && Date.now() >= deadline) { break; }
            const id = ids[i];
            emit({kind:'begin', id:id});
            try {
                const n = app.notes.byId(id);
                if (n.passwordProtected()) { emit({kind:'skip', id:id, protected:true}); continue; }
                const title = n.name();
                let text = n.plaintext();
                const truncated = text.length > 100000 || bytes + text.length > 16000000;
                if (truncated) { text = ''; }
                bytes += text.length;
                emit({kind:'note', id:id, title:title, text:text, truncated:truncated});
            } catch (e) { emit({kind:'skip', id:id, protected:false}); }
        }
        emit({kind:'end'});
        return '';
    }
    """#

    private struct Event: Decodable {
        let kind: String
        let ids: [String]?
        let capped: Bool?
        let id: String?
        let title: String?
        let text: String?
        let truncated: Bool?
        let `protected`: Bool?
    }

    static func read(checkpoint: NotesReadState?, cancellation: ProcessCancellation,
                     progress: @escaping @Sendable (PersonalLoad) -> Void) throws -> PersonalLoad {
        let decoder = JSONDecoder()
        var scan: NotesReadState
        if let checkpoint, checkpoint.hasMore { scan = checkpoint }
        else {
            let data = try run(["mode": "manifest"], cancellation: cancellation)
            guard let line = data.split(separator: 10).first,
                  let manifest = try? decoder.decode(Event.self, from: Data(line)), manifest.kind == "manifest", let ids = manifest.ids else {
                throw ProcessFailure.failed("備忘錄未回傳有效的讀取狀態，請稍後重試。")
            }
            scan = NotesReadState(identifiers: ids, capped: manifest.capped ?? false)
        }
        var activeID: String?, ended = false, receivedEvent = false
        let before = scan.processed
        var deferredStuckNote = false
        if scan.hasMore {
            do {
                _ = try run(["mode": "read", "ids": Array(scan.pending.prefix(50)), "budgetMs": 12000, "textCount": scan.textCount], cancellation: cancellation) { data in
                    guard let event = try? decoder.decode(Event.self, from: data) else { return }
                    receivedEvent = true
                    if event.kind == "begin" { activeID = event.id; return }
                    if event.kind == "end" { ended = true; return }
                    guard let id = event.id else { return }
                    if event.kind == "note", let title = event.title, let text = event.text {
                        scan.receive(id: id, title: title, text: text, isTruncated: event.truncated ?? false)
                    } else if event.kind == "skip" { scan.skip(id: id, protected: event.protected ?? false) }
                    else { return }
                    activeID = nil
                    if scan.processed % 10 == 0 || !scan.hasMore { progress(load(scan)) }
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                // A bounded worker may time out inside one Apple event. Keep its earlier
                // results and let the next worker read the remaining stable identifiers.
                if let activeID { scan.timedOut(id: activeID); deferredStuckNote = true }
                else if !receivedEvent { throw error }
            }
            guard ended || receivedEvent else { throw ProcessFailure.failed("備忘錄未回傳有效的讀取狀態，請稍後重試。") }
            guard scan.processed > before || deferredStuckNote else { throw ProcessFailure.failed("備忘錄本批未能繼續讀取；已保留先前進度，稍後可重新讀取。") }
        }
        return load(scan)
    }

    static func progressStatus(_ scan: NotesReadState) -> String {
        "正在讀取備忘錄 \(scan.processed)/\(scan.total)；已載入 \(scan.records.count) 則，可先搜尋"
    }
    private static func load(_ scan: NotesReadState) -> PersonalLoad {
        let status = scan.hasMore ? progressStatus(scan) : "已連接 \(scan.records.count) 則備忘錄（\(scan.total) 則已檢查；\(scan.protectedCount) 則受保護略過；\(scan.incompleteCount) 則無法完整讀取）" + (scan.capped ? "（2,000 則上限）" : "")
        return PersonalLoad(records: scan.records, status: status, complete: scan.complete, notesCheckpoint: scan.hasMore ? scan : nil)
    }
    private static func run(_ request: [String: Any], cancellation: ProcessCancellation, onLine: ((Data) -> Void)? = nil) throws -> Data {
        let argument = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        return try ProcessRunner.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", script, argument], timeout: 30, cancellation: cancellation, onLine: onLine)
    }
}
