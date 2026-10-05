import Foundation

// A tiny executable harness keeps tests runnable with Command Line Tools, which
// provide the Swift compiler and macOS SDK but do not bundle XCTest.
class XCTestCase {}
var failures = 0
func fail(_ text: String, file: StaticString, line: UInt) {
    failures += 1; print("FAIL \(file):\(line): \(text)")
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { fail("\(actual) != \(expected)", file: file, line: line) }
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value { fail("Expected true", file: file, line: line) }
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value { fail("Expected false", file: file, line: line) }
}
func XCTUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else { fail("Expected a value", file: file, line: line); throw TestFailure.missingValue }
    return value
}
enum TestFailure: Error { case missingValue }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("Expected error", file: file, line: line) } catch {}
}

@main struct TestMain {
    static func main() {
        let c = ChatTests(); let s = StatusTests(); let w = WireTests(); let d = DiscoveryTests()
        let tests: [(String, () throws -> Void)] = [
            ("Chat signals and unavailable controls", c.testChatSignalsDoNotMistakeMissingControlsForCompletion),
            ("Desktop sidebar signals and safe chat URLs", c.testDesktopSidebarStatusesAndSafeURLs),
            ("Sidebar remount identity and duplicate titles", c.testSidebarRemountKeepsIdentityOnlyWhenUnambiguous),
            ("Retire reclassified Code sidebar rows", c.testCodeSidebarRetirementDoesNotLeaveGrayDuplicates),
            ("Require confirmed Claude chat mode", c.testClaudeSidebarRequiresConfirmedChatMode),
            ("Async question cards and accepted replies", s.testAsyncQuestionCardsAreOrangeUntilAcceptedReply),
            ("Codex waiting flags and completion", s.testCodexRuntimeFlagsOverrideRunningAndClearWhenResolved),
            ("Pending question", s.testPendingQuestionIsOrangeEvenWithIdleRuntime),
            ("Disconnected runtime", s.testDisconnectedOrMissingRuntimeIsNotFinished),
            ("Claude statuses", s.testClaudeExplicitStatuses),
            ("Status alerts and dismissal", s.testOnlyStatusChangesAlertAndDismissedSessionCanRunAgain),
            ("Uncertainty alert suppression", s.testMonitorUncertaintyDoesNotCreateCompletionAlert),
            ("Fragmented IPC frames", w.testFragmentedHeaderBodyAndMultipleFrames),
            ("Invalid frame", w.testInvalidFrameLengthThrows),
            ("Frame encode", w.testWireEncodeProducesReadableFrames),
            ("JSON patch arrays", w.testArrayInsertRemoveAndNestedReplacementPreserveOrdering),
            ("Invalid patch", w.testBadPatchDoesNotSilentlyInventState),
            ("Snapshot revision gap", w.testRevisionGapRequiresNewSnapshot),
            ("Claude waiting and process exit", d.testClaudeWaitingReasonAndDeadPID),
            ("Malformed Claude metadata", d.testMalformedClaudeRecordIsRejected),
            ("Codex discovery filtering", d.testDiscoveryExcludesArchivedSubagentsAndOldHistory),
            ("Plan implementation approval", s.testPlanImplementationApprovalIsOrange),
            ("Terminal response labels", s.testFailedAndInterruptedResponsesKeepAccurateLabels),
            ("Reconnect alert suppression", s.testUnchangedStateDoesNotAlertAfterSourceReconnects),
            ("Exclude Claude SDK helpers", d.testSDKHelperSessionsAreExcluded),
            ("Open exact Claude desktop session", d.testClaudeDesktopLinksOpenTheHostSessionWithoutImportingCLIHistory),
            ("Claude transcript links and invalid IDs", d.testClaudeTerminalLinksTargetExactTranscriptAndInvalidIDsAreRejected)
        ]
        for (name, body) in tests {
            let before = failures
            do { try body() } catch { failures += 1; print("FAIL \(name): \(error)") }
            if before == failures { print("PASS \(name)") }
        }
        print("\(tests.count) tests, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
