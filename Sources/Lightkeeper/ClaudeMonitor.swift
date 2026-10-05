import Foundation
import BeaconCore

final class ClaudeMonitor {
    var onSession: ((Session, Bool) -> Void)?
    var onConnection: ((Bool, String) -> Void)?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "beacon.claude", qos: .utility)
    private var known: [String: Session] = [:]
    private var firstScan = true
    private let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.scan() }
        self.timer = timer; timer.resume()
    }
    private func scan() {
        let directory = home.appendingPathComponent(".claude/sessions")
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            var current: [String: Session] = [:]
            var unreadable = false
            var unsupported = false
            for file in files where file.pathExtension == "json" && Int32(file.deletingPathExtension().lastPathComponent) != nil {
                do {
                    let data = try Data(contentsOf: file)
                    if let record = try ClaudeRecord.parse(data) {
                        let row = record.session
                        unsupported = unsupported || row.state == .unknown
                        current[row.id] = row
                        let initial = firstScan
                        DispatchQueue.main.async { self.onSession?(row, initial) }
                    }
                } catch {
                    // A registry writer may be replacing a file. Keep prior states
                    // rather than treating this transient read as a process exit.
                    unreadable = true
                }
            }
            if !unreadable {
                for (id, var row) in known where current[id] == nil {
                    row.state = .finished; row.detail = "Session ended"; row.updatedAt = Date()
                    DispatchQueue.main.async { self.onSession?(row, false) }
                }
                known = current
            } else { known.merge(current) { _, new in new } }
            let detail = unreadable ? "Claude registry updating" : unsupported ? "Claude has an unsupported status" : "Claude Code connected"
            DispatchQueue.main.async { self.onConnection?(!unreadable && !unsupported, detail) }
            firstScan = false
        } catch {
            DispatchQueue.main.async { self.onConnection?(false, "Open Claude Code to connect") }
        }
    }
}
