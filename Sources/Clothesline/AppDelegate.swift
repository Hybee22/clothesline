import AppKit
import ServiceManagement
import SwiftUI

/// Commands other processes can send with `Clothesline --cmd <name>` (used for testing and scripting).
let commandNotification = Notification.Name(
    "dev.ibrahim.clothesline.cmd" + (ProcessInfo.processInfo.environment["CLOTHESLINE_DATA"] == nil ? "" : ".dev"))

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = Store()
    var watcher: Watcher!
    var line: LineController!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    let hotKey = HotKey()
    private var pauseItem: NSMenuItem!
    private var showItem: NSMenuItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        store.load()
        line = LineController(store: store)
        line.openSettings = { [weak self] in self?.showSettings() }
        watcher = Watcher(store: store)
        watcher.onCapture = { [weak self] clip in self?.line.capture(clip) }
        Paster.watcher = watcher
        watcher.start()

        setUpStatusItem()
        HotKey.handler = { [weak self] in self?.line.toggleKeyboard() }
        hotKey.register(Prefs.shared.shortcut)
        Prefs.shared.onShortcutChange = { [weak self] in
            guard let self else { return }
            self.hotKey.register(Prefs.shared.shortcut)
            self.showItem.title = "Show Line  \(Prefs.shared.shortcut.label)"
        }

        DistributedNotificationCenter.default().addObserver(forName: commandNotification, object: nil, queue: .main) { [weak self] note in
            let cmd = note.object as? String ?? ""
            MainActor.assumeIsolated { self?.run(command: cmd) }
        }

        if ProcessInfo.processInfo.environment["CLOTHESLINE_DEMO"] != nil && store.clips.isEmpty { Demo.seed(store) }

        if !Prefs.shared.onboarded {
            Prefs.shared.onboarded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.line.show(peekFor: 3.5)
                self?.line.showToast("Rest the pointer at the top edge of the screen, or press \(Prefs.shared.shortcut.label)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { store.saveNow() }

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where u.scheme == "clothesline" { run(command: u.host ?? "show") }
    }

    private func run(command: String) {
        switch command {
        case "show": line.show()
        case "keyboard": line.show(keyboard: true)
        case "hide": line.hide()
        case "search": line.setDrawer(true)
        case "settings": showSettings()
        case "next-line": line.cycleLine(1)
        case "demo-capture": line.capture(Demo.random(store))
        case "scroll": line.scrollBy(400)
        // Used when testing without a mouse.
        case "demo-delete": if let c = line.visible.first { line.delete(c) }
        case "demo-pick": for c in line.visible.prefix(3) { line.togglePick(c.id) }
        case "demo-preview": line.pinnedPreview = line.pinnedPreview == nil ? line.visible.dropFirst().first?.id : nil
        case "undo": line.undoDelete()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIcon.make()
        statusItem.button?.toolTip = "Clothesline"
        let menu = NSMenu()
        menu.delegate = self
        showItem = menu.addItem(withTitle: "Show Line  \(Prefs.shared.shortcut.label)", action: #selector(showLine), keyEquivalent: "")
        menu.addItem(withTitle: "Search the Basket…", action: #selector(searchBasket), keyEquivalent: "")
        menu.addItem(.separator())
        pauseItem = menu.addItem(withTitle: "Pause Capturing", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Clothesline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.state = Prefs.shared.paused ? .on : .off
        pauseItem.title = Prefs.shared.paused ? "Capturing Paused" : "Pause Capturing"
    }

    @objc private func showLine() { line.show(keyboard: true) }
    @objc private func searchBasket() { line.setDrawer(true) }
    @objc private func togglePause() {
        Prefs.shared.paused.toggle()
        statusItem.button?.appearsDisabled = Prefs.shared.paused
    }
    @objc private func openSettingsAction() { showSettings() }

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            w.title = "Clothesline Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
enum StatusIcon {
    static func make() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let rope = NSBezierPath()
            rope.move(to: NSPoint(x: 1, y: 3))
            rope.curve(to: NSPoint(x: 19, y: 3), controlPoint1: NSPoint(x: 6, y: 7), controlPoint2: NSPoint(x: 14, y: 7))
            rope.lineWidth = 1.4
            rope.stroke()
            // Two little cards on pegs
            NSBezierPath(roundedRect: NSRect(x: 4, y: 6.2, width: 5, height: 7), xRadius: 1.2, yRadius: 1.2).fill()
            NSBezierPath(roundedRect: NSRect(x: 11, y: 6.2, width: 5, height: 8.5), xRadius: 1.2, yRadius: 1.2).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - Settings

struct SettingsView: View {
    let store: Store
    @Bindable private var prefs = Prefs.shared
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var trusted = Paster.canAutoPaste
    @State private var newLine = ""
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Capturing") {
                Toggle("Pause capturing", isOn: $prefs.paused)
                LabeledContent("Skipped apps") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(prefs.ignoredApps, id: \.self) { id in
                            HStack(spacing: 6) {
                                if let icon = AppIcons.icon(id) { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                                Text(AppIcons.name(id) ?? id).foregroundStyle(AppIcons.name(id) == nil ? .secondary : .primary)
                                Button { prefs.ignoredApps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle.fill") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12))
                        }
                        Button("Add App…", action: addApp).controlSize(.small)
                    }
                }
                Text("Anything a password manager marks as hidden is never captured, whichever app it comes from.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Secrets") {
                Picker("Remove secret-looking clips", selection: $prefs.secretMinutes) {
                    Text("After 1 minute").tag(1)
                    Text("After 2 minutes").tag(2)
                    Text("After 5 minutes").tag(5)
                    Text("After 15 minutes").tag(15)
                    Text("Never (keep them masked)").tag(0)
                }
                Text("API keys, tokens, private keys and passwords in connection strings are masked on their cards. When they're removed, they're also cleared from the clipboard if still there. Hang one on a line to keep it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("The line") {
                Toggle("Rest the pointer at the top edge to show the line", isOn: $prefs.revealOnEdge)
                Toggle("Peek down when something new is copied", isOn: $prefs.peekOnCopy)
                Toggle("Peg sound when a clip is hung", isOn: $prefs.pegSound)
                Picker("Keyboard shortcut", selection: $prefs.shortcut) {
                    ForEach(Shortcut.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Clips on the Inbox line: \(prefs.inboxCapacity)", value: $prefs.inboxCapacity, in: 6...40)
                Stepper("Keep history: \(prefs.historyLimit) clips", value: $prefs.historyLimit, in: 50...2000, step: 50)
            }
            Section("Lines") {
                ForEach(store.lines) { l in
                    HStack {
                        Circle().fill(Color(hue: l.hue, saturation: 0.55, brightness: 0.95)).frame(width: 10, height: 10)
                        Text(l.name)
                        Spacer()
                        Text("\(store.count(on: l.id)) clips").foregroundStyle(.secondary).font(.caption)
                        Button(role: .destructive) { store.deleteLine(l.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("New line name", text: $newLine).onSubmit(addLine)
                    Button("Add", action: addLine).disabled(newLine.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Pasting") {
                Toggle("Double-click or Return pastes into the app in front", isOn: $prefs.autoPaste)
                if prefs.autoPaste && !trusted {
                    HStack {
                        Text("Needs Accessibility permission. Until then, clips are only copied.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow…") {
                            Paster.requestAccessibility()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                } else if prefs.autoPaste {
                    Label("Accessibility allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                }
            }
            Section("General") {
                Toggle("Open at login", isOn: $loginItem)
                    .onChange(of: loginItem) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch { loginItem = SMAppService.mainApp.status == .enabled }
                    }
                HStack {
                    Button("Show Data Folder") { NSWorkspace.shared.open(store.dir) }
                    Spacer()
                    Button("Empty Basket", role: .destructive) { store.clearBasket() }
                        .disabled(store.basketCount == 0)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 720)
        .onReceive(timer) { _ in trusted = Paster.canAutoPaste }
    }

    private func addLine() {
        let n = newLine.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        store.addLine(named: n)
        newLine = ""
    }

    private func addApp() {
        let p = NSOpenPanel()
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowedContentTypes = [.application]
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for u in p.urls {
            if let id = Bundle(url: u)?.bundleIdentifier, !prefs.ignoredApps.contains(id) { prefs.ignoredApps.append(id) }
        }
    }
}

// MARK: - Demo content (CLOTHESLINE_DEMO=1 with an empty CLOTHESLINE_DATA folder)

@MainActor
enum Demo {
    static func seed(_ store: Store) {
        let work = store.lines.first?.id
        let snippets = store.lines.dropFirst().first?.id
        let items: [(Clip, UUID?)] = [
            (Capture.text("git rebase -i origin/main && git push --force-with-lease", source: "com.apple.Terminal"), snippets),
            (Capture.text("https://github.com/swiftlang/swift/pulls", source: "com.apple.Safari"), work),
            (Capture.text("Hey team, the release notes are in the doc. Ship it after the smoke test passes on staging.", source: "com.tinyspeck.slackmacgap"), nil),
            (Capture.text("#FF7A59", source: "com.figma.Desktop"), nil),
            (Capture.text("const line = await clothesline.hang(clip, { peg: \"wood\" });\nline.sway();", source: "com.microsoft.VSCode"), nil),
            (Clip(kind: .files, paths: ["/System/Library/CoreServices/Finder.app"], sourceBundleID: "com.apple.finder", hash: "demo-files"), nil),
            (Capture.text("https://developer.apple.com/documentation/swiftui/animation", source: "com.apple.Safari"), nil),
            (Capture.text("#5B8DEF", source: "com.figma.Desktop"), snippets),
            (Capture.text("Meeting moved to Thursday 3pm. Bring the dmg build.", source: "com.apple.Notes"), nil),
            (Capture.text("DATABASE_URL=postgres://app:demo-only-password@localhost:5432/clothesline", source: "com.apple.Terminal"), nil),
        ]
        if let img = gradientImage(), let clip = Capture.image(img, source: "com.apple.Preview", store: store) {
            store.add(clip)
        }
        for (clip, line) in items.reversed() {
            let c = store.add(clip)
            if let line { store.hang(c.id, on: line) }
        }
    }

    static func random(_ store: Store) -> Clip {
        let samples = [
            "Remember to rotate the staging keys on Friday.",
            "https://www.apple.com/macos/",
            "#34C759",
            "SELECT id, email FROM users WHERE created_at > now() - interval '7 days';",
            "Thanks! Sounds good, see you then.",
        ]
        var c = Capture.text(samples.randomElement()!, source: "com.apple.Notes")
        c.hash += UUID().uuidString
        return c
    }

    private static func gradientImage() -> Data? {
        let size = NSSize(width: 800, height: 520)
        let img = NSImage(size: size, flipped: false) { r in
            NSGradient(colors: [NSColor.systemIndigo, NSColor.systemPink, NSColor.systemOrange])?.draw(in: r, angle: 35)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 560, y: 320, width: 120, height: 120)).fill()
            NSColor.black.withAlphaComponent(0.25).setFill()
            let hills = NSBezierPath()
            hills.move(to: .zero)
            hills.curve(to: NSPoint(x: 800, y: 60), controlPoint1: NSPoint(x: 250, y: 260), controlPoint2: NSPoint(x: 520, y: -40))
            hills.line(to: NSPoint(x: 800, y: 0))
            hills.fill()
            return true
        }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
