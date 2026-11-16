import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Layout {
    static let closedHeight: CGFloat = 318
    static let drawerHeight: CGFloat = 380
    /// Extra room under the line while a card is shown large.
    static let previewRoom: CGFloat = 330
    static let previewW: CGFloat = 470
    static let cardW: CGFloat = 150
    static let cardH: CGFloat = 180
    static let cardTop: CGFloat = 16          // card's top edge inside the hanging view
    static let pegTop: CGFloat = 10           // the rope passes this far below the view's top
    static let viewH: CGFloat = cardH + cardTop
    static let inset: CGFloat = 26
    static let baseY: CGFloat = 52
    static let restSag: CGFloat = 36
    static let spacing: CGFloat = 172
    static let slotStart: CGFloat = inset + 70 + cardW / 2

    static func slotEnd(_ w: CGFloat) -> CGFloat { w - inset - 150 - cardW / 2 }
    static func slotX(_ i: Int, scroll: CGFloat, width: CGFloat) -> CGFloat { slotStart + CGFloat(i) * spacing - scroll }
    static func maxScroll(count: Int, width: CGFloat) -> CGFloat {
        max(0, CGFloat(count - 1) * spacing - (slotEnd(width) - slotStart))
    }
    static func firstVisible(_ scroll: CGFloat) -> Int { max(0, Int((scroll / spacing - 0.02).rounded(.up))) }

    static func ropeY(_ x: CGFloat, sag: CGFloat, width: CGFloat) -> CGFloat {
        let l = inset, r = width - inset
        let t = min(max((x - l) / (r - l), 0), 1)
        return baseY + sag * 4 * t * (1 - t)
    }
    static func ropeSlope(_ x: CGFloat, sag: CGFloat, width: CGFloat) -> CGFloat {
        let l = inset, r = width - inset
        let t = min(max((x - l) / (r - l), 0), 1)
        return sag * 4 * (1 - 2 * t) / (r - l)
    }
    static func fade(_ x: CGFloat, width: CGFloat) -> Double {
        let lo = slotStart - spacing * 0.8, hi = slotEnd(width) + spacing * 0.8
        let a = (x - lo) / (spacing * 0.5), b = (hi - x) / (spacing * 0.5)
        return Double(min(max(min(a, b), 0), 1))
    }
    static func drawerWidth(_ w: CGFloat) -> CGFloat { min(w - 80, 1240) }
    static func drawerColumns(_ w: CGFloat) -> Int { max(1, Int((drawerWidth(w) - 32 + 12) / (cardW + 12))) }
    static var basketX: (CGFloat) -> CGFloat = { w in w - inset - 64 }
}

// MARK: - Root

