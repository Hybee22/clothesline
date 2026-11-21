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
    /// The big preview lives in its own see-through window that ignores the mouse,
    /// so showing it never resizes or moves the line.
    @ObservationIgnored private var previewPanel: LinePanel!

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
    var toast: Toast?
    /// The card shown large under the line (hover-hold or ⌥).
    var previewID: UUID?
    /// Clips ⌘-clicked to copy together, in the order they were picked.
    var picked: [UUID] = []
    /// While a card is dragged along the line: the gap it would drop into.
    var dropIndex: Int?
    /// How particular cards leave the line (into the basket, burnt up…). Unset means they flutter away.
    var exitStyle: [UUID: LeaveStyle] = [:]
    /// Set while the pulley carries one line out and the next one in (+1 = moving right along the tabs).
    var slideDir: CGFloat?
    /// Moves the rope's twist, so the rope itself seems to run through the pulley.
    var ropePhase: CGFloat = 0
    var loosePegs: [LoosePeg] = []
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
    @ObservationIgnored private var toastAction: (() -> Void)?
    /// Testing: keeps one card previewed without hovering.
    @ObservationIgnored var pinnedPreview: UUID?
    @ObservationIgnored private var hoverTarget: UUID?
    @ObservationIgnored private var hoverSince = Date()
    @ObservationIgnored private var pendingDelete: (clip: Clip, index: Int)?
    @ObservationIgnored private var purgeWork: DispatchWorkItem?
    @ObservationIgnored private var lastSecretCheck = Date.distantPast
    @ObservationIgnored private var nextBreeze = Date().addingTimeInterval(6)
    @ObservationIgnored private var lastPointer: (x: CGFloat, t: Date)?
    @ObservationIgnored private var lastGust = Date.distantPast
    @ObservationIgnored private var phaseTimer: Timer?

    init(store: Store) {
        self.store = store
        panel = LinePanel()
        let host = LineHostingView(rootView: LineRoot(c: self))
        host.sizingOptions = []
        host.controller = self
        panel.contentView = host
        previewPanel = LinePanel()
        previewPanel.ignoresMouseEvents = true
        let pHost = NSHostingView(rootView: PreviewLayer(c: self))
        pHost.sizingOptions = []
        previewPanel.contentView = pHost
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
                guard let self, self.renamingLine == nil else { return }
                // Picks keep the line open until you click somewhere else.
                if self.keyboard || !self.picked.isEmpty { self.hide() }
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
            previewPanel.orderFrontRegardless()
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
        picked = []
        previewID = nil
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.previewPanel.orderOut(nil)
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
        let ph = Layout.closedHeight + Layout.previewRoom
        previewPanel.setFrame(NSRect(x: s.frame.minX, y: top - ph, width: s.frame.width, height: ph), display: false)
        width = frame.width
        scroll = min(scroll, Layout.maxScroll(count: visible.count, width: width))
    }

    // MARK: Pointer tracking

    private func tick() {
        let p = NSEvent.mouseLocation
        let now = Date()
        if now.timeIntervalSince(lastSecretCheck) > 1 {
            lastSecretCheck = now
            expireSecrets()
        }
        if panel.isVisible && shown && hideWork == nil {
            updatePreview(now)
            updateRopeDip()
            weather(now, pointer: p)
        }
        let buttons = NSEvent.pressedMouseButtons
        if buttons == 0, draggingClip != nil {
            if let r = releasedAt, now.timeIntervalSince(r) > 0.8 {
                draggingClip = nil
                releasedAt = nil
                if dropIndex != nil { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dropIndex = nil } }
            }
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
        guard shown, hideWork == nil, !keyboard, renamingLine == nil, picked.isEmpty, dropIndex == nil else { return }
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
        // A full Inbox: the oldest card slides off the end into the basket as the new one lands.
        if currentLine == Store.inboxID, panel.isVisible, shown, !Motion.reduced, !store.contains(hash: clip.hash) {
            let vis = visible
            if vis.count >= store.inboxCapacity, let last = vis.last {
                exitStyle[last.id] = .basket
                DispatchQueue.main.async { [weak self] in
                    self?.addCaptured(clip)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self?.swing.kick(Store.inboxID, 2.6)
                        Haptics.tick()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self?.exitStyle[last.id] = nil }
                }
                return
            }
        }
        addCaptured(clip)
    }

    private func addCaptured(_ clip: Clip) {
        let wasInbox = currentLine == Store.inboxID
        var added: Clip!
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            added = store.add(clip)
            if wasInbox { scroll = 0 }
        }
        if panel.isVisible && shown {
            if wasInbox { kickNewest(added.id); PegSound.play() }
        } else if Prefs.shared.peekOnCopy && !panel.isVisible {
            currentLine = Store.inboxID
            scroll = 0
            show(peekFor: 1.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.kickNewest(added.id)
                PegSound.play()
            }
        }
    }

    private func kickNewest(_ id: UUID) {
        swing.kick(id, 3.2)
        for (i, c) in visible.prefix(5).enumerated() where c.id != id {
            swing.kick(c.id, (i.isMultiple(of: 2) ? -1 : 1) * 0.9 / Double(i + 1))
        }
    }

    func copy(_ clip: Clip, plain: Bool = false) {
        Paster.write(clip, store: store, plain: plain)
        flash(clip.id)
        swing.kick(clip.id, 1.1)
        if let x = cardX(clip.id) { swing.tug(x: x) }
        Haptics.tick()
        if !keyboard { showToast(plain && clip.rich != nil ? "Copied as plain text" : "Copied") }
    }

    /// Copies one of a colour's other spellings (HEX, RGB, SwiftUI…).
    func copy(_ value: String, from clip: Clip) {
        Paster.writeString(value)
        flash(clip.id)
        swing.kick(clip.id, 1.1)
        showToast("Copied \(value)")
    }

    /// Copies, then pastes into the app in front if Accessibility allows it.
    func paste(_ clip: Clip, plain: Bool = false) {
        Paster.write(clip, store: store, plain: plain)
        flash(clip.id)
        sendPasteOrExplain()
    }

    private func sendPasteOrExplain() {
        if Prefs.shared.autoPaste && Paster.canAutoPaste {
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { Paster.sendPaste() }
        } else {
            showToast(Prefs.shared.autoPaste ? "Copied · allow Accessibility to paste for you" : "Copied · press ⌘V")
            if keyboard { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.hide() } }
        }
    }

    /// Click copies, double-click pastes, ⇧ leaves out formatting, ⌘ picks it to copy with others.
    func activate(_ clip: Clip) {
        let e = NSApp.currentEvent
        let mods = e?.modifierFlags ?? []
        if mods.contains(.command) { togglePick(clip.id); return }
        let plain = mods.contains(.shift)
        if e?.clickCount ?? 1 >= 2 { paste(clip, plain: plain) } else { copy(clip, plain: plain) }
    }

    func delete(_ clip: Clip) {
        // First mark how it leaves (and pop its peg), then take it down on the next pass,
        // so the card has its exit drawn before it goes.
        if exitStyle[clip.id] == nil, panel.isVisible, shown, let x = cardX(clip.id) {
            exitStyle[clip.id] = .flutter
            if !Motion.reduced {
                let y = Layout.ropeY(x, sag: sag, width: width, load: ropeLoad(width))
                let peg = LoosePeg(x: x, y: y, hue: store.line(clip.lineID)?.hue)
                loosePegs.append(peg)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.loosePegs.removeAll { $0.id == peg.id } }
            }
            swing.tug(x: x, strength: -60)
            Haptics.tick()
            DispatchQueue.main.async { [weak self] in self?.delete(clip) }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.store.clips.contains(where: { $0.id == clip.id }) == false { self?.exitStyle[clip.id] = nil }
        }
        finishPendingDelete()
        var removed: (Clip, Int)?
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            removed = store.remove(clip.id)
            picked.removeAll { $0 == clip.id }
            if previewID == clip.id { previewID = nil }
        }
        guard let removed else { return }
        selection = min(selection, max(0, visible.count - 1))
        pendingDelete = (removed.0, removed.1)
        let w = DispatchWorkItem { [weak self] in self?.finishPendingDelete() }
        purgeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: w)
        showToast("Taken down", action: "Undo", for: 5) { [weak self] in self?.undoDelete() }
    }

    func undoDelete() {
        guard let pd = pendingDelete else { return }
        let c = pd.clip, i = pd.index
        purgeWork?.cancel()
        pendingDelete = nil
        exitStyle[c.id] = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { store.restore(c, at: i) }
        swing.kick(c.id, 3)
        PegSound.play()
        showToast("Put back")
    }

    private func finishPendingDelete() {
        purgeWork?.cancel()
        if let c = pendingDelete?.clip { store.purgeFiles(c) }
        pendingDelete = nil
    }

    // MARK: Picking several clips

    func togglePick(_ id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let i = picked.firstIndex(of: id) { picked.remove(at: i) } else { picked.append(id) }
        }
        Haptics.tick()
        swing.kick(id, 1.4)
        if !keyboard { panel.makeKey() }
    }

    func copyPicked(paste: Bool) {
        let clips = picked.compactMap { id in store.clips.first { $0.id == id } }
        guard !clips.isEmpty else { return }
        Paster.writeCombined(clips, store: store)
        for c in clips { swing.kick(c.id, 1.2) }
        withAnimation(.easeOut(duration: 0.2)) { picked = [] }
        if paste { sendPasteOrExplain() } else { showToast("Copied \(clips.count) clips together") }
    }

    func clearPicks() { withAnimation(.easeOut(duration: 0.2)) { picked = [] } }

    // MARK: Reordering

    /// Drops a dragged clip into gap `index` of the line being shown (counting without the clip itself).
    func move(_ id: UUID, to index: Int) {
        let others = visible.filter { $0.id != id }
        let target = others.indices.contains(index) ? others[index].id : nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            store.move(id, before: target, on: currentLine)
            dropIndex = nil
        }
        swing.kick(id, 2.4)
        PegSound.play()
    }

    /// Which gap the pointer is over, for a drag at `x` along the line.
    func gapIndex(atX x: CGFloat, dragging id: UUID) -> Int {
        let others = visible.filter { $0.id != id }
        let i = Int(((x + scroll - Layout.slotStart) / Layout.spacing + 0.5).rounded(.down))
        return max(0, min(others.count, i))
    }

    // MARK: Preview

    private func updatePreview(_ now: Date) {
        let option = NSEvent.modifierFlags.contains(.option)
        var target: UUID?
        if drawerOpen || draggingClip != nil || renamingLine != nil {
            target = nil
        } else if keyboard {
            target = option && visible.indices.contains(selection) ? visible[selection].id : nil
        } else {
            target = hoveredCard
        }
        if let pinnedPreview { setPreview(pinnedPreview); return }
        if target != hoverTarget {
            hoverTarget = target
            hoverSince = now
        }
        if target == nil && previewID != nil && !option {
            // Let the pointer cross the gap between two cards without the preview closing.
            if now.timeIntervalSince(hoverSince) < 0.15 { return }
        }
        // Once a preview is up, moving to the next card switches it straight away.
        let want = target != nil && (option || previewID != nil || now.timeIntervalSince(hoverSince) > 0.9)
        setPreview(want ? target : nil)
    }

    private func setPreview(_ id: UUID?) {
        guard id != previewID else { return }
        if previewID == nil {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { previewID = id }
        } else if id == nil {
            withAnimation(.easeOut(duration: 0.14)) { previewID = nil }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { previewID = id }
        }
    }

    // MARK: Secrets

    private func expireSecrets() {
        let minutes = Prefs.shared.secretMinutes
        guard minutes > 0 else { return }
        let old = store.expiredSecrets(olderThan: TimeInterval(minutes * 60))
        guard !old.isEmpty else { return }
        let pb = NSPasteboard.general
        for c in old {
            // Don't leave the secret sitting on the clipboard either.
            if let t = c.text, pb.string(forType: .string) == t {
                pb.clearContents()
                Paster.watcher?.skipCurrent()
            }
        }
        // They curl up and fade rather than flutter away.
        for c in old { exitStyle[c.id] = .burn }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                for c in old { self.store.delete(c.id) }
                self.picked.removeAll { id in old.contains { $0.id == id } }
            }
            self.selection = min(self.selection, max(0, self.visible.count - 1))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { for c in old { self.exitStyle[c.id] = nil } }
        }
    }

    func hang(_ id: UUID, on line: UUID) {
        let name = line == Store.inboxID ? "Inbox" : (store.line(line)?.name ?? "line")
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { store.hang(id, on: line) }
        if line == currentLine { swing.kick(id, 2) }
        PegSound.play()
        showToast("Hung on \(name)")
    }

    func select(line: UUID) {
        guard line != currentLine else { return }
        let all = [Store.inboxID] + store.lines.map(\.id)
        let dir: CGFloat = (all.firstIndex(of: line) ?? 0) > (all.firstIndex(of: currentLine) ?? 0) ? 1 : -1
        guard panel.isVisible && shown && !Motion.reduced else {
            currentLine = line
            scroll = 0
            selection = 0
            return
        }
        // The pulley: this line's cards ride off one end while the next line's ride in from the other.
        slideDir = dir
        DispatchQueue.main.async { [self] in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                currentLine = line
                scroll = 0
                selection = 0
            }
            runRope(by: -dir * width * 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self else { return }
                self.swing.ripple(self.visible.prefix(10).map(\.id), strength: 0.9)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.slideDir = nil }
        }
    }

    /// Runs the rope's twist along by `distance` over 0.6 s.
    private func runRope(by distance: CGFloat) {
        phaseTimer?.invalidate()
        let start = ropePhase, began = Date()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let p = min(1, Date().timeIntervalSince(began) / 0.6)
                let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                self.ropePhase = start + distance * CGFloat(e)
                if p >= 1 { timer.invalidate() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        phaseTimer = t
    }

    // MARK: Rope and weather

    func cardX(_ id: UUID) -> CGFloat? {
        visible.firstIndex { $0.id == id }.map { Layout.slotX($0, scroll: scroll, width: width) }
    }

    /// Where the rope is pulled down: the springy dip under the hovered or tugged card,
    /// and a little under each image card, which is heavier.
    func ropeLoad(_ w: CGFloat) -> RopeLoad {
        var load = RopeLoad()
        if abs(swing.dip) > 0.05 { load.points.append((swing.dipX, swing.dip)) }
        for (i, clip) in visible.enumerated() where clip.kind == .image {
            let x = Layout.slotX(i, scroll: scroll, width: w)
            if x > 0 && x < w { load.points.append((x, 5 * Layout.fade(x, width: w))) }
        }
        return load
    }

    private func updateRopeDip() {
        if draggingClip == nil, let h = hoveredCard, let x = cardX(h) {
            swing.setDip(x: x, depth: 8)
        } else {
            swing.setDip(x: swing.dipX, depth: 0)
        }
    }

    /// A breeze now and then, and a gust when the pointer sweeps fast across the line.
    private func weather(_ now: Date, pointer p: NSPoint) {
        guard !Motion.reduced, draggingClip == nil else { return }
        let cards = visible.enumerated().filter { i, _ in
            let x = Layout.slotX(i, scroll: scroll, width: width)
            return x > -Layout.cardW && x < width + Layout.cardW
        }
        if now > nextBreeze {
            nextBreeze = now.addingTimeInterval(.random(in: 7...14))
            let dir: Double = Bool.random() ? 1 : -1
            let strength = Double.random(in: 0.25...0.5)
            let ordered = dir > 0 ? cards : cards.reversed()
            for (n, (_, clip)) in ordered.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 0.09) { [weak self] in
                    self?.swing.kick(clip.id, dir * strength * Double.random(in: 0.7...1.2))
                }
            }
        }
        let local = p.x - (panel.frame.minX)
        defer { lastPointer = (local, now) }
        guard let last = lastPointer, NSMouseInRect(p, panel.frame, false) else { return }
        let dt = now.timeIntervalSince(last.t)
        guard dt > 0, dt < 0.1 else { return }
        let vx = (local - last.x) / CGFloat(dt)
        guard abs(vx) > 3200, now.timeIntervalSince(lastGust) > 1.5 else { return }
        lastGust = now
        // A gust, not a gale: enough to stir the cards, never to throw them around.
        let strength = min(0.9, Double(abs(vx)) / 5000)
        for (i, clip) in cards {
            let x = Layout.slotX(i, scroll: scroll, width: width)
            let delay = Double(abs(x - local)) / 2200
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.swing.kick(clip.id, (vx > 0 ? -1 : 1) * strength * Double.random(in: 0.8...1.1))
            }
        }
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

    func showToast(_ text: String, action: String? = nil, for seconds: Double = 1.6, perform: (() -> Void)? = nil) {
        toastWork?.cancel()
        toastAction = perform
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { toast = Toast(text: text, action: action) }
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
            self?.toastAction = nil
        }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    func runToastAction() {
        let a = toastAction
        toastWork?.cancel()
        toastAction = nil
        withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        a?()
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
            if !picked.isEmpty && !drawerOpen { clearPicks(); return true }
            if drawerOpen {
                if !query.isEmpty { query = "" } else { setDrawer(false) }
                if !keyboard && !drawerOpen { panel.resignKey() }
            } else { hide() }
            return true
        }
        if mods.contains(.command) {
            if e.charactersIgnoringModifiers == "f" { setDrawer(true); return true }
            if e.charactersIgnoringModifiers == "z", pendingDelete != nil { undoDelete(); return true }
            if e.charactersIgnoringModifiers == "c", !picked.isEmpty { copyPicked(paste: false); return true }
            if e.charactersIgnoringModifiers == "," { hide(); openSettings(); return true }
            return false
        }
        if drawerOpen {
            let results = drawerResults
            switch code {
            case 125, 124: drawerSelection = min(drawerSelection + (code == 125 ? Layout.drawerColumns(width) : 1), max(0, results.count - 1)); return true
            case 126, 123: drawerSelection = max(0, drawerSelection - (code == 126 ? Layout.drawerColumns(width) : 1)); return true
            case 36, 76:
                if results.indices.contains(drawerSelection) { paste(results[drawerSelection], plain: e.modifierFlags.contains(.shift)) }
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
            if !picked.isEmpty { copyPicked(paste: true); return true }
            if clips.indices.contains(selection) { paste(clips[selection], plain: e.modifierFlags.contains(.shift)) }
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

struct Toast: Equatable {
    var id = UUID()
    let text: String
    let action: String?
}
