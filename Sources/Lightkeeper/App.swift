import AppKit
import SwiftUI
import BeaconCore

final class BeaconModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var collapsed = false
    @Published var codexConnected = false
    @Published var claudeConnected = false
    @Published var codexDetail = "Connecting to Codex…"
    @Published var claudeDetail = "Connecting to Claude Code…"
    @Published var desktopChatsConnected = false
    @Published var desktopChatsEnabled = DesktopChatMonitor.enabled
    @Published var desktopChatsAccessGranted = DesktopChatMonitor.accessGranted
    @Published var desktopChatsDetail = "Desktop chats off — use Setup"
    @Published var lastUpdate = "Watching your sessions"
    var onAlert: (() -> Void)?
    var onResize: (() -> Void)?
    var onHide: (() -> Void)?
    private var ledger = SessionLedger()
    private let codex = CodexMonitor()
    private let claude = ClaudeMonitor()
    private let desktopChats = DesktopChatMonitor()
    func refreshDesktopChatAccess() {
        desktopChatsEnabled = DesktopChatMonitor.enabled
        desktopChatsAccessGranted = DesktopChatMonitor.accessGranted
    }
    func enableDesktopChats() {
        DesktopChatMonitor.requestAccess()
        refreshDesktopChatAccess()
    }

    func start() {
        codex.onSession = { [weak self] in self?.accept($0, initial: $1) }
        claude.onSession = { [weak self] in self?.accept($0, initial: $1) }
        codex.onConnection = { [weak self] connected, detail in
            guard let self else { return }
            self.codexConnected = connected; self.codexDetail = detail
            if !connected { self.ledger.markSourceDisconnected("Codex"); self.publish() }
        }
        claude.onConnection = { [weak self] connected, detail in
            guard let self else { return }
            self.claudeConnected = connected; self.claudeDetail = detail
            // A temporary partial registry write should retain the known colors.
            if !connected && detail == "Open Claude Code to connect" { self.ledger.markSourceDisconnected("Claude Code"); self.publish() }
        }
        desktopChats.onSession = { [weak self] in self?.accept($0, initial: $1) }
        desktopChats.onConnection = { [weak self] ok, detail in
            self?.desktopChatsConnected = ok; self?.desktopChatsDetail = detail
            self?.refreshDesktopChatAccess()
        }
        codex.start(); claude.start(); desktopChats.start()
    }
    func accept(_ row: Session, initial: Bool = false) {
        let shouldAlert = ledger.update(row, initial: initial)
        publish()
        if shouldAlert {
            lastUpdate = "\(row.source): \(row.detail)"
            collapsed = false; onAlert?()
        }
    }
    func publish() {
        let priority: [SessionState: Int] = [.needsInput: 0, .running: 1, .unknown: 2, .finished: 3]
        sessions = ledger.sessions.values.sorted {
            if $0.state != $1.state { return priority[$0.state]! < priority[$1.state]! }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        onResize?()
    }
    func dismissFinished() {
        for row in sessions where row.state == .finished { ledger.dismiss(row.id) }
        publish()
    }
    func openSession(_ row: Session) {
        if row.openAppBundleID != nil {
            if desktopChats.open(row) { onHide?() }
            else { lastUpdate = "Open \(row.source) to locate this chat" }
            return
        }
        guard let url = row.openURL else { return }
        if NSWorkspace.shared.open(url) { onHide?() }
        else { lastUpdate = "Could not open this \(row.source) session" }
    }
    func dismiss(_ id: String) { ledger.dismiss(id); publish() }
    func toggleCollapsed() { collapsed.toggle(); onResize?() }
    func count(_ state: SessionState) -> Int { sessions.filter { $0.state == state }.count }
}

extension SessionState {
    var color: Color {
        switch self { case .running: return .green; case .needsInput: return .orange; case .finished: return .red; case .unknown: return .secondary }
    }
}