struct LineRoot: View {
    @Bindable var c: LineController
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let w = c.width
        let clips = c.visible
        let first = Layout.firstVisible(c.scroll)
        let total = Layout.closedHeight + (c.drawerOpen ? Layout.drawerHeight : c.previewID != nil ? Layout.previewRoom : 0)
        ZStack(alignment: .topLeading) {
            scrim(w)
                .contentShape(Rectangle())
                .onTapGesture { c.hide() }

            Hook().position(x: Layout.inset, y: (Layout.baseY + 6) / 2)
            Hook().position(x: w - Layout.inset, y: (Layout.baseY + 6) / 2)
            Rope(sag: c.sag, width: w, dark: scheme == .dark)

            BasketHanger(c: c, width: w)
                .zIndex(5)

            if clips.isEmpty {
                EmptyCard(line: c.currentLine == Store.inboxID ? nil : c.store.line(c.currentLine)?.name)
                    .modifier(Hang(x: Layout.slotX(0, scroll: 0, width: w), sag: c.sag, width: w, angle: 0))
                    .transition(.opacity)
            }

            ForEach(Array(clips.enumerated()), id: \.element.id) { i, clip in
                let x = Layout.slotX(i, scroll: c.scroll, width: w)
                let badge = c.keyboard && i >= first && i < first + 9 ? i - first + 1 : nil
                CardView(clip: clip, index: i, badge: badge, c: c)
                    .modifier(Hang(x: x, sag: c.sag, width: w, angle: c.swing.angle[clip.id] ?? 0))
                    // Above the scrim (zIndex 0), which closes the line when you click it.
                    .zIndex(c.hoveredCard == clip.id ? 10 : 1 - Double(i) * 0.001)
                    .transition(.asymmetric(
                        insertion: .modifier(active: DropIn(p: 1), identity: DropIn(p: 0)),
                        removal: .modifier(active: Fall(p: 1), identity: Fall(p: 0))))
            }

            TabsBar(c: c)
                .fixedSize()
                .position(x: w / 2, y: 22)
                .zIndex(20)

            if c.drawerOpen {
                Drawer(c: c)
                    .frame(width: Layout.drawerWidth(w), height: Layout.drawerHeight - 20)
                    .position(x: w / 2, y: Layout.closedHeight + (Layout.drawerHeight - 20) / 2 - 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(30)
            }

            if let id = c.previewID, let i = clips.firstIndex(where: { $0.id == id }) {
                let x = Layout.slotX(i, scroll: c.scroll, width: w)
                let top = Layout.ropeY(x, sag: c.sag, width: w) - Layout.pegTop + Layout.viewH + 4
                PreviewCard(clip: clips[i], store: c.store)
                    .frame(width: Layout.previewW)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Layout.previewW, height: Layout.previewRoom - 14, alignment: .top)
                    .position(x: min(max(x, Layout.previewW / 2 + 16), w - Layout.previewW / 2 - 16),
                              y: top + (Layout.previewRoom - 14) / 2)
                    .transition(.modifier(active: SwingForward(p: 1), identity: SwingForward(p: 0)))
                    .allowsHitTesting(false)
                    .zIndex(25)
            }

            if !c.picked.isEmpty {
                PickBar(c: c)
                    .position(x: w / 2, y: Layout.closedHeight - 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(35)
            }

            if let t = c.toast {
                ToastView(toast: t, c: c)
                    .id(t.id)
                    .position(x: w / 2, y: Layout.closedHeight - (c.picked.isEmpty ? 24 : 64))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(40)
            }
        }
        .frame(width: w, height: total, alignment: .topLeading)
        .offset(y: c.shown ? 0 : -(Layout.closedHeight + 30))
        .opacity(c.shown ? 1 : 0)
        .onDrop(of: [.fileURL, .plainText, .image, .url], isTargeted: nil) { providers in
            c.draggingClip == nil ? c.importDrop(providers, onto: c.currentLine) : false
        }
    }

    private func scrim(_ w: CGFloat) -> some View {
        let dark = scheme == .dark
        return LinearGradient(stops: [
            .init(color: .black.opacity(dark ? 0.62 : 0.42), location: 0),
            .init(color: .black.opacity(dark ? 0.42 : 0.26), location: 0.6),
            .init(color: .black.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(width: w, height: Layout.closedHeight + (c.drawerOpen ? Layout.drawerHeight * 0.6 : 0))
    }
}

/// Places a card on the rope at `x`, following the rope's curve while it animates.
struct Hang: ViewModifier, Animatable {
    var x: CGFloat
    var sag: CGFloat
    let width: CGFloat
    let angle: Double

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, sag) }
        set { x = newValue.first; sag = newValue.second }
    }

    func body(content: Content) -> some View {
        let y = Layout.ropeY(x, sag: sag, width: width)
        let tilt = Double(atan(Layout.ropeSlope(x, sag: sag, width: width))) * 0.6
        let fade = Layout.fade(x, width: width)
        content
            .frame(width: Layout.cardW, height: Layout.viewH, alignment: .top)
            .rotationEffect(.radians(angle + tilt), anchor: UnitPoint(x: 0.5, y: Layout.pegTop / Layout.viewH))
            .opacity(fade)
            .allowsHitTesting(fade > 0.4)
            .position(x: x, y: y - Layout.pegTop + Layout.viewH / 2)
    }
}

/// The preview tips forward out of the line, hinged at its top edge.
struct SwingForward: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(-70 * p), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            .scaleEffect(1 - 0.25 * p, anchor: .top)
            .opacity(1 - p)
    }
}

struct DropIn: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content.offset(y: -240 * p).opacity(1 - p * 0.6)
    }
}

struct Fall: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(24 * p), anchor: .top)
            .offset(x: 30 * p, y: 300 * p)
            .opacity(1 - p)
    }
}

// MARK: - Rope, hooks, pegs

struct RopeShape: Shape {
    var sag: CGFloat
    let width: CGFloat
    var animatableData: CGFloat {
        get { sag }
        set { sag = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = Layout.inset, r = width - Layout.inset
        p.move(to: CGPoint(x: l, y: Layout.baseY))
        p.addQuadCurve(to: CGPoint(x: r, y: Layout.baseY), control: CGPoint(x: (l + r) / 2, y: Layout.baseY + 2 * sag))
        return p
    }
}

struct Rope: View {
    let sag: CGFloat
    let width: CGFloat
    let dark: Bool

