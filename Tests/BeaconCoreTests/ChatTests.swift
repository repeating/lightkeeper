import Foundation
import BeaconCore

final class ChatTests: XCTestCase {
    func testChatSignalsDoNotMistakeMissingControlsForCompletion() {
        XCTAssertEqual(ChatStatus.state(running: true, needsInput: true, composerPresent: true), .needsInput)
        XCTAssertEqual(ChatStatus.state(running: true, needsInput: false, composerPresent: true), .running)
        XCTAssertEqual(ChatStatus.state(running: false, needsInput: false, composerPresent: false), .unknown)
        XCTAssertEqual(ChatStatus.state(running: false, needsInput: false, composerPresent: true), .finished)
    }
    func testDesktopSidebarStatusesAndSafeURLs() {
        XCTAssertEqual(ChatStatus.sidebar(source: "Claude", label: "Running Design icon")?.0, "Design icon")
        XCTAssertEqual(ChatStatus.sidebar(source: "Claude", label: "Idle Previous chat")?.1, .finished)
        XCTAssertEqual(ChatStatus.sidebar(source: "ChatGPT", label: "Plan holiday, Needs input")?.1, .needsInput)
        XCTAssertEqual(ChatStatus.webURL("https://claude.ai/chat/abc?secret=hidden")?.absoluteString, "https://claude.ai/chat/abc")
        XCTAssertEqual(ChatStatus.webURL("https://claude.ai.evil.test/chat/a"), nil)
        XCTAssertEqual(ChatStatus.webURL("http://chatgpt.com/c/a"), nil)
        XCTAssertEqual(ChatStatus.webURL("https://user:secret@chatgpt.com/c/a"), nil)
    }
    func testSidebarRemountKeepsIdentityOnlyWhenUnambiguous() {
        let running = Session(id: "tracked", source: "Claude", title: "Landing page", state: .running, detail: "Running")
        XCTAssertEqual(ChatStatus.sidebarSessionID(title: "Landing page", visibleTitles: ["Landing page"], candidates: [running]), "tracked")
        XCTAssertEqual(ChatStatus.sidebarSessionID(title: "Landing page", visibleTitles: ["Landing page", "Landing page"], candidates: [running]), nil)
        var duplicate = running; duplicate.id = "another"
        XCTAssertEqual(ChatStatus.sidebarSessionID(title: "Landing page", visibleTitles: ["Landing page"], candidates: [running, duplicate]), nil)
        XCTAssertEqual(ChatStatus.sidebarSessionID(title: "Unrelated", visibleTitles: ["Unrelated"], candidates: [running]), nil)
    }

    func testCodeSidebarRetirementDoesNotLeaveGrayDuplicates() {
        let duplicate = Session(id: "desktop:Claude:code", source: "Claude", title: "Website launch", state: .running, detail: "Running")
        let chat = Session(id: "desktop:Claude:chat", source: "Claude", title: "Holiday plan", state: .running, detail: "Running")
        let current = ChatStatus.desktopHistory(previous: [duplicate.id: duplicate, chat.id: chat], observed: [:], excluding: [duplicate.id])
        XCTAssertEqual(Set(current.keys), Set([chat.id]))
        XCTAssertEqual(current[chat.id]?.state, .unknown)
        // A control reclassified during a scan must not reintroduce the retired row.
        XCTAssertEqual(ChatStatus.desktopHistory(previous: [:], observed: [duplicate.id: duplicate], excluding: [duplicate.id]).count, 0)
    }
    func testClaudeSidebarRequiresConfirmedChatMode() {
        XCTAssertTrue(ChatStatus.claudeChatMode(chatSelected: true, codeSelected: false, url: "https://claude.ai/chat/a"))
        XCTAssertFalse(ChatStatus.claudeChatMode(chatSelected: false, codeSelected: false, url: nil))
        XCTAssertFalse(ChatStatus.claudeChatMode(chatSelected: true, codeSelected: true, url: nil))
        XCTAssertFalse(ChatStatus.claudeChatMode(chatSelected: true, codeSelected: false, url: "https://claude.ai/epitaxy/local_test"))
        XCTAssertTrue(ChatStatus.claudeChatMode(chatSelected: false, codeSelected: false, url: "https://claude.ai/cowork/cse_test"))
    }

}
