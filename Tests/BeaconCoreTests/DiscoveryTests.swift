import Foundation
import BeaconCore
import CSQLite

final class DiscoveryTests: XCTestCase {
    func testClaudeWaitingReasonAndDeadPID() throws {
        let data = Data("""
        {"pid":123,"sessionId":"abc","cwd":"/Projects/Test","name":"Build app","status":"waiting","waitingFor":"input needed","statusUpdatedAt":1791188726477}
        """.utf8)
        let record = try XCTUnwrap(ClaudeRecord.parse(data, isAlive: { $0 == 123 }))
        XCTAssertEqual(record.session.state, .needsInput)
        XCTAssertEqual(record.session.detail, "input needed")
        XCTAssertEqual(record.session.title, "Build app")
        XCTAssertEqual(try ClaudeRecord.parse(data, isAlive: { _ in false })?.session.id, nil)
    }
    func testClaudeDesktopLinksOpenTheHostSessionWithoutImportingCLIHistory() throws {
        let cli = "d156d5a6-da91-5df8-8a0b-d1ea8c7a6638"
        let host = "local_5b3b7526-47b1-5bf7-babb-e9224d814209"
        let url = SessionLink.claude(sessionID: cli, hostSessionID: host)
        let data = Data("""
        {"pid":123,"sessionId":"\(cli)","hostSessionId":"\(host)","status":"busy"}
        """.utf8)
        XCTAssertEqual(try ClaudeRecord.parse(data, isAlive: { _ in true })?.session.openURL, url)
        XCTAssertEqual(url?.scheme, "claude")
        XCTAssertEqual(url?.host, "code")
        XCTAssertEqual(url?.path, "/continue")
        XCTAssertEqual(URLComponents(url: url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, host)
    }
    func testClaudeTerminalLinksTargetExactTranscriptAndInvalidIDsAreRejected() {
        let cli = "d156d5a6-da91-5df8-8a0b-d1ea8c7a6638"
        XCTAssertEqual(SessionLink.claude(sessionID: cli, hostSessionID: nil)?.absoluteString, "claude://resume?session=d156d5a6-da91-5df8-8a0b-d1ea8c7a6638")
        XCTAssertEqual(SessionLink.claude(sessionID: "bad&session=other", hostSessionID: nil), nil)
        XCTAssertEqual(SessionLink.codex(sessionID: cli)?.absoluteString, "codex://threads/" + cli)
        XCTAssertEqual(SessionLink.codex(sessionID: "invalid"), nil)
    }
    func testMalformedClaudeRecordIsRejected() {
        XCTAssertThrowsError(try ClaudeRecord.parse(Data("{\"status\":\"busy\"}".utf8)))
    }
    func testSDKHelperSessionsAreExcluded() throws {
        let data = Data("""
        {"pid":123,"sessionId":"observer","kind":"interactive","entrypoint":"sdk-cli","name":"171-dc","cwd":"/Users/test/.claude-mem/observer-sessions/171","status":"busy"}
        """.utf8)
        XCTAssertEqual(try ClaudeRecord.parse(data, isAlive: { _ in true })?.session.id, nil)
    }
    func testDiscoveryExcludesArchivedSubagentsAndOldHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw DiscoveryError.invalidRecord }
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE threads (id TEXT,title TEXT,cwd TEXT,archived INTEGER,agent_path TEXT,thread_source TEXT,originator TEXT,recency_at INTEGER);
        INSERT INTO threads VALUES ('root','App','/Projects/App',0,'/root','user','Codex Desktop',200);
        INSERT INTO threads VALUES ('child','Internal','/Projects/App',0,'/root/reviewer','subagent','Codex Desktop',200);
        INSERT INTO threads VALUES ('archived','Archive','/Projects/App',1,NULL,'user','Codex Desktop',200);
        INSERT INTO threads VALUES ('old','History','/Projects/App',0,NULL,'user','Codex Desktop',1);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DiscoveryError.invalidRecord }
        let rows = try CodexDiscovery.threads(database: url, since: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(rows.map(\.id), ["root"])
        XCTAssertEqual(rows.first?.title, "App")
    }
}