    var body: some View {
        let twine = dark ? Color(red: 0.80, green: 0.72, blue: 0.60) : Color(red: 0.90, green: 0.83, blue: 0.70)
        let twist = dark ? Color(red: 0.52, green: 0.44, blue: 0.34) : Color(red: 0.62, green: 0.52, blue: 0.40)
        ZStack {
            RopeShape(sag: sag, width: width)
                .stroke(Color.black.opacity(0.32), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .offset(y: 4).blur(radius: 2.5)
            RopeShape(sag: sag, width: width)
                .stroke(twine, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            RopeShape(sag: sag, width: width)
                .stroke(twist.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [1.4, 2.6]))
            RopeShape(sag: sag, width: width)
                .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                .offset(y: -0.7)
        }
        .allowsHitTesting(false)
    }
}

private let metal = LinearGradient(colors: [Color(white: 0.92), Color(white: 0.58)], startPoint: .leading, endPoint: .trailing)

struct Hook: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 2).fill(metal).frame(width: 20, height: 5)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            Rectangle().fill(metal).frame(width: 2.2, height: Layout.baseY - 12).offset(y: 4)
            Circle().stroke(metal, lineWidth: 2.4).frame(width: 11, height: 11).offset(y: Layout.baseY - 10)
        }
        .frame(width: 22, height: Layout.baseY + 6, alignment: .top)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
        .allowsHitTesting(false)
    }
}

struct Peg: View {
    let hue: Double?
    var open = false

    var body: some View {
        let light = hue.map { Color(hue: $0, saturation: 0.42, brightness: 1.0) } ?? Color(red: 0.91, green: 0.77, blue: 0.56)
        let dark = hue.map { Color(hue: $0, saturation: 0.64, brightness: 0.80) } ?? Color(red: 0.69, green: 0.51, blue: 0.32)
        ZStack(alignment: .top) {
            HStack(spacing: 1.2) {
                half(light, dark).rotationEffect(.degrees(open ? -5 : 0), anchor: .bottom)
                half(light, dark).rotationEffect(.degrees(open ? 5 : 0), anchor: .bottom)
            }
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                .frame(width: 18, height: 5)
                .offset(y: 11)
        }
        .frame(width: 18, height: 32, alignment: .top)
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1.5)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: open)
    }

    private func half(_ l: Color, _ d: Color) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 3)
            .fill(LinearGradient(colors: [l, d], startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.45)).frame(width: 1).padding(.vertical, 3).padding(.leading, 1)
            }
            .frame(width: 6.5, height: 32)
    }
}

// MARK: - Cards

struct CardView: View {
    let clip: Clip
    let index: Int
    let badge: Int?
    @Bindable var c: LineController
    @State private var lastX: CGFloat?
    @State private var dropTarget = false

