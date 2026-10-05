import Foundation
import Darwin
import BeaconCore

final class CodexMonitor {
    var onSession: ((Session, Bool) -> Void)?
    var onConnection: ((Bool, String) -> Void)?
    private let queue = DispatchQueue(label: "beacon.codex", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var reader: DispatchSourceRead?
    private var fd: Int32 = -1
    private var clientID: String?
    private var decoder = FrameDecoder()
    private var store = ConversationStore()
    private var subscribed = Set<String>()
    private var tracked = Set<String>()
    private var started = Date()
    private var connectedAt = Date()
    private var lastDiscovery = Date.distantPast
    private var metadata: [String: CodexThread] = [:]
    private var owners: [String: String] = [:]
    private var lastRows: [String: Session] = [:]
    private var metadataUnavailable = false
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    func start() {
        queue.async {
            self.started = Date()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 2)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer; timer.resume()
        }
    }
    private func tick() {
        if fd < 0 { connect() }
        if fd >= 0 && clientID == nil && Date().timeIntervalSince(connectedAt) > 5 { disconnect("Codex connection timed out") }
        if clientID != nil && Date().timeIntervalSince(lastDiscovery) > 4 { discover() }
    }
    private func connect() {
        let path = home.appendingPathComponent(".codex/ipc/ipc.sock").path
        guard FileManager.default.fileExists(atPath: path) else { connection(false, "Open Codex to connect"); return }
        let socketFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { connection(false, "Cannot create Codex connection"); return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(socketFD); connection(false, "Codex socket path is too long"); return }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in pathBytes.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { Darwin.close(socketFD); connection(false, "Open Codex to connect"); return }
        var noSignal: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        guard fcntl(socketFD, F_SETFL, O_NONBLOCK) == 0 else { Darwin.close(socketFD); connection(false, "Cannot configure Codex connection"); return }
        fd = socketFD; connectedAt = Date(); decoder = FrameDecoder(); store.reset(); subscribed.removeAll()
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in self?.read() }
        source.setCancelHandler { Darwin.close(socketFD) }
        reader = source; source.resume()
        send(["type": "request", "requestId": UUID().uuidString, "sourceClientId": "uninitialized", "version": 1, "method": "initialize", "params": ["clientType": "session-beacon"], "timeoutMs": 3000])
    }
    private func read() {
        var bytes = [UInt8](repeating: 0, count: 65536)
        while fd >= 0 {
            let count = Darwin.recv(fd, &bytes, bytes.count, 0)
            if count == 0 { disconnect("Codex disconnected — reconnecting"); return }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                disconnect("Codex connection lost — reconnecting"); return
            }
            do { for message in try decoder.append(Data(bytes.prefix(count))) { handle(message) } }
            catch { disconnect("Codex sent an unsupported message — reconnecting"); return }
        }
    }
    private func handle(_ message: [String: Any]) {
        let type = message["type"] as? String
        if type == "response", message["method"] as? String == "initialize" {
            guard let result = message["result"] as? [String: Any], let id = result["clientId"] as? String else { disconnect("Codex rejected the monitor connection"); return }
            clientID = id; connection(true, "Codex connected"); discover(); return
        }
        if type == "client-discovery-request" {
            send(["type": "client-discovery-response", "requestId": message["requestId"] ?? "", "response": ["canHandle": false]])
            return
        }
        if type == "request" {
            send(["type": "response", "requestId": message["requestId"] ?? "", "resultType": "error", "error": "monitor-is-read-only"])
            return
        }
        guard type == "broadcast", let params = message["params"] as? [String: Any] else { return }
        if message["method"] as? String == "client-status-changed" {
            if params["status"] as? String == "disconnected", let owner = params["clientId"] as? String {
                for (id, value) in owners where value == owner {
                    owners.removeValue(forKey: id); subscribed.remove(id)
                    if var row = lastRows[id] {
                        row.state = .unknown; row.detail = "Session connection unavailable"
                        DispatchQueue.main.async { self.onSession?(row, false) }
                    }
                }
            }
            return
        }
        guard params["hostId"] as? String == "local" else { return }
        if message["method"] as? String == "thread-stream-following-status-requested" {
            if let id = params["conversationId"] as? String, metadata[id] != nil {
                subscribed.insert(id); follow(id)
            }
            return
        }
        if message["method"] as? String == "thread-stream-following-changed" {
            // A freshly opened conversation can be discovered before the next poll.
            if let id = params["conversationId"] as? String, !subscribed.contains(id) { discover() }
            return
        }
        guard message["method"] as? String == "thread-stream-state-changed",
              let id = params["conversationId"] as? String, metadata[id] != nil,
              let change = params["change"] as? [String: Any] else { return }
        do {
            let snapshot = try store.apply(id: id, change: change)
            if let owner = message["sourceClientId"] as? String { owners[id] = owner }
            let state = StatusDecoder.codex(snapshot)
            // Never add an archive of previously idle conversations on startup.
            guard state == .running || state == .needsInput || tracked.contains(id) else { return }
            let first = tracked.insert(id).inserted
            let terminalStatus = state == .finished ? try? CodexDiscovery.lastTurnStatus(historyDatabase: home.appendingPathComponent(".codex/thread_history_1.sqlite"), threadID: id) : nil
            let detail = StatusDecoder.codexDetail(snapshot, terminalStatus: terminalStatus)
            let title = snapshot["title"] as? String ?? metadata[id]?.title ?? "Codex session"
            let row = Session(id: "codex:\(id)", source: "Codex", title: title, state: state, detail: detail, openURL: SessionLink.codex(sessionID: id))
            lastRows[id] = row
            let initial = first && Date().timeIntervalSince(started) < 5
            DispatchQueue.main.async { self.onSession?(row, initial) }
        } catch {
            // Asking for following=true again forces an authoritative snapshot.
            follow(id)
        }
    }
    private func discover() {
        lastDiscovery = Date()
        do {
            let threads = try CodexDiscovery.threads(database: home.appendingPathComponent(".codex/state_5.sqlite"), since: Date().addingTimeInterval(-7 * 86400))
            let recovering = metadataUnavailable
            metadataUnavailable = false
            connection(true, "Codex connected")
            for thread in threads {
                metadata[thread.id] = thread
                if subscribed.insert(thread.id).inserted || recovering { follow(thread.id) }
            }
        } catch { metadataUnavailable = true; connection(false, "Codex metadata unavailable; check app compatibility") }
    }
    private func follow(_ id: String) {
        guard let clientID else { return }
        send(["type": "broadcast", "method": "thread-stream-following-changed", "sourceClientId": clientID, "version": 1,
              "params": ["conversationId": id, "hostId": "local", "following": true]])
    }
    private func send(_ message: [String: Any]) {
        guard fd >= 0 else { return }
        do {
            let data = try FrameDecoder.encode(message)
            var offset = 0
            while offset < data.count {
                let count = data.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!.advanced(by: offset), data.count - offset, 0) }
                guard count > 0 else { disconnect("Codex connection busy — reconnecting"); return }
                offset += count
            }
        } catch { disconnect("Cannot encode Codex subscription") }
    }
    private func disconnect(_ reason: String) {
        reader?.cancel(); reader = nil; fd = -1; clientID = nil
        store.reset(); subscribed.removeAll(); owners.removeAll(); connection(false, reason)
    }
    private func connection(_ connected: Bool, _ detail: String) {
        DispatchQueue.main.async { self.onConnection?(connected, detail) }
    }
}
