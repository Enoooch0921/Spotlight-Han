import Foundation
import SQLite3

/// Each operation owns a connection. WAL allows searching while extraction writes batches.
final class IndexDatabase {
    let handle: OpaquePointer
    init(url: URL, limit: Int64, readOnly: Bool = false) throws {
        if !readOnly { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        var db: OpaquePointer?
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path, &db, flags, nil)
        guard code == SQLITE_OK, let db else { if let db { sqlite3_close(db) }; throw IndexDatabaseError.message("無法開啟 Han 文件索引") }
        handle = db
        do {
            sqlite3_busy_timeout(db, 1500)
            if readOnly { return }
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA secure_delete=ON")
            try execute("PRAGMA synchronous=NORMAL")
            let version = try rows("PRAGMA user_version").first?.first ?? "0"
            guard ["0", "1", "2"].contains(version) else { throw IndexDatabaseError.message("索引版本不相容，請先備份並重建") }
            try execute("CREATE TABLE IF NOT EXISTS documents(path TEXT PRIMARY KEY, name TEXT NOT NULL, body TEXT NOT NULL, modified REAL, created REAL, size INTEGER, reason TEXT, generation TEXT NOT NULL)")
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS document_terms USING fts5(tokens, content='', detail=none)")
            try execute("CREATE TABLE IF NOT EXISTS scans(root TEXT PRIMARY KEY, completed REAL)")
            try execute("CREATE TABLE IF NOT EXISTS scan_state(root TEXT PRIMARY KEY, incomplete INTEGER NOT NULL)")
            if !(try rows("PRAGMA table_info(documents)")).contains(where: { $0[1] == "extraction" }) { try execute("ALTER TABLE documents ADD COLUMN extraction INTEGER NOT NULL DEFAULT 0") }
            try execute("CREATE TABLE IF NOT EXISTS document_pages(path TEXT NOT NULL, page INTEGER NOT NULL, body TEXT NOT NULL, ocr INTEGER NOT NULL, reason TEXT, PRIMARY KEY(path,page))")
            try execute("PRAGMA user_version=2")
            let pageSize = Int64(try rows("PRAGMA page_size").first?.first ?? "4096") ?? 4096
            try execute("PRAGMA max_page_count=\(max(32, limit / pageSize))")
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { sqlite3_close(db); throw error }
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String, _ values: [String?] = []) throws {
        try statement(sql, values) { statement in
            let code = sqlite3_step(statement)
            guard code == SQLITE_DONE || code == SQLITE_ROW else { throw failure(code) }
        }
    }
    func rows(_ sql: String, _ values: [String?] = []) throws -> [[String]] {
        try statement(sql, values) { statement in
            var rows: [[String]] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return rows }
                guard code == SQLITE_ROW else { throw failure(code) }
                rows.append((0..<sqlite3_column_count(statement)).map { i in
                    guard let text = sqlite3_column_text(statement, i) else { return "" }
                    return String(decoding: UnsafeBufferPointer(start: text, count: Int(sqlite3_column_bytes(statement, i))), as: UTF8.self)
                })
            }
        }
    }
    private func statement<T>(_ sql: String, _ values: [String?], operation: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw failure(code) }
        defer { sqlite3_finalize(statement) }
        for (i, value) in values.enumerated() {
            let result: Int32
            if let value { result = value.withCString { sqlite3_bind_text(statement, Int32(i+1), $0, Int32(value.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) } }
            else { result = sqlite3_bind_null(statement, Int32(i+1)) }
            guard result == SQLITE_OK else { throw failure(result) }
        }
        return try operation(statement)
    }
    func transaction<T>(_ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let value = try operation(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func failure(_ code: Int32) -> IndexDatabaseError {
        code == SQLITE_FULL ? .capacity : .message("Han 索引資料庫錯誤（\(code)）：" + String(cString: sqlite3_errmsg(handle)))
    }
}

public enum IndexDatabaseError: Error, LocalizedError {
    case capacity, message(String)
    public var errorDescription: String? {
        switch self { case .capacity: return "Han 索引空間已達上限，尚有文件未收錄"; case .message(let message): return message }
    }
}

/// Coordinate writers across app instances; readers keep using the WAL snapshot.
final class IndexWriteLock {
    private let descriptor: Int32
    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        descriptor = open(url.path + ".scan.lock", O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw IndexDatabaseError.message("無法鎖定 Han 文件索引") }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            throw IndexDatabaseError.message("Han 索引正在由另一個程序更新，請稍後重試")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
