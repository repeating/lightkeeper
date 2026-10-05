import Foundation
import CSQLite
import Darwin

public struct CodexThread {
    public let id: String
    public let title: String
    public let cwd: String
}
public enum DiscoveryError: Error { case database(String), invalidRecord }
public enum CodexDiscovery {
    public static func lastTurnStatus(historyDatabase: URL, threadID: String) throws -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(historyDatabase.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db); throw DiscoveryError.database("Cannot read turn history")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)
        var statement: OpaquePointer?
        let sql = "SELECT status FROM thread_turns WHERE thread_id=? ORDER BY rollout_ordinal DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw DiscoveryError.database("Unsupported turn history") }
        defer { sqlite3_finalize(statement) }
        let bound = threadID.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard bound == SQLITE_OK else { throw DiscoveryError.database("Cannot bind thread") }
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return sqlite3_column_text(statement, 0).map { String(cString: $0) }
        case SQLITE_DONE: return nil
        default: throw DiscoveryError.database("Turn history temporarily unavailable")
        }
    }
    public static func threads(database: URL, since: Date) throws -> [CodexThread] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open Codex metadata"
            sqlite3_close(db); throw DiscoveryError.database(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)
        let sql = """
        SELECT id,title,cwd FROM threads WHERE archived=0
        AND (agent_path IS NULL OR agent_path='/root')
        AND (thread_source IS NULL OR thread_source='user')
        AND originator LIKE '%Desktop%' AND recency_at>=?
        ORDER BY recency_at DESC LIMIT 80
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw DiscoveryError.database(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970))
        var rows: [CodexThread] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            func text(_ index: Int32) -> String { sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
            rows.append(CodexThread(id: text(0), title: text(1), cwd: text(2)))
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw DiscoveryError.database(String(cString: sqlite3_errmsg(db))) }
        return rows
    }
}

public struct ClaudeRecord {
    public var pid: Int32
    public var session: Session
    public static func parse(_ data: Data, isAlive: (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) throws -> ClaudeRecord? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = object["pid"] as? Int, pid > 0, pid <= Int(Int32.max),
              let id = object["sessionId"] as? String, !id.isEmpty,
              let status = object["status"] as? String else { throw DiscoveryError.invalidRecord }
        // SDK agents such as memory observers publish the same registry but
        // are not user-facing Claude Code sessions.
        if object["entrypoint"] as? String == "sdk-cli" { return nil }
        if let kind = object["kind"] as? String, kind != "interactive" { return nil }
        guard isAlive(Int32(pid)) else { return nil }
        let state = StatusDecoder.claude(status)
        let cwd = object["cwd"] as? String ?? ""
        let name = object["name"] as? String
        let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? URL(fileURLWithPath: cwd).lastPathComponent
        let reason = object["waitingFor"] as? String
        let detail: String
        switch state {
        case .running: detail = "Running"
        case .needsInput: detail = reason ?? "Needs your attention"
        case .finished: detail = "Finished"
        case .unknown: detail = "Unsupported status: \(status)"
        }
        let date = (object["statusUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        return ClaudeRecord(pid: Int32(pid), session: Session(id: "claude:\(id)", source: "Claude Code", title: title.isEmpty ? "Claude session" : title, state: state, detail: detail, updatedAt: date, openURL: SessionLink.claude(sessionID: id, hostSessionID: object["hostSessionId"] as? String)))
    }
}
