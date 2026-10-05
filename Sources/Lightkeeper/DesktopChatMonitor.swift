import AppKit
import ApplicationServices
import BeaconCore

final class DesktopChatMonitor {
    var onSession: ((Session, Bool) -> Void)?
    var onConnection: ((Bool, String) -> Void)?
    private let queue = DispatchQueue(label: "beacon.desktop-chats", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var known: [String: Session] = [:]
    private var initial = true
    private var targets: [String: AXUIElement] = [:]
    static let enabledKey = "desktopChatMonitoringEnabled"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var accessGranted: Bool { AXIsProcessTrusted() }
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    static func showAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    static func requestAccess() {
        UserDefaults.standard.set(true, forKey: enabledKey)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in self?.scan() }
        self.timer = timer; timer.resume()
    }
    private func scan() {
        guard Self.enabled else { unavailable("Desktop chats off — use Setup"); return }
        guard Self.accessGranted else { unavailable("Desktop chats need Accessibility access"); return }
        let apps = NSWorkspace.shared.runningApplications.filter {
            ["com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex"].contains($0.bundleIdentifier ?? "")
        }
        var current: [String: Session] = [:]
        for app in apps {
            let source = app.bundleIdentifier == "com.anthropic.claudefordesktop" ? "Claude" : "ChatGPT"
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.25)
            for window in windows(root) {
                let controls = inspect(window, source: source)
                var sidebarRows: [Session] = []
                for (element, label, title, state) in controls.sidebar {
                    let prefix = "desktop:\(source):\(app.processIdentifier):\(CFHash(window)):"
                    let exactID = targets.first { $0.key.hasPrefix(prefix) && CFEqual($0.value, element) }?.key
                    let existingID = exactID ?? ChatStatus.sidebarSessionID(title: title,
                        visibleTitles: controls.sidebar.map { $0.2 },
                        candidates: known.values.filter { $0.id.hasPrefix(prefix) && current[$0.id] == nil })
                    if existingID == nil && state == .finished { continue }
                    let id = existingID ?? prefix + UUID().uuidString
                    targets[id] = element
                    let row = Session(id: id, source: source, title: title, state: state, detail: state.label,
                        openAppBundleID: app.bundleIdentifier, openAccessibilityLabel: label)
                    current[id] = row; sidebarRows.append(row)
                }
                if let url = controls.url, let safe = ChatStatus.webURL(url), safe.path.contains("/chat/") || safe.path.contains("/c/") || safe.path.contains("/cowork/") {
                    let title = controls.title.isEmpty ? "\(source) chat" : controls.title
                    // Never merge ambiguous titles; exact AX targets identify sidebar rows.
                    let matches = sidebarRows.filter { $0.title == title }
                    let id = matches.count == 1 ? matches[0].id : "desktop:\(source):\(app.processIdentifier):url:" + safe.absoluteString
                    let state = ChatStatus.state(running: controls.running, needsInput: controls.needsInput, composerPresent: controls.composer)
                    if matches.count != 1 && (state == .running || state == .needsInput || known[id] != nil) {
                        current[id] = Session(id: id, source: source, title: title, state: state, detail: state.label,
                            openURL: safe, openAppBundleID: app.bundleIdentifier)
                    }
                }
            }
        }
        for (id, var old) in known where current[id] == nil {
            old.state = .unknown; old.detail = "Status unavailable in \(old.source)"
            current[id] = old
        }
        for row in current.values {
            let first = initial
            DispatchQueue.main.async { self.onSession?(row, first) }
        }
        known = current; initial = false
        report(true, apps.isEmpty ? "Open ChatGPT or Claude desktop" : "Desktop chat controls connected")
    }
    private func unavailable(_ detail: String) {
        for (id, var row) in known where row.state != .unknown {
            row.state = .unknown; row.detail = detail; known[id] = row
            DispatchQueue.main.async { self.onSession?(row, false) }
        }
        report(false, detail)
    }
    private func report(_ ok: Bool, _ detail: String) { DispatchQueue.main.async { self.onConnection?(ok, detail) } }
    private struct Controls {
        var sidebar: [(AXUIElement, String, String, SessionState)] = []
        var running = false; var needsInput = false; var composer = false
        var url: String?; var title = ""; var codeSelected = false
    }
    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return "" }
        if let url = result as? URL { return url.absoluteString }
        return result as? String ?? ""
    }
    private func windows(_ element: AXUIElement) -> [AXUIElement] {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &result) == .success else { return [] }
        return result as? [AXUIElement] ?? []
    }
    private func children(_ element: AXUIElement) -> [AXUIElement] {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &result) == .success else { return [] }
        return result as? [AXUIElement] ?? []
    }
    private func inspect(_ root: AXUIElement, source: String) -> Controls {
        var result = Controls(); var budget = 1400
        func walk(_ element: AXUIElement, sidebar: Bool, dialog: Bool, depth: Int) {
            guard budget > 0, depth < 35 else { return }; budget -= 1
            let role = string(element, kAXRoleAttribute)
            if role == kAXTextAreaRole || role == kAXTextFieldRole {
                let hint = (string(element, kAXDescriptionAttribute) + " " + string(element, kAXTitleAttribute)).lowercased()
                if !sidebar && ["prompt", "message", "ask anything", "reply", "chat input"].contains(where: hint.contains) { result.composer = true }
                return
            }
            if role == kAXStaticTextRole { return } // Never read chat messages or draft text.
            let label = string(element, kAXDescriptionAttribute)
            let title = string(element, kAXTitleAttribute)
            if label == "Chat messages" || title == "Chat messages" || label.hasPrefix("Artifact panel") || title.hasPrefix("Artifact panel") || label.hasPrefix("Message ") || title.hasPrefix("Message ") { return }
            if role == kAXRadioButtonRole && label.hasPrefix("Code") {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success {
                    result.codeSelected = result.codeSelected || (value as? NSNumber)?.intValue == 1 || (value as? String) == "1"
                }
            }
            let inSidebar = sidebar || label == "Sidebar" || title == "Sidebar"
            let inDialog = dialog || string(element, kAXSubroleAttribute) == kAXDialogSubrole || label.lowercased().contains("approval")
            if source == "Claude" && role == "AXWebArea" && (title.hasSuffix(" - Claude Code") || label.hasSuffix(" - Claude Code")) {
                result.codeSelected = true
            }
            if role == "AXWebArea", result.url == nil {
                let url = string(element, "AXURL")
                if ChatStatus.webURL(url) != nil {
                    result.url = url
                    result.title = (title.isEmpty ? label : title).replacingOccurrences(of: " - Claude", with: "").replacingOccurrences(of: " - ChatGPT", with: "")
                }
            }
            if role == kAXButtonRole {
                let value = label.isEmpty ? title : label
                if inSidebar, let (name, state) = ChatStatus.sidebar(source: source, label: value) { result.sidebar.append((element, value, name, state)) }
                if !inSidebar {
                    if ["Stop", "Stop generating", "Stop response", "Stop streaming", "Stop generating response"].contains(value) { result.running = true }
                    if inDialog && ["Allow", "Allow once", "Approve", "Continue", "Send answers"].contains(value) { result.needsInput = true }
                }
            }
            for child in children(element) { walk(child, sidebar: inSidebar, dialog: inDialog, depth: depth + 1) }
        }
        walk(root, sidebar: false, dialog: false, depth: 0)
        if source == "Claude" && result.codeSelected { result.sidebar.removeAll() }
        return result
    }
    func open(_ row: Session) -> Bool {
        guard let bundle = row.openAppBundleID, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundle }) else { return false }
        if row.openAccessibilityLabel != nil {
            guard let button = queue.sync(execute: { targets[row.id] }),
                  string(button, kAXRoleAttribute) == kAXButtonRole else { return false }
            let description = string(button, kAXDescriptionAttribute)
            let label = description.isEmpty ? string(button, kAXTitleAttribute) : description
            guard ChatStatus.sidebar(source: row.source, label: label)?.0 == row.title,
                  AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { return false }
            app.activate(options: []); return true
        }
        if let url = row.openURL {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.25)
            for window in windows(root) {
                if inspect(window, source: row.source).url.flatMap(ChatStatus.webURL) == url {
                    _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    app.activate(options: []); return true
                }
            }
            if row.source == "Claude", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = "claude"
                if let link = components.url { return NSWorkspace.shared.open(link) }
            }
        }
        return false
    }
}