struct BeaconView: View {
    @ObservedObject var model: BeaconModel
    @State private var setupOpen = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lightkeeper").font(.system(size: 15, weight: .semibold))
                    Text(model.lastUpdate).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { model.toggleCollapsed() } label: {
                    Image(systemName: model.collapsed ? "chevron.down" : "chevron.up")
                        .frame(width: 22, height: 26)
                }.buttonStyle(.plain).help(model.collapsed ? "Expand sessions" : "Collapse sessions")
                Button { setupOpen.toggle() } label: {
                    Image(systemName: "gearshape").frame(width: 22, height: 26)
                }.buttonStyle(.plain).help("Set up desktop chats")
                    .popover(isPresented: $setupOpen) { setupView }
                Button("Hide") { model.onHide?() }.buttonStyle(.bordered).controlSize(.small).keyboardShortcut("h", modifiers: .command)
            }.padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 14)

            HStack(spacing: 13) {
                ForEach([SessionState.running, .needsInput, .finished], id: \.self) { state in
                    HStack(spacing: 5) {
                        Circle().fill(state.color).frame(width: 7, height: 7)
                        Text("\(model.count(state)) \(state.label)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 18).padding(.bottom, 13)

            if !model.collapsed {
                Divider().opacity(0.5)
                if model.sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkle").font(.system(size: 25)).foregroundStyle(.secondary)
                        Text("Ready when you are").font(.system(size: 13, weight: .medium))
                        Text("Start a Codex or Claude Code session.\nThis window will return when its status changes.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.sessions) { row in
                                SessionRow(session: row, open: { model.openSession(row) }, dismiss: { model.dismiss(row.id) })
                                if row.id != model.sessions.last?.id { Divider().padding(.leading, 42).opacity(0.4) }
                            }
                        }
                    }.frame(maxHeight: .infinity)
                }
            }

            Divider().opacity(0.5)
            HStack(spacing: 12) {
                connectionDot("Codex", connected: model.codexConnected, detail: model.codexDetail)
                connectionDot("Code", connected: model.claudeConnected, detail: model.claudeDetail)
                connectionDot("Chats", connected: model.desktopChatsConnected, detail: model.desktopChatsDetail)
                Spacer()
                if model.count(.finished) > 0 {
                    Button("Clear finished") { model.dismissFinished() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 18).padding(.vertical, 11)
            if !model.codexConnected || !model.claudeConnected {
                Text(!model.codexConnected ? model.codexDetail : model.claudeDetail)
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 18).padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
    private var setupView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chat monitoring").font(.headline)
            Text("Desktop: ChatGPT and Claude").font(.subheadline)
            Text("Reads chat activity controls. Enable Lightkeeper in macOS Accessibility settings. Hidden chats without an exposed status stay gray.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.desktopChatsEnabled {
                Button("Enable desktop chat monitoring") { model.enableDesktopChats() }
            } else if !model.desktopChatsAccessGranted {
                Text("Monitoring is enabled, but macOS has not authorized this copy of Lightkeeper.")
                    .font(.caption).foregroundStyle(.orange)
                Text("If its Accessibility switch is already on, remove the old entry for this app (it may still be named Session Beacon), then add this app again using the + button. Choose the app shown by Show this app, enable its switch, and reopen Lightkeeper.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open Accessibility settings") { DesktopChatMonitor.openAccessibilitySettings() }
                    Button("Show this app") { DesktopChatMonitor.showAppInFinder() }
                }
            } else {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            Text(model.desktopChatsDetail).font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Chat titles and status stay on this Mac. Messages and draft text are not collected.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 330)
    }
    private func connectionDot(_ title: String, connected: Bool, detail: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(connected ? Color.green.opacity(0.7) : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }.help(detail)
    }
}

struct SessionRow: View {
    var session: Session
    var open: () -> Void
    var dismiss: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Circle().fill(session.state.color).frame(width: 11, height: 11)
                        .shadow(color: session.state.color.opacity(0.25), radius: 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        HStack(spacing: 5) {
                            Text(session.source).foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                            Text(session.detail).foregroundStyle(session.state.color)
                        }.font(.system(size: 10)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if session.openURL != nil || session.openAppBundleID != nil {
                        Image(systemName: "arrow.up.forward").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(session.openURL == nil && session.openAppBundleID == nil)
                .help("Open this \(session.source) session")
                .accessibilityLabel("Open \(session.source) session: \(session.title), \(session.state.label)")
            if session.state == .finished {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9)).padding(4) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Dismiss finished session")
            }
        }.padding(.horizontal, 18).padding(.vertical, 13).frame(minHeight: 66)
    }
}

