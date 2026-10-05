import Foundation

public enum WireError: Error { case invalidFrame, invalidPatch, revisionMismatch }
public struct FrameDecoder {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ bytes: Data) throws -> [[String: Any]] {
        buffer.append(bytes)
        var result: [[String: Any]] = []
        while buffer.count >= 4 {
            let size = buffer.prefix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            guard size > 0, size <= 64 * 1024 * 1024 else { throw WireError.invalidFrame }
            guard buffer.count >= size + 4 else { break }
            let body = buffer.subdata(in: 4..<(size + 4))
            guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw WireError.invalidFrame }
            result.append(object)
            buffer = Data(buffer.dropFirst(size + 4))
        }
        return result
    }
    public static func encode(_ message: [String: Any]) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: message)
        var size = UInt32(body.count).littleEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(body); return frame
    }
}

public enum JSONPatch {
    public static func apply(_ patches: [[String: Any]], to value: Any) throws -> Any {
        var result = value
        for patch in patches {
            guard let op = patch["op"] as? String, ["add", "replace", "remove"].contains(op), let path = patch["path"] as? [Any] else { throw WireError.invalidPatch }
            result = try modify(result, path: ArraySlice(path), op: op, value: patch["value"] ?? NSNull())
        }
        return result
    }
    private static func modify(_ node: Any, path: ArraySlice<Any>, op: String, value: Any) throws -> Any {
        guard let head = path.first else {
            guard op != "remove" else { throw WireError.invalidPatch }
            return value
        }
        let tail = path.dropFirst()
        if var object = node as? [String: Any], let key = head as? String {
            if tail.isEmpty {
                if op == "remove" { guard object.removeValue(forKey: key) != nil else { throw WireError.invalidPatch } }
                else { if op == "replace" && object[key] == nil { throw WireError.invalidPatch }; object[key] = value }
            } else {
                guard let child = object[key] else { throw WireError.invalidPatch }
                object[key] = try modify(child, path: tail, op: op, value: value)
            }
            return object
        }
        if var array = node as? [Any], let index = head as? Int {
            guard index >= 0 else { throw WireError.invalidPatch }
            if tail.isEmpty && op == "add" {
                guard index <= array.count else { throw WireError.invalidPatch }
                array.insert(value, at: index)
            } else {
                guard index < array.count else { throw WireError.invalidPatch }
                if tail.isEmpty && op == "remove" { array.remove(at: index) }
                else { array[index] = try modify(array[index], path: tail, op: op, value: value) }
            }
            return array
        }
        throw WireError.invalidPatch
    }
}

public struct ConversationStore {
    public private(set) var snapshots: [String: [String: Any]] = [:]
    private var revisions: [String: Int] = [:]
    public init() {}
    public mutating func apply(id: String, change: [String: Any]) throws -> [String: Any] {
        guard let revision = change["revision"] as? Int else { throw WireError.invalidPatch }
        let result: [String: Any]
        if change["type"] as? String == "snapshot", let snapshot = change["conversationState"] as? [String: Any] {
            result = snapshot
        } else {
            guard let current = snapshots[id], let base = change["baseRevision"] as? Int, base == revisions[id] else { throw WireError.revisionMismatch }
            guard revision > base, let patches = change["patches"] as? [[String: Any]], let next = try JSONPatch.apply(patches, to: current) as? [String: Any] else { throw WireError.invalidPatch }
            result = next
        }
        snapshots[id] = result; revisions[id] = revision; return result
    }
    public mutating func reset() { snapshots.removeAll(); revisions.removeAll() }
}