    var body: some View {
        let hover = c.hoveredCard == clip.id
        let selected = c.keyboard && c.selection == index
        let pick = c.picked.firstIndex(of: clip.id)
        let reorderable = c.currentLine != Store.inboxID && c.draggingClip != nil && c.draggingClip != clip.id
        ZStack(alignment: .top) {
            CardFace(clip: clip, store: c.store, lifted: hover || selected)
                .frame(width: Layout.cardW, height: Layout.cardH)
                .overlay(alignment: .topTrailing) {
                    if hover && !c.keyboard {
                        Button { c.delete(clip) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Take it down (delete)")
                        .padding(7)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay {
                    if c.flashID == clip.id { CopiedBadge().transition(.scale(scale: 0.8).combined(with: .opacity)) }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: selected || pick != nil ? 2.5 : 0)
                )
                .overlay(alignment: .topLeading) {
                    if let pick {
                        Text("\(pick + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.accentColor))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.2))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: -7, y: -7)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .leading) {
                    // Where a dragged clip will land when reordering a line.
                    if dropTarget && reorderable {
                        Capsule().fill(Color.accentColor).frame(width: 4, height: Layout.cardH * 0.7)
                            .shadow(color: Color.accentColor.opacity(0.7), radius: 6)
                            .offset(x: -14)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Text("\(badge)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(selected ? Color.accentColor : Color(white: 0.18)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: 6, y: 6)
                    }
                }
                .scaleEffect(hover ? 1.04 : 1, anchor: .top)
                .offset(x: dropTarget && reorderable ? 26 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dropTarget)
                .padding(.top, Layout.cardTop)
            Peg(hue: c.store.line(clip.lineID)?.hue, open: hover)
        }
        .frame(width: Layout.cardW, height: Layout.viewH, alignment: .top)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if c.hoveredCard != clip.id {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { c.hoveredCard = clip.id }
                }
                // Brushing past a card sets it swinging.
                let x = NSEvent.mouseLocation.x
                if let lx = lastX, abs(x - lx) > 0.3 { c.swing.kick(clip.id, -Double(x - lx) * 0.02) }
                lastX = x
            case .ended:
                lastX = nil
                if c.hoveredCard == clip.id {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { c.hoveredCard = nil }
                }
            }
        }
        .onTapGesture { c.activate(clip) }
        .onDrag {
            c.draggingClip = clip.id
            return DragOut.provider(clip, store: c.store)
        }
        .onDrop(of: [.item], isTargeted: $dropTarget) { _ in
            guard reorderable, let d = c.draggingClip else { return false }
            c.draggingClip = nil
            return c.move(d, before: clip.id)
        }
        .contextMenu { ClipMenu(clip: clip, c: c) }
        .help("Click to copy · double-click to paste · ⇧ without formatting · ⌘-click to pick several · hold to preview (or ⌥)")
    }
}

struct CardFace: View {
    let clip: Clip
    let store: Store
    var lifted = false
    var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous)
        ZStack {
            switch clip.kind {
            case .image: imageFace
            case .color: colorFace
            default: if clip.isSecret { secretFace } else { paperFace }
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.22 : 0.85), Color.white.opacity(scheme == .dark ? 0.04 : 0.2)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        )
        .shadow(color: .black.opacity(lifted ? 0.38 : 0.28), radius: lifted ? 18 : 10, y: lifted ? 12 : 7)
    }

    // Paper: text, links and files
    private var paperFace: some View {
        let dark = scheme == .dark
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: dark ? [Color(white: 0.23), Color(white: 0.16)] : [Color(white: 1.0), Color(white: 0.93)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [tint.opacity(dark ? 0.16 : 0.10), .clear], startPoint: .top, endPoint: .center)
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                header(color: tint)
                content
                Spacer(minLength: 0)
                Text(footer)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(compact ? 10 : 12)
            .padding(.top, compact ? 0 : 6)
        }
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .link:
            let u = URL(string: clip.text ?? "")
            VStack(alignment: .leading, spacing: 4) {
                Text(u?.host?.replacingOccurrences(of: "www.", with: "") ?? clip.text ?? "")
                    .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                let path = (u?.path ?? "") + (u?.query.map { "?" + $0 } ?? "")
                if !path.isEmpty && path != "/" {
                    Text(path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 2 : 4)
                }
            }
        case .files:
            let paths = clip.paths ?? []
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .leading) {
                    ForEach(Array(paths.prefix(3).enumerated().reversed()), id: \.offset) { i, p in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: p))
                            .resizable().frame(width: compact ? 34 : 46, height: compact ? 34 : 46)
                            .rotationEffect(.degrees(Double(i) * 7))
                            .offset(x: CGFloat(i) * 14)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    }
                }
                Text(paths.count == 1 ? (paths[0] as NSString).lastPathComponent : "\(paths.count) items")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
            }
        default:
            let t = String((clip.text ?? "").prefix(500))
            Text(clip.looksLikeCode ? t : t.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(clip.looksLikeCode ? .system(size: 10.5, design: .monospaced) : .system(size: compact ? 11.5 : 12.5))
                .lineSpacing(1.5)
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(compact ? 4 : 7)
        }
    }

    private var footer: String {
        switch clip.kind {
        case .link: return URL(string: clip.text ?? "")?.scheme?.uppercased() ?? "LINK"
        case .files:
            let p = clip.paths ?? []
            return p.count == 1 ? ((p[0] as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath : "Files"
        default:
            let t = clip.text ?? ""
            let lines = t.split(separator: "\n", omittingEmptySubsequences: false).count
            return "\(t.count) chars" + (lines > 1 ? " · \(lines) lines" : "") + (clip.rich != nil ? " · formatted" : "")
        }
    }

    private func header(color: Color) -> some View {
        HStack(spacing: 5) {
            if let icon = AppIcons.icon(clip.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(ago(clip.created))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var tint: Color {
        switch clip.kind {
        case .text: return clip.looksLikeCode ? Color(hue: 0.75, saturation: 0.5, brightness: 0.8) : Color(hue: 0.6, saturation: 0.55, brightness: 0.85)
        case .link: return Color(hue: 0.5, saturation: 0.7, brightness: 0.72)
        case .files: return Color(hue: 0.08, saturation: 0.75, brightness: 0.9)
        case .image: return Color(hue: 0.92, saturation: 0.5, brightness: 0.85)
        case .color: return Color(nsColor: ColorParse.color(clip.text ?? "") ?? .gray)
        }
    }
    private var label: String {
        switch clip.kind {
        case .text: return clip.looksLikeCode ? "CODE" : "TEXT"
        case .link: return "LINK"
        case .files: return (clip.paths?.count ?? 0) > 1 ? "FILES" : "FILE"
        case .image: return "IMAGE"
        case .color: return "COLOUR"
        }
    }
    private var symbol: String {
        switch clip.kind {
        case .text: return clip.looksLikeCode ? "chevron.left.forwardslash.chevron.right" : "text.alignleft"
        case .link: return "link"
        case .files: return "doc"
        case .image: return "photo"
        case .color: return "paintpalette"
        }
    }

    private var secretFace: some View {
        let dark = scheme == .dark
        let red = Color(hue: 0.02, saturation: 0.7, brightness: 0.9)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: dark ? [Color(white: 0.21), Color(white: 0.14)] : [Color(white: 0.99), Color(white: 0.91)],
                           startPoint: .top, endPoint: .bottom)
            // Diagonal hatching, like a sealed envelope.
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 9
                }
                ctx.stroke(p, with: .color(red.opacity(dark ? 0.10 : 0.07)), lineWidth: 3)
            }
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                    Text("SECRET").font(.system(size: 9, weight: .bold)).tracking(0.6)
                    Spacer(minLength: 0)
                    Text(ago(clip.created)).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
                .foregroundStyle(red)
                Text(Secrets.mask(clip.text ?? ""))
                    .font(.system(size: compact ? 11 : 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(compact ? 2 : 3)
                Spacer(minLength: 0)
                SecretCountdown(clip: clip)
            }
            .padding(compact ? 10 : 12)
            .padding(.top, compact ? 0 : 6)
        }
    }

    private var imageFace: some View {
        ZStack(alignment: .bottomLeading) {
            Color(white: scheme == .dark ? 0.15 : 0.96)
            if let img = store.thumbnail(clip) {
                Color.clear
                    .overlay(Image(nsImage: img).resizable().aspectRatio(contentMode: .fill))
                    .clipped()
            } else {
                Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            HStack(spacing: 5) {
                if let icon = AppIcons.icon(clip.sourceBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                }
                if let s = clip.imageSize {
                    Text("\(Int(s.width))×\(Int(s.height))").font(.system(size: 9.5, weight: .semibold, design: .rounded))
                }
                Spacer()
                Text(ago(clip.created)).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.bottom, 8)
        }
    }

    private var colorFace: some View {
        let ns = ColorParse.color(clip.text ?? "") ?? .gray
        let rgb = ns.usingColorSpace(.sRGB) ?? ns
        let lum = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        let ink: Color = lum > 0.6 ? .black.opacity(0.78) : .white
        return ZStack(alignment: .bottomLeading) {
            Color(nsColor: ns)
            LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "paintpalette").font(.system(size: 9, weight: .bold))
                    Text("COLOUR").font(.system(size: 9, weight: .bold)).tracking(0.6)
                    Spacer()
                    Text(ago(clip.created)).font(.system(size: 9, weight: .medium))
                }
                .padding(.top, compact ? 0 : 6)
                Spacer()
                Text(clip.text ?? "").font(.system(size: compact ? 12 : 14, weight: .semibold, design: .monospaced)).lineLimit(1)
                Text("RGB \(Int(rgb.redComponent * 255)) \(Int(rgb.greenComponent * 255)) \(Int(rgb.blueComponent * 255))")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded)).opacity(0.8)
            }
            .foregroundStyle(ink)
            .padding(compact ? 10 : 12)
        }
    }
}

