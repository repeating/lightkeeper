import Foundation

public enum SessionState: String, Codable {
    case running, needsInput, finished, unknown
    public var label: String {
        switch self { case .running: return "Running"; case .needsInput: return "Needs you"; case .finished: return "Finished"; case .unknown: return "Unavailable" }
    }
}

public struct Session: Identifiable, Equatable {
    public var id: String
    public var source: String
    public var title: String
    public var state: SessionState
    public var detail: String
    public var updatedAt: Date
    public var openURL: URL?
    public var openAppBundleID: String?
    public var openAccessibilityLabel: String?
    public init(id: String, source: String, title: String, state: SessionState, detail: String, updatedAt: Date = Date(), openURL: URL? = nil, openAppBundleID: String? = nil, openAccessibilityLabel: String? = nil) {
        self.id = id; self.source = source; self.title = title; self.state = state; self.detail = detail; self.updatedAt = updatedAt
        self.openURL = openURL
        self.openAppBundleID = openAppBundleID; self.openAccessibilityLabel = openAccessibilityLabel
    }
}

public enum SessionLink {
    public static func claude(sessionID: String, hostSessionID: String?) -> URL? {
        var link = URLComponents()
        link.scheme = "claude"
        if let host = hostSessionID, host.hasPrefix("local_"), UUID(uuidString: String(host.dropFirst(6))) != nil {
            link.host = "code"; link.path = "/continue"
            link.queryItems = [URLQueryItem(name: "session", value: host)]
        } else {
            guard UUID(uuidString: sessionID) != nil else { return nil }
            link.host = "resume"
            link.queryItems = [URLQueryItem(name: "session", value: sessionID)]
        }
        return link.url
    }
    public static func codex(sessionID: String) -> URL? {
        guard UUID(uuidString: sessionID) != nil else { return nil }
        var link = URLComponents()
        link.scheme = "codex"; link.host = "threads"; link.path = "/" + sessionID
        return link.url
    }
}

public enum StatusDecoder {
    public static func codexDetail(_ snapshot: [String: Any], terminalStatus: String? = nil) -> String {
        let state = codex(snapshot)
        switch state {
        case .running: return "Running"
        case .needsInput:
            let requests = snapshot["requests"] as? [[String: Any]] ?? []
            if requests.contains(where: { $0["method"] as? String == "item/plan/requestImplementation" }) { return "Plan approval requested" }
            let flags = (snapshot["threadRuntimeStatus"] as? [String: Any])?["activeFlags"] as? [String] ?? []
            return flags.contains("waitingOnApproval") ? "Approval requested" : "Needs your answer"
        case .unknown: return "Status unavailable"
        case .finished:
            let turns = snapshot["turns"] as? [[String: Any]] ?? []
            switch terminalStatus ?? (turns.last?["status"] as? String) {
            case "failed": return "Failed"
            case "interrupted": return "Interrupted"
            default:
                return (snapshot["threadRuntimeStatus"] as? [String: Any])?["type"] as? String == "systemError" ? "Ended with an error" : "Finished"
            }
        }
    }
    public static func hasUnansweredAsyncQuestion(_ snapshot: [String: Any]) -> Bool {
        let turns = snapshot["turns"] as? [[String: Any]] ?? []
        var pending = Set<String>()
        for (turnIndex, turn) in turns.enumerated() {
            for item in turn["items"] as? [[String: Any]] ?? [] {
                if item["type"] as? String == "agentMessage", let id = item["id"] as? String,
                   turnIndex == turns.count - 1, turn["status"] as? String == "inProgress" {
                    for (index, _) in (item["questions"] as? [[String: Any]] ?? []).enumerated() {
                        pending.insert(id + ":" + String(index))
                    }
                }
                let type = item["type"] as? String
                guard type == "userMessage" || (type == "steeringUserMessage" && item["status"] as? String == "accepted") else { continue }
                for content in (item["content"] ?? item["input"]) as? [[String: Any]] ?? [] {
                    guard content["type"] as? String == "text", let text = content["text"] as? String,
                          let start = text.range(of: "<send_user_message_question_reply>"),
                          let end = text.range(of: "</send_user_message_question_reply>", range: start.upperBound..<text.endIndex),
                          let data = String(text[start.upperBound..<end.lowerBound]).data(using: .utf8),
                          let decoded = try? JSONSerialization.jsonObject(with: data) else { continue }
                    let replies = decoded as? [[String: Any]] ?? (decoded as? [String: Any]).map { [$0] } ?? []
                    for reply in replies {
                        guard let key = reply["questionItemId"] as? String, let keyData = key.data(using: .utf8),
                              let parts = try? JSONSerialization.jsonObject(with: keyData) as? [Any],
                              parts.count == 3, parts[0] as? String == "request_user_input_async",
                              let id = parts[1] as? String, let index = parts[2] as? Int else { continue }
                        pending.remove(id + ":" + String(index))
                    }
                }
            }
        }
        return !pending.isEmpty
    }
    public static func codex(_ snapshot: [String: Any]) -> SessionState {
        if hasUnansweredAsyncQuestion(snapshot) { return .needsInput }
        let requests = snapshot["requests"] as? [[String: Any]] ?? []
        let waitingMethods: Set<String> = [
            "item/commandExecution/requestApproval", "item/fileChange/requestApproval",
            "item/permissions/requestApproval", "item/tool/requestUserInput",
            "item/tool/requestOptionPicker", "mcpServer/elicitation/request",
            "execCommandApproval", "applyPatchApproval", "item/plan/requestImplementation"
        ]
        if requests.contains(where: { waitingMethods.contains($0["method"] as? String ?? "") }) { return .needsInput }
        guard let runtime = snapshot["threadRuntimeStatus"] as? [String: Any], let type = runtime["type"] as? String else { return .unknown }
        let flags = runtime["activeFlags"] as? [String] ?? []
        if flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput") { return .needsInput }
        switch type {
        case "active": return .running
        case "idle", "systemError": return .finished
        default: return .unknown
        }
    }
    public static func claude(_ status: String) -> SessionState {
        switch status {
        case "busy": return .running
        case "waiting": return .needsInput
        case "idle", "shell": return .finished
        default: return .unknown
        }
    }
}

public struct SessionLedger {
    public private(set) var sessions: [String: Session] = [:]
    private var dismissed: Set<String> = []
    private var lastKnownStates: [String: SessionState] = [:]
    public init() {}
    public mutating func update(_ session: Session, initial: Bool = false) -> Bool {
        if dismissed.contains(session.id) {
            guard session.state == .running || session.state == .needsInput else { return false }
            dismissed.remove(session.id)
        }
        let previous = sessions[session.id]
        let previousKnownState = lastKnownStates[session.id]
        var row = session
        if previous?.state == row.state { row.updatedAt = previous!.updatedAt }
        sessions[row.id] = row
        if row.state != .unknown { lastKnownStates[row.id] = row.state }
        return !initial && row.state != .unknown && previousKnownState != row.state
    }
    public mutating func dismiss(_ id: String) {
        guard sessions[id]?.state == .finished else { return }
        dismissed.insert(id); sessions.removeValue(forKey: id)
    }
    public mutating func remove(_ id: String) {
        sessions.removeValue(forKey: id)
        dismissed.remove(id); lastKnownStates.removeValue(forKey: id)
    }
    public mutating func markSourceDisconnected(_ source: String) {
        for (id, var row) in sessions where row.source == source {
            row.state = .unknown; row.detail = "Connection unavailable"; sessions[id] = row
        }
    }
}