final class BeaconPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = BeaconModel()
    var panel: BeaconPanel!
    var demoTimer: Timer?
    var hidden = false
    var demo: Bool {
        #if BEACON_WINDOW_TEST
        return true
        #else
        return CommandLine.arguments.contains("--demo")
        #endif
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Beacon.icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        setupMenu()
        panel = BeaconPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Lightkeeper"
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: BeaconView(model: model))
        panel.delegate = self
        if let frame = UserDefaults.standard.string(forKey: "windowFrame") {
            panel.setFrame(NSRectFromString(frame), display: false)
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 400, y: screen.visibleFrame.maxY - 330))
        }
        model.onAlert = { [weak self] in self?.reveal(update: true) }
        model.onResize = { [weak self] in self?.resize() }
        model.onHide = { [weak self] in self?.hidePanel() }
        resize(); reveal(update: false)
        if demo { startDemo() } else { model.start() }
        #if BEACON_WINDOW_TEST
        runWindowSelfTest(self)
        #endif
    }
    func setupMenu() {
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "Show Lightkeeper", action: #selector(showPanel), keyEquivalent: "s").target = self
        appMenu.addItem(withTitle: "Hide Window", action: #selector(hidePanel), keyEquivalent: "h").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Lightkeeper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
    }
    @objc func hidePanel() { hidden = true; panel.orderOut(nil) }
    @objc func showPanel() { model.collapsed = false; reveal(update: false) }
    func reveal(update: Bool) {
        if update { model.collapsed = false }
        if hidden, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            let visible = screen.visibleFrame
            let origin = panel.frame.origin
            if !visible.contains(origin) {
                panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 20, y: visible.maxY - panel.frame.height - 20))
            }
        }
        hidden = false; resize(); panel.orderFrontRegardless()
    }
    func resize() {
        guard panel != nil else { return }
        let warning: CGFloat = (!model.codexConnected || !model.claudeConnected) ? 24 : 0
        let body: CGFloat = model.collapsed ? 0 : model.sessions.isEmpty ? 130 : min(390, CGFloat(model.sessions.count) * 72)
        let height = 136 + warning + body
        let old = panel.frame
        var next = NSRect(x: old.minX, y: old.maxY - height, width: 380, height: height)
        if let screen = panel.screen ?? NSScreen.main {
            next.origin.x = min(max(next.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - next.width)
            next.origin.y = min(max(next.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - next.height)
        }
        if next != old { panel.setFrame(next, display: true, animate: panel.isVisible) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hidePanel(); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowDidMove(_ notification: Notification) { UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "windowFrame") }

    func startDemo() {
        model.codexConnected = true; model.claudeConnected = true
        model.lastUpdate = "Demo — no real sessions"
        model.accept(Session(id: "demo-codex", source: "Codex", title: "Build the onboarding screen", state: .running, detail: "Running"), initial: true)
        model.accept(Session(id: "demo-claude", source: "Claude Code", title: "Review the booking flow", state: .needsInput, detail: "Approval requested"), initial: true)
        model.accept(Session(id: "demo-finished", source: "Codex", title: "Check the release notes", state: .finished, detail: "Finished"), initial: true)
        #if !BEACON_WINDOW_TEST
            var step = 0
            demoTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
                let states: [SessionState] = [.needsInput, .finished, .running]
                let state = states[step % 3]; step += 1
                DispatchQueue.main.async {
                    self?.model.accept(Session(id: "demo-codex", source: "Codex", title: "Build the onboarding screen", state: state, detail: state.label))
                }
            }
        #endif
    }
}

@main struct Entry {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            let codex = CodexMonitor(); let claude = ClaudeMonitor()
            var rows: [String: Session] = [:]
            var connections: [String: String] = [:]
            codex.onSession = { row, _ in rows[row.id] = row }
            claude.onSession = { row, _ in rows[row.id] = row }
            codex.onConnection = { _, detail in connections["Codex"] = detail }
            claude.onConnection = { _, detail in connections["Claude Code"] = detail }
            codex.start(); claude.start()
            RunLoop.main.run(until: Date().addingTimeInterval(6))
            let report: [String: Any] = ["connections": connections, "sessions": rows.values.sorted { $0.id < $1.id }.map { ["source": $0.source, "title": $0.title, "state": $0.state.rawValue, "detail": $0.detail] }]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