struct CopiedBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor.opacity(0.16))
            Label("Copied", systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .allowsHitTesting(false)
    }
}

struct EmptyCard: View {
    let line: String?
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                Image(systemName: line == nil ? "doc.on.clipboard" : "hand.draw")
                    .font(.system(size: 22, weight: .light))
                Text(line == nil ? "Copy anything and it hangs here" : "Drag clips onto the \(line!) tag to hang them here")
                    .font(.system(size: 11.5, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(14)
            .frame(width: Layout.cardW, height: Layout.cardH)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.15)))
            )
            .padding(.top, Layout.cardTop)
            Peg(hue: nil)
        }
        .allowsHitTesting(false)
    }
}

struct ClipMenu: View {
    let clip: Clip
    let c: LineController

    var body: some View {
        Button("Copy") { c.copy(clip) }
        Button("Paste") { c.paste(clip) }
        if clip.rich != nil {
            Button("Copy as Plain Text") { c.copy(clip, plain: true) }
            Button("Paste as Plain Text") { c.paste(clip, plain: true) }
        }
        if clip.kind == .color {
            Menu("Copy as") {
                ForEach(ColorFormats.all(clip.text ?? ""), id: \.label) { f in
                    Button("\(f.label)   \(f.value)") { c.copy(f.value, from: clip) }
                }
            }
        }
        Button(c.picked.contains(clip.id) ? "Unpick" : "Pick to Copy Together (⌘-click)") { c.togglePick(clip.id) }
        Menu("Hang on") {
            if clip.lineID != nil { Button("Inbox") { c.hang(clip.id, on: Store.inboxID) } }
            ForEach(c.store.lines) { l in
                if l.id != clip.lineID { Button(l.name) { c.hang(clip.id, on: l.id) } }
            }
        }
        switch clip.kind {
        case .link:
            if let u = URL(string: clip.text ?? "") { Button("Open Link") { NSWorkspace.shared.open(u) } }
        case .files:
            let urls = (clip.paths ?? []).map { URL(fileURLWithPath: $0) }
            Button("Open") { urls.forEach { NSWorkspace.shared.open($0) } }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        case .image:
            if let b = clip.blob {
                Button("Open in Preview") { NSWorkspace.shared.open(c.store.blobURL(b)) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([c.store.blobURL(b)]) }
            }
        default: EmptyView()
        }
        Divider()
        Button(clip.lineID == nil ? "Delete" : "Take Down and Delete", role: .destructive) { c.delete(clip) }
    }
}

