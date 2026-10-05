import Foundation
import BeaconCore

@main struct Probe {
    static func main() {
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BEACON_TEST_HOME"]!)
        let codex = CodexMonitor(home: home)
        let claude = ClaudeMonitor(home: home)
        func emit(_ object: [String: Any]) {
            let data = try! JSONSerialization.data(withJSONObject: object)
            print(String(data: data, encoding: .utf8)!); fflush(stdout)
        }
        codex.onSession = { row, _ in emit(["source": "Codex", "state": row.state.rawValue, "detail": row.detail]) }
        codex.onConnection = { connected, detail in emit(["source": "Codex", "connected": connected, "detail": detail]) }
        claude.onSession = { row, _ in emit(["source": "Claude", "state": row.state.rawValue, "detail": row.detail]) }
        claude.onConnection = { _, _ in }
        codex.start(); claude.start()
        RunLoop.main.run(until: Date().addingTimeInterval(18))
    }
}
