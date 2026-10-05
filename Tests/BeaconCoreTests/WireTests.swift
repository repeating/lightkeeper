import Foundation
import BeaconCore

final class WireTests: XCTestCase {
    func testFragmentedHeaderBodyAndMultipleFrames() throws {
        // Hand-encoded {"a":1} with a seven-byte little-endian frame length.
        let bytes = Data([7, 0, 0, 0, 123, 34, 97, 34, 58, 49, 125])
        var decoder = FrameDecoder()
        XCTAssertTrue(try decoder.append(bytes.prefix(2)).isEmpty)
        XCTAssertTrue(try decoder.append(bytes.subdata(in: 2..<8)).isEmpty)
        let messages = try decoder.append(bytes.suffix(3) + bytes)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["a"] as? Int, 1)
    }
    func testInvalidFrameLengthThrows() {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 0])))
    }
    func testWireEncodeProducesReadableFrames() throws {
        var decoder = FrameDecoder()
        let messages = try decoder.append(FrameDecoder.encode(["method": "initialize"]))
        XCTAssertEqual(messages.first?["method"] as? String, "initialize")
    }
    func testArrayInsertRemoveAndNestedReplacementPreserveOrdering() throws {
        let start: [String: Any] = ["requests": [["id": "a"], ["id": "c"]], "runtime": ["flags": ["waitingOnApproval"]]]
        let patches: [[String: Any]] = [
            ["op": "add", "path": ["requests", 1], "value": ["id": "b"]],
            ["op": "remove", "path": ["requests", 0]],
            ["op": "replace", "path": ["runtime", "flags"], "value": []]
        ]
        let result = try XCTUnwrap(JSONPatch.apply(patches, to: start) as? [String: Any])
        XCTAssertEqual((result["requests"] as? [[String: String]])?.map { $0["id"]! }, ["b", "c"])
        XCTAssertEqual(((result["runtime"] as? [String: Any])?["flags"] as? [String])?.count, 0)
    }
    func testBadPatchDoesNotSilentlyInventState() {
        XCTAssertThrowsError(try JSONPatch.apply([["op": "remove", "path": ["missing"]]], to: ["present": 1]))
    }
    func testRevisionGapRequiresNewSnapshot() throws {
        var store = ConversationStore()
        _ = try store.apply(id: "s", change: ["type": "snapshot", "revision": 4, "conversationState": ["title": "Task"]])
        XCTAssertThrowsError(try store.apply(id: "s", change: ["type": "patches", "baseRevision": 3, "revision": 5, "patches": []]))
        let result = try store.apply(id: "s", change: ["type": "patches", "baseRevision": 4, "revision": 5, "patches": [["op": "replace", "path": ["title"], "value": "Updated"]]])
        XCTAssertEqual(result["title"] as? String, "Updated")
    }
}