@MainActor
enum DragOut {
    static func provider(_ clip: Clip, store: Store) -> NSItemProvider {
        switch clip.kind {
        case .text, .color:
            return NSItemProvider(object: (clip.text ?? "") as NSString)
        case .link:
            if let u = URL(string: clip.text ?? "") {
                let p = NSItemProvider(object: u as NSURL)
                p.registerObject((clip.text ?? "") as NSString, visibility: .all)
                return p
            }
            return NSItemProvider(object: (clip.text ?? "") as NSString)
        case .image:
            guard let b = clip.blob, let p = NSItemProvider(contentsOf: store.blobURL(b)) else { return NSItemProvider() }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            p.suggestedName = "Clip \(f.string(from: clip.created)).png"
            return p
        case .files:
            guard let first = clip.paths?.first, let p = NSItemProvider(contentsOf: URL(fileURLWithPath: first)) else { return NSItemProvider() }
            return p
        }
    }
}

// MARK: - Basket

struct BasketHanger: View {
    let c: LineController
    let width: CGFloat
    @State private var targeted = false
    @State private var hover = false

    var body: some View {
        let bx = Layout.basketX(width)
        let ry = Layout.ropeY(bx, sag: c.sag, width: width)
        let top = ry + 40
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: bx, y: ry + 6))
                p.addLine(to: CGPoint(x: bx - 40, y: top + 2))
                p.move(to: CGPoint(x: bx, y: ry + 6))
                p.addLine(to: CGPoint(x: bx + 40, y: top + 2))
            }
            .stroke(Color(red: 0.86, green: 0.79, blue: 0.66), lineWidth: 1.2)
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            .allowsHitTesting(false)

            BasketView(count: c.store.basketCount, open: c.drawerOpen, lifted: hover || targeted)
                .contentShape(Rectangle())
                .onHover { h in
                    hover = h
                    if h { c.swing.kick(Store.inboxID, 0.8) }
                }
                .onTapGesture { c.toggleDrawer() }
                .help("The basket: everything you've copied. Click to search it")
                // Gestures go before .position: after it they cover the whole line
                // and steal hovers and clicks from the cards hanging under it.
                .rotationEffect(.radians(c.swing.angle[Store.inboxID] ?? 0), anchor: UnitPoint(x: 0.5, y: -0.6))
                .position(x: bx, y: top + 30)

            Peg(hue: nil).position(x: bx, y: ry + 6).allowsHitTesting(false)
        }
        .frame(width: width, height: Layout.closedHeight, alignment: .topLeading)
    }
}

struct BasketView: View {
    let count: Int
    let open: Bool
    let lifted: Bool

