import AppKit
import SwiftUI

final class LinePanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: Layout.closedHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class LineHostingView: NSHostingView<LineRoot> {
    weak var controller: LineController?

    override func scrollWheel(with event: NSEvent) {
        guard let c = controller else { return super.scrollWheel(with: event) }
        let p = convert(event.locationInWindow, from: nil)
        // Inside the basket drawer, let its own scroll view have the event.
        let fromTop = isFlipped ? p.y : bounds.height - p.y
        if c.drawerOpen && fromTop > Layout.closedHeight { return super.scrollWheel(with: event) }
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        let delta = abs(dx) > abs(dy) ? -dx : -dy
        MainActor.assumeIsolated { c.scrollBy(delta * (event.hasPreciseScrollingDeltas ? 1 : 12)) }
    }
}

@Observable @MainActor
final class LineController {
    let store: Store
    let swing = Swing()
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored private(set) var panel: LinePanel!

    // What the line shows
    var shown = false
    var sag: CGFloat = Layout.restSag
    var currentLine: UUID = Store.inboxID
    var scroll: CGFloat = 0
    var width: CGFloat = 1400

    // Keyboard mode (opened with the shortcut)
    var keyboard = false
    var selection = 0

    // Basket drawer (search through everything)
    var drawerOpen = false
    var query = ""
    var drawerSelection = 0
    var focusSearch = 0

    var flashID: UUID?
    var toast: String?
    var renamingLine: UUID?
    var draggingClip: UUID?
    var hoveredCard: UUID?

    @ObservationIgnored private var edgeSince: Date?
    @ObservationIgnored private var outsideSince: Date?
    @ObservationIgnored private var peekUntil: Date?
    @ObservationIgnored private var releasedAt: Date?
    @ObservationIgnored private var hideWork: DispatchWorkItem?
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored private var screen: NSScreen?

