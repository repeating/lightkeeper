import Foundation

public enum ChatStatus {
    public static func state(running: Bool, needsInput: Bool, composerPresent: Bool) -> SessionState {
        if needsInput { return .needsInput }
        if running { return .running }
        return composerPresent ? .finished : .unknown
    }
    public static func sidebar(source: String, label: String) -> (String, SessionState)? {
        if source == "Claude" {
            for (prefix, state) in [("Running ", SessionState.running), ("Needs input ", .needsInput), ("Waiting for approval ", .needsInput), ("Idle ", .finished), ("Mark as unread ", .finished)] {
                if label.hasPrefix(prefix), label.count > prefix.count { return (String(label.dropFirst(prefix.count)), state) }
            }
        } else {
            for (suffix, state) in [(", Active", SessionState.running), (", Working", .running), (", Starting", .running), (", Needs input", .needsInput), (", Completed", .finished), (", Failed", .finished), (", Stopped", .finished)] {
                if label.hasSuffix(suffix), label.count > suffix.count { return (String(label.dropLast(suffix.count)), state) }
            }
        }
        return nil
    }
    // A remounted accessibility control can represent the same conversation.
    // Reuse its identity only when neither the visible rows nor history are ambiguous.
    public static func sidebarSessionID(title: String, visibleTitles: [String], candidates: [Session]) -> String? {
        guard visibleTitles.filter({ $0 == title }).count == 1 else { return nil }
        let matches = candidates.filter { $0.title == title }
        return matches.count == 1 ? matches[0].id : nil
    }
    public static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", url.user == nil, url.password == nil,
              ["chatgpt.com", "chat.openai.com", "claude.ai"].contains(url.host?.lowercased() ?? "") else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil; components?.fragment = nil
        return components?.url
    }
}