    private let cloth: [Color] = [
        Color(hue: 0.58, saturation: 0.45, brightness: 0.95),
        Color(hue: 0.95, saturation: 0.35, brightness: 0.98),
        Color(hue: 0.14, saturation: 0.45, brightness: 1.0),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            if count > 0 {
                HStack(spacing: -10) {
                    ForEach(0..<min(count, 3), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 7)
                            .fill(cloth[i])
                            .frame(width: 30, height: 22)
                            .rotationEffect(.degrees(Double(i - 1) * 16))
                            .offset(y: i == 1 ? -4 : 0)
                    }
                }
                .offset(y: -12)
            }
            BasketShape()
                .fill(LinearGradient(colors: [Color(red: 0.82, green: 0.62, blue: 0.40), Color(red: 0.56, green: 0.38, blue: 0.22)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Weave().stroke(Color.black.opacity(0.2), lineWidth: 1).clipShape(BasketShape()))
                .frame(width: 84, height: 50)
                .offset(y: 4)
            Capsule()
                .fill(LinearGradient(colors: [Color(red: 0.72, green: 0.52, blue: 0.32), Color(red: 0.50, green: 0.33, blue: 0.19)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 92, height: 9)
            Image(systemName: open ? "chevron.up" : "magnifyingglass")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .offset(y: 20)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .offset(y: 40)
            }
        }
        .frame(width: 96, height: 62, alignment: .top)
        .shadow(color: .black.opacity(0.35), radius: lifted ? 10 : 5, y: lifted ? 7 : 4)
        .scaleEffect(lifted ? 1.06 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: lifted)
        .contentShape(Rectangle())
    }
}

struct BasketShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 9, y: r.maxY - 8))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 19, y: r.maxY), control: CGPoint(x: r.maxX - 11, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 19, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX + 9, y: r.maxY - 8), control: CGPoint(x: r.minX + 11, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct Weave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var y = r.minY + 7
        while y < r.maxY {
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            y += 7
        }
        var x = r.minX - 10
        while x < r.maxX + 10 {
            p.move(to: CGPoint(x: x, y: r.minY))
            p.addLine(to: CGPoint(x: x + (x - r.midX) * 0.12, y: r.maxY))
            x += 8
        }
        return p
    }
}

// MARK: - Tabs bar

struct Glass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct TabsBar: View {
    @Bindable var c: LineController
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            Spacer().frame(width: 2)
            LineTag(c: c, id: Store.inboxID, name: "Inbox", hue: nil)
            ForEach(c.store.lines) { l in
                LineTag(c: c, id: l.id, name: l.name, hue: l.hue)
            }
            BarButton(symbol: "plus", help: "New line") { c.newLine() }
            Divider().frame(height: 14).padding(.horizontal, 4)
            if Prefs.shared.paused {
                Button { Prefs.shared.paused = false } label: {
                    Label("Paused", systemImage: "pause.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .help("Capturing is paused. Click to resume")
            }
            BarButton(symbol: "magnifyingglass", help: "Search everything (⌘F, or just start typing)") { c.toggleDrawer() }
            BarButton(symbol: "gearshape", help: "Settings (⌘,)") { c.hide(); c.openSettings() }
        }
        .padding(4)
        .background(Glass().clipShape(Capsule()))
        .overlay(Capsule().strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.6), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
    }
}

struct BarButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct LineTag: View {
    @Bindable var c: LineController
    let id: UUID
    let name: String
    let hue: Double?
    @State private var hover = false
    @State private var targeted = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let selected = c.currentLine == id
        let tint = hue.map { Color(hue: $0, saturation: 0.55, brightness: 0.95) } ?? Color(red: 0.85, green: 0.70, blue: 0.50)
        let n = c.store.count(on: id)
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
            if c.renamingLine == id {
                TextField("Line name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 96)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { c.renamingLine = nil }
                    .onAppear {
                        draft = name == "New line" ? "" : name
                        DispatchQueue.main.async { focused = true }
                    }
                    .onChange(of: focused) { _, f in if !f && c.renamingLine == id { commit() } }
            } else {
                Text(name).font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            if n > 0 && c.renamingLine != id {
                Text("\(n)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            Capsule().fill(targeted ? tint.opacity(0.4) : selected ? Color.primary.opacity(0.12) : Color.primary.opacity(hover ? 0.06 : 0))
        )
        .overlay(Capsule().strokeBorder(tint.opacity(targeted ? 0.9 : 0), lineWidth: 1.5))
        .contentShape(Capsule())
        .scaleEffect(targeted ? 1.1 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: targeted)
        .onHover { hover = $0 }
        .onTapGesture {
            if NSApp.currentEvent?.clickCount ?? 1 >= 2 && id != Store.inboxID {
                c.renamingLine = id
                c.panel.makeKey()
            } else {
                c.select(line: id)
            }
        }
        .contextMenu {
            if id != Store.inboxID {
                Button("Rename") { c.renamingLine = id; c.panel.makeKey() }
                Button("Delete Line", role: .destructive) { c.deleteLine(id) }
            }
        }
        .onDrop(of: [.item], isTargeted: $targeted) { providers in
            if let d = c.draggingClip {
                c.draggingClip = nil
                c.hang(d, on: id)
                return true
            }
            return c.importDrop(providers, onto: id)
        }
        .help(id == Store.inboxID ? "Everything you copy lands here" : "Drop a clip here to hang it on \(name). Double-click to rename")
    }

    private func commit() {
        let n = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        c.store.rename(id, to: n.isEmpty ? (name == "New line" ? "Untitled" : name) : n)
        c.renamingLine = nil
    }
}

// MARK: - Drawer (search the basket)

struct Drawer: View {
    @Bindable var c: LineController
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let results = c.drawerResults
        let cols = Layout.drawerColumns(c.width)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                TextField("Search everything you've copied…", text: $c.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onChange(of: c.query) { c.drawerSelection = 0 }
                Text(c.query.isEmpty ? "\(c.store.clips.count) clips" : "\(results.count) found")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if c.store.basketCount > 0 {
                    Button("Empty basket") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { c.store.clearBasket() }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .help("Delete the \(c.store.basketCount) older clips that no longer fit on the Inbox line. Hung clips stay")
                }
                BarButton(symbol: "xmark", help: "Close (Esc)") { c.setDrawer(false) }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider().opacity(0.6)
            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "basket").font(.system(size: 28, weight: .light))
                    Text(c.query.isEmpty ? "The basket is empty" : "Nothing matches “\(c.query)”")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Layout.cardW), spacing: 12), count: cols), spacing: 14) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { i, clip in
                                DrawerTile(clip: clip, selected: i == c.drawerSelection, c: c).id(clip.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: c.drawerSelection) { _, s in
                        if results.indices.contains(s) { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(results[s].id, anchor: .center) } }
                    }
                }
            }
        }
        .background(Glass(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.12 : 0.6), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: c.focusSearch) { focused = true }
    }
}