    init(store: Store) {
        self.store = store
        panel = LinePanel()
        let host = LineHostingView(rootView: LineRoot(c: self))
        host.sizingOptions = []
        host.controller = self
        panel.contentView = host
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            return MainActor.assumeIsolated { self.handleKey(e) } ? nil : e
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.keyboard, self.renamingLine == nil else { return }
                self.hide()
            }
        }
    }

    var visible: [Clip] { store.clips(on: currentLine) }
    var isVisible: Bool { panel.isVisible }

    var drawerResults: [Clip] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return Array(store.clips.prefix(300)) }
        let words = q.split(separator: " ").map(String.init)
        return Array(store.clips.lazy.filter { c in
            let blob = c.searchBlob
            return words.allSatisfy { blob.contains($0) }
        }.prefix(300))
    }

    // MARK: Showing and hiding

    func show(keyboard kb: Bool = false, peekFor: TimeInterval? = nil) {
        hideWork?.cancel()
        hideWork = nil
        let wasUp = panel.isVisible && shown
        if !panel.isVisible {
            screen = screenUnderMouse()
            layoutPanel()
        }
        keyboard = kb
        if kb { selection = 0 }
        peekUntil = peekFor.map { Date().addingTimeInterval($0) }
        outsideSince = nil
        if !wasUp {
            shown = false
            sag = Layout.restSag + 46
            panel.orderFrontRegardless()
            DispatchQueue.main.async { [self] in
                withAnimation(.spring(response: 0.46, dampingFraction: 0.8)) { shown = true }
                withAnimation(.interpolatingSpring(stiffness: 70, damping: 5.5).delay(0.06)) { sag = Layout.restSag }
                swing.ripple(visible.prefix(12).map(\.id), strength: 1.5)
            }
        }
        if kb || drawerOpen { panel.makeKey() }
    }

    func hide() {
        guard panel.isVisible, hideWork == nil else { return }
        keyboard = false
        renamingLine = nil
        peekUntil = nil
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.hideWork = nil
            self.drawerOpen = false
            self.query = ""
            self.layoutPanel()
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: w)
    }

    func toggleKeyboard() {
        if panel.isVisible && shown && keyboard { hide() } else { show(keyboard: true) }
    }

    func toggleDrawer() {
        setDrawer(!drawerOpen)
    }

    func setDrawer(_ open: Bool) {
        guard open != drawerOpen else { return }
        if open {
            drawerSelection = 0
            if !panel.isVisible { show() }
            layoutPanel(drawer: true)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { drawerOpen = true }
            panel.makeKey()
            focusSearch += 1
        } else {
            withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
            query = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { [weak self] in
                guard let self, !self.drawerOpen else { return }
                self.layoutPanel()
            }
        }
    }

    private func screenUnderMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) || ($0.frame.minX...$0.frame.maxX).contains(p.x) && abs(p.y - $0.frame.maxY) < 3 }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func layoutPanel(drawer: Bool? = nil) {
        let s = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let h = Layout.closedHeight + ((drawer ?? drawerOpen) ? Layout.drawerHeight : 0)
        let top = s.visibleFrame.maxY
        let frame = NSRect(x: s.frame.minX, y: top - h, width: s.frame.width, height: h)
        panel.setFrame(frame, display: true)
        width = frame.width
        scroll = min(scroll, Layout.maxScroll(count: visible.count, width: width))
    }

    // MARK: Pointer tracking

    private func tick() {
        let p = NSEvent.mouseLocation
        let now = Date()
        let buttons = NSEvent.pressedMouseButtons
        if buttons == 0, draggingClip != nil {
            if let r = releasedAt, now.timeIntervalSince(r) > 0.8 { draggingClip = nil; releasedAt = nil }
            else if releasedAt == nil { releasedAt = now }
        } else { releasedAt = nil }

        if !panel.isVisible {
            guard Prefs.shared.revealOnEdge else { return }
            let s = screenUnderMouse()
            let atEdge = p.y >= s.frame.maxY - 1.5 && p.x > s.frame.minX + 4 && p.x < s.frame.maxX - 4
            if atEdge {
                if let t = edgeSince {
                    if now.timeIntervalSince(t) > 0.32 { edgeSince = nil; show() }
                } else { edgeSince = now }
            } else { edgeSince = nil }
            return
        }
        guard shown, hideWork == nil, !keyboard, renamingLine == nil else { return }
        var zone = panel.frame
        let screenTop = (screen ?? NSScreen.main)?.frame.maxY ?? zone.maxY
        zone.size.height = screenTop - zone.minY
        zone = zone.insetBy(dx: 0, dy: -18)
        let inside = NSMouseInRect(p, zone, false) || buttons != 0
        if inside {
            outsideSince = nil
            if p.y < screenTop - 6 { peekUntil = nil }
        } else if let until = peekUntil {
            if now > until { hide() }
        } else if drawerOpen && panel.isKeyWindow && !query.isEmpty {
            // Searching: stay until Esc or a click elsewhere.
        } else if let t = outsideSince {
            if now.timeIntervalSince(t) > 0.35 { hide() }
        } else {
            outsideSince = now
        }
    }

    // MARK: Actions

    func capture(_ clip: Clip) {
        let wasInbox = currentLine == Store.inboxID
        var added: Clip!
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            added = store.add(clip)
            if wasInbox { scroll = 0 }
        }
        if panel.isVisible && shown {
            if wasInbox { kickNewest(added.id) }
        } else if Prefs.shared.peekOnCopy && !panel.isVisible {
            currentLine = Store.inboxID
            scroll = 0
            show(peekFor: 1.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.kickNewest(added.id) }
        }
    }

    private func kickNewest(_ id: UUID) {
        swing.kick(id, 3.2)
        for (i, c) in visible.prefix(5).enumerated() where c.id != id {
            swing.kick(c.id, (i.isMultiple(of: 2) ? -1 : 1) * 0.9 / Double(i + 1))
        }
    }

    func copy(_ clip: Clip) {
        Paster.write(clip, store: store)
        flash(clip.id)
        swing.kick(clip.id, 1.1)
        if !keyboard { showToast("Copied") }
    }

    /// Copies, then pastes into the app in front if Accessibility allows it.
    func paste(_ clip: Clip) {
        Paster.write(clip, store: store)
        flash(clip.id)
        if Prefs.shared.autoPaste && Paster.canAutoPaste {
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { Paster.sendPaste() }
        } else {
            showToast(Prefs.shared.autoPaste ? "Copied · allow Accessibility to paste for you" : "Copied · press ⌘V")
            if keyboard { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.hide() } }
        }
    }

    func activate(_ clip: Clip) {
        if NSApp.currentEvent?.clickCount ?? 1 >= 2 { paste(clip) } else { copy(clip) }
    }

    func delete(_ clip: Clip) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { store.delete(clip.id) }
        selection = min(selection, max(0, visible.count - 1))
    }

    func hang(_ id: UUID, on line: UUID) {
        let name = line == Store.inboxID ? "Inbox" : (store.line(line)?.name ?? "line")
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { store.hang(id, on: line) }
        if line == currentLine { swing.kick(id, 2) }
        showToast("Hung on \(name)")
    }

    func select(line: UUID) {
        guard line != currentLine else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            currentLine = line
            scroll = 0
            selection = 0
        }
        swing.ripple(visible.prefix(10).map(\.id), strength: 1.2)
    }

    func cycleLine(_ step: Int) {
        let all = [Store.inboxID] + store.lines.map(\.id)
        let i = all.firstIndex(of: currentLine) ?? 0
        select(line: all[(i + step + all.count) % all.count])
    }

    func newLine() {
        let l = withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { store.addLine(named: "New line") }
        renamingLine = l.id
        panel.makeKey()
        select(line: l.id)
    }

    func deleteLine(_ id: UUID) {
        if currentLine == id { select(line: Store.inboxID) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { store.deleteLine(id) }
    }

    func scrollBy(_ d: CGFloat) {
        let maxS = Layout.maxScroll(count: visible.count, width: width)
        let old = scroll
        scroll = min(max(0, scroll + d), maxS)
        if abs(scroll - old) > 0.5 {
            // A little sway as the cards slide along the line.
            for c in visible { swing.kick(c.id, Double(scroll - old) * 0.0035) }
        }
    }

    private func ensureVisible(_ index: Int) {
        let x = Layout.slotX(index, scroll: scroll, width: width)
        let lo = Layout.slotStart, hi = Layout.slotEnd(width)
        var target = scroll
        if x < lo { target -= lo - x } else if x > hi { target += x - hi }
        if target != scroll { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { scroll = max(0, target) } }
    }

    func flash(_ id: UUID) {
        flashID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            if self?.flashID == id { withAnimation(.easeOut(duration: 0.25)) { self?.flashID = nil } }
        }
    }

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { toast = text }
        let w = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil } }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
    }

    /// Something dropped onto the line from another app.
    func importDrop(_ providers: [NSItemProvider], onto line: UUID) -> Bool {
        var handled = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier("public.file-url") {
                handled = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { self.addImported(.init(kind: .files, paths: [url.path], hash: Hash.of(url.path)), line) }
                }
            } else if p.canLoadObject(ofClass: String.self) {
                handled = true
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    guard let s else { return }
                    DispatchQueue.main.async { self.addImported(Capture.text(s, source: nil), line) }
                }
            } else if p.hasItemConformingToTypeIdentifier("public.image") {
                handled = true
                p.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async {
                        if let clip = Capture.image(data, source: nil, store: self.store) { self.addImported(clip, line) }
                    }
                }
            }
        }
        return handled
    }

    private func addImported(_ clip: Clip, _ line: UUID) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            let c = store.add(clip)
            if line != Store.inboxID { store.hang(c.id, on: line) }
        }
        if let first = visible.first { swing.kick(first.id, 3) }
    }

    // MARK: Keys

    private func handleKey(_ e: NSEvent) -> Bool {
        let code = Int(e.keyCode)
        let mods = e.modifierFlags.intersection([.command, .option, .control])
        if renamingLine != nil { return false }
        if code == 53 { // Esc
            if drawerOpen {
                if !query.isEmpty { query = "" } else { setDrawer(false) }
                if !keyboard && !drawerOpen { panel.resignKey() }
            } else { hide() }
            return true
        }
        if mods.contains(.command) {
            if e.charactersIgnoringModifiers == "f" { setDrawer(true); return true }
            if e.charactersIgnoringModifiers == "," { hide(); openSettings(); return true }
            return false
        }
        if drawerOpen {
            let results = drawerResults
            switch code {
            case 125, 124: drawerSelection = min(drawerSelection + (code == 125 ? Layout.drawerColumns(width) : 1), max(0, results.count - 1)); return true
            case 126, 123: drawerSelection = max(0, drawerSelection - (code == 126 ? Layout.drawerColumns(width) : 1)); return true
            case 36, 76:
                if results.indices.contains(drawerSelection) { paste(results[drawerSelection]) }
                return true
            default: return false
            }
        }
        let clips = visible
        switch code {
        case 123: selection = max(0, selection - 1); ensureVisible(selection); nudgeSelected(-1); return true
        case 124: selection = min(max(0, clips.count - 1), selection + 1); ensureVisible(selection); nudgeSelected(1); return true
        case 48: cycleLine(e.modifierFlags.contains(.shift) ? -1 : 1); return true
        case 36, 76:
            if clips.indices.contains(selection) { paste(clips[selection]) }
            return true
        case 51, 117:
            if clips.indices.contains(selection) { delete(clips[selection]) }
            return true
        case 49: // Space copies without pasting
            if clips.indices.contains(selection) { copy(clips[selection]) }
            return true
        default: break
        }
        guard let chars = e.characters, let ch = chars.first else { return false }
        if let n = Int(String(ch)), (1...9).contains(n) {
            let i = Layout.firstVisible(scroll) + n - 1
            if clips.indices.contains(i) { paste(clips[i]) }
            return true
        }
        if ch.isLetter || ch.isPunctuation || ch.isSymbol {
            query = chars
            setDrawer(true)
            return true
        }
        return false
    }

    private func nudgeSelected(_ dir: Double) {
        let clips = visible
        if clips.indices.contains(selection) { swing.kick(clips[selection].id, -dir * 1.2) }
    }
}
