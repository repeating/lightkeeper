import AppKit
import BeaconCore

@MainActor func runWindowSelfTest(_ app: AppDelegate) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        app.model.collapsed = true; app.resize(); app.hidePanel()
        let wasHidden = !app.panel.isVisible && NSApp.activationPolicy() == .regular
        app.model.accept(Session(id: "demo-codex", source: "Codex", title: "Build the onboarding screen", state: .needsInput, detail: "Needs your answer"))
        let reopened = app.panel.isVisible && !app.model.collapsed
        let focusPreserved = before == NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        app.hidePanel()
        _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        let report: [String: Bool] = ["hidePreservesDock": wasHidden, "statusReopensAndExpands": reopened, "focusPreserved": focusPreserved,
                                    "dockReopens": app.panel.isVisible, "floating": app.panel.level == .floating,
                                    "allSpaces": app.panel.collectionBehavior.contains(.canJoinAllSpaces)]
        let output = ProcessInfo.processInfo.environment["BEACON_UI_REPORT"] ?? ".build/window-test-report.json"
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: output))
            print(String(data: data, encoding: .utf8)!)
        } catch { print("FAIL: \(error)"); exit(1) }
        exit(report.values.allSatisfy { $0 } ? 0 : 1)
    }
}
