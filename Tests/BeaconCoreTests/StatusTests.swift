import Foundation
import BeaconCore

final class StatusTests: XCTestCase {
    func testCodexRuntimeFlagsOverrideRunningAndClearWhenResolved() {
        XCTAssertEqual(StatusDecoder.codex(["threadRuntimeStatus": ["type": "active", "activeFlags": []]]), .running)
        XCTAssertEqual(StatusDecoder.codex(["threadRuntimeStatus": ["type": "active", "activeFlags": ["waitingOnApproval"]]]), .needsInput)
        XCTAssertEqual(StatusDecoder.codex(["threadRuntimeStatus": ["type": "active", "activeFlags": ["waitingOnUserInput"]]]), .needsInput)
        XCTAssertEqual(StatusDecoder.codex(["threadRuntimeStatus": ["type": "idle"]]), .finished)
    }
    func testPendingQuestionIsOrangeEvenWithIdleRuntime() {
        let snapshot: [String: Any] = ["threadRuntimeStatus": ["type": "idle"], "requests": [["method": "item/tool/requestUserInput"]]]
        XCTAssertEqual(StatusDecoder.codex(snapshot), .needsInput)
    }
    func testDisconnectedOrMissingRuntimeIsNotFinished() {
        XCTAssertEqual(StatusDecoder.codex([:]), .unknown)
        XCTAssertEqual(StatusDecoder.codex(["threadRuntimeStatus": ["type": "notLoaded"]]), .unknown)
    }
    func testClaudeExplicitStatuses() {
        XCTAssertEqual(StatusDecoder.claude("busy"), .running)
        XCTAssertEqual(StatusDecoder.claude("waiting"), .needsInput)
        XCTAssertEqual(StatusDecoder.claude("idle"), .finished)
        XCTAssertEqual(StatusDecoder.claude("unrecognized"), .unknown)
    }
    func testOnlyStatusChangesAlertAndDismissedSessionCanRunAgain() {
        var ledger = SessionLedger()
        var row = Session(id: "a", source: "Codex", title: "Task", state: .running, detail: "Running")
        XCTAssertFalse(ledger.update(row, initial: true))
        row.title = "New title"
        XCTAssertFalse(ledger.update(row))
        row.state = .needsInput
        XCTAssertTrue(ledger.update(row))
        XCTAssertFalse(ledger.update(row))
        row.state = .finished
        XCTAssertTrue(ledger.update(row))
        ledger.dismiss(row.id)
        XCTAssertFalse(ledger.update(row))
        XCTAssertTrue(ledger.sessions.isEmpty)
        row.state = .running
        XCTAssertTrue(ledger.update(row))
        XCTAssertEqual(ledger.sessions.count, 1)
    }
    func testMonitorUncertaintyDoesNotCreateCompletionAlert() {
        var ledger = SessionLedger()
        let row = Session(id: "a", source: "Codex", title: "Task", state: .unknown, detail: "Disconnected")
        XCTAssertFalse(ledger.update(row))
    }
    func testPlanImplementationApprovalIsOrange() {
        XCTAssertEqual(StatusDecoder.codex(["threadRuntimeStatus": ["type": "idle"], "requests": [["method": "item/plan/requestImplementation"]]]), .needsInput)
    }
    func testFailedAndInterruptedResponsesKeepAccurateLabels() {
        XCTAssertEqual(StatusDecoder.codexDetail(["threadRuntimeStatus": ["type": "idle"], "turns": [["status": "failed"]]]), "Failed")
        XCTAssertEqual(StatusDecoder.codexDetail(["threadRuntimeStatus": ["type": "idle"], "turns": [["status": "interrupted"]]]), "Interrupted")
    }
    func testUnchangedStateDoesNotAlertAfterSourceReconnects() {
        var ledger = SessionLedger()
        var row = Session(id: "a", source: "Codex", title: "Task", state: .running, detail: "Running")
        _ = ledger.update(row, initial: true)
        ledger.markSourceDisconnected("Codex")
        XCTAssertEqual(ledger.sessions["a"]?.state, .unknown)
        XCTAssertFalse(ledger.update(row))
        ledger.markSourceDisconnected("Codex")
        row.state = .finished
        XCTAssertTrue(ledger.update(row))
    }
    func testAsyncQuestionCardsAreOrangeUntilAcceptedReply() {
        let question: [String: Any] = ["id": "call-question", "type": "agentMessage", "questions": [["title": "Desktop or browser?", "options": ["Both", "Desktop"]]]]
        let reply: [String: Any] = ["type": "steeringUserMessage", "status": "accepted", "input": [["type": "text", "text": "<send_user_message_question_reply>[{\"questionItemId\":\"[\\\"request_user_input_async\\\",\\\"call-question\\\",0]\",\"answer\":\"Both\"}]</send_user_message_question_reply>"]]]
        var snapshot: [String: Any] = ["threadRuntimeStatus": ["type": "active"], "turns": [["status": "inProgress", "items": [question]]]]
        XCTAssertEqual(StatusDecoder.codex(snapshot), .needsInput)
        XCTAssertEqual(StatusDecoder.codexDetail(snapshot), "Needs your answer")
        snapshot["turns"] = [["status": "inProgress", "items": [question, reply]]]
        XCTAssertEqual(StatusDecoder.codex(snapshot), .running)
        var rejected = reply; rejected["status"] = "rejected"
        snapshot["turns"] = [["status": "inProgress", "items": [question, rejected]]]
        XCTAssertEqual(StatusDecoder.codex(snapshot), .needsInput)
        snapshot["turns"] = [["status": "completed", "items": [question]], ["status": "inProgress", "items": []]]
        XCTAssertEqual(StatusDecoder.codex(snapshot), .running)
    }

}