struct DrawerTile: View {
    let clip: Clip
    let selected: Bool
    let c: LineController
    @State private var hover = false

    var body: some View {
        CardFace(clip: clip, store: c.store, lifted: hover || selected, compact: true)
            .frame(width: Layout.cardW, height: 120)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.accentColor, lineWidth: selected ? 2.5 : 0))
            .overlay(alignment: .topTrailing) {
                if let l = c.store.line(clip.lineID) {
                    Text(l.name)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hue: l.hue, saturation: 0.55, brightness: 0.95)))
                        .foregroundStyle(.black.opacity(0.7))
                        .padding(6)
                }
            }
            .overlay { if c.flashID == clip.id { CopiedBadge() } }
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
            .onHover { hover = $0 }
            .onTapGesture { c.activate(clip) }
            .onDrag {
                c.draggingClip = clip.id
                return DragOut.provider(clip, store: c.store)
            }
            .contextMenu { ClipMenu(clip: clip, c: c) }
    }
}

struct ToastView: View {
    let toast: Toast
    let c: LineController

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.text).font(.system(size: 12, weight: .semibold))
            if let action = toast.action {
                Button { c.runToastAction() } label: {
                    Text(action + (action == "Undo" ? "  ⌘Z" : ""))
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14).padding(.trailing, toast.action == nil ? 14 : 5).padding(.vertical, toast.action == nil ? 7 : 4)
        .background(Glass().clipShape(Capsule()))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .allowsHitTesting(toast.action != nil)
    }
}

/// Shown while clips are ⌘-clicked: copy or paste them all at once.
struct PickBar: View {
    let c: LineController

    var body: some View {
        HStack(spacing: 8) {
            Text("\(c.picked.count) picked")
                .font(.system(size: 12, weight: .semibold))
                .padding(.leading, 6)
            Button("Copy Together  ⌘C") { c.copyPicked(paste: false) }
                .buttonStyle(PillButton(primary: false))
            Button("Paste Together  ↩") { c.copyPicked(paste: true) }
                .buttonStyle(PillButton(primary: true))
            BarButton(symbol: "xmark", help: "Clear (Esc)") { c.clearPicks() }
        }
        .padding(4)
        .background(Glass().clipShape(Capsule()))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

struct PillButton: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(primary ? Color.accentColor : Color.primary.opacity(0.1)))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// "Removed in 1:42" on a secret's card.
struct SecretCountdown: View {
    let clip: Clip
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let minutes = Prefs.shared.secretMinutes
            Group {
                if clip.lineID != nil || minutes == 0 {
                    Text("Kept · masked")
                } else {
                    let left = max(0, Int(clip.created.addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSince(ctx.date)))
                    Text("Removed in \(left / 60):\(String(format: "%02d", left % 60))")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }
}
