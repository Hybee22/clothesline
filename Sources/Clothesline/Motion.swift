import AppKit
import SwiftUI

// MARK: - Motion settings

@MainActor
enum Motion {
    /// macOS "Reduce motion": swings get smaller, the breeze stops and cards fade instead of flying.
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// After dark (7 pm to 6 am), or forced on for testing with `--cmd night`.
    static var nightOverride: Bool?
    static var isNight: Bool {
        if let nightOverride { return nightOverride }
        let h = Calendar.current.component(.hour, from: .now)
        return h >= 19 || h < 6
    }
}

/// A light tick on a Force Touch trackpad.
@MainActor
enum Haptics {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    static func thump() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

// MARK: - Rope load

/// Places where the rope is pulled down: under the hovered or tugged card, and under heavy image cards.
struct RopeLoad {
    var points: [(x: CGFloat, depth: CGFloat)] = []
    static let flat = RopeLoad()
    static let spread: CGFloat = 95

    func offset(_ x: CGFloat) -> CGFloat {
        points.reduce(0) { sum, p in
            let u = (x - p.x) / Self.spread
            return sum + p.depth * exp(-u * u)
        }
    }
    func slope(_ x: CGFloat) -> CGFloat {
        points.reduce(0) { sum, p in
            let u = (x - p.x) / Self.spread
            return sum + p.depth * exp(-u * u) * (-2 * u / Self.spread)
        }
    }
}

// MARK: - How cards arrive and leave

enum LeaveStyle: Equatable {
    case flutter          // taken down: drifts away like a leaf
    case basket           // pushed off the full Inbox into the basket
    case burn             // an expired secret curls up and fades
    case slide(CGFloat)   // carried off by the pulley when switching lines
    case fade             // Reduce Motion
}

enum ArriveStyle: Equatable {
    case drop
    case slide(CGFloat)
    case fade
}

struct Leave: ViewModifier, Animatable {
    var p: Double
    let style: LeaveStyle
    /// How far the basket is from the card, for `.basket`.
    let toBasket: CGSize

    var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    func body(content: Content) -> some View {
        switch style {
        case .flutter:
            let s = sin(p * .pi * 2.4)
            content
                .rotation3DEffect(.degrees(38 * sin(p * .pi * 3)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .rotationEffect(.degrees(26 * sin(p * .pi * 2.4 + 0.6) + 14 * p), anchor: .top)
                .offset(x: 48 * s, y: 340 * pow(p, 1.6))
                .opacity(1 - max(0, (p - 0.55) / 0.45))
        case .basket:
            let e = p * p * (3 - 2 * p)
            content
                .scaleEffect(1 - 0.78 * p, anchor: .top)
                .rotationEffect(.degrees(50 * p), anchor: .top)
                .offset(x: toBasket.width * e, y: toBasket.height * p - 46 * sin(.pi * p))
                .opacity(1 - max(0, (p - 0.75) / 0.25))
        case .burn:
            content
                .rotation3DEffect(.degrees(75 * p), axis: (x: 1, y: -1, z: 0), anchor: .bottomTrailing, perspective: 0.6)
                .scaleEffect(1 - 0.45 * p, anchor: .bottomTrailing)
                .saturation(1 - p)
                .brightness(-0.25 * p)
                .blur(radius: 5 * p)
                .opacity(1 - p)
        case .slide(let dx):
            content
                .rotationEffect(.degrees(Double(dx > 0 ? -7 : 7) * sin(.pi * p)), anchor: .top)
                .offset(x: dx * p)
        case .fade:
            content.opacity(1 - p)
        }
    }
}

struct Arrive: ViewModifier, Animatable {
    var p: Double
    let style: ArriveStyle

    var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    func body(content: Content) -> some View {
        switch style {
        case .drop:
            content.offset(y: -240 * p).opacity(1 - p * 0.6)
        case .slide(let dx):
            content
                .rotationEffect(.degrees(Double(dx > 0 ? 7 : -7) * sin(.pi * p)), anchor: .top)
                .offset(x: dx * p)
        case .fade:
            content.opacity(1 - p)
        }
    }
}

extension AnyTransition {
    static func leave(_ style: LeaveStyle, toBasket: CGSize = .zero) -> AnyTransition {
        let t = AnyTransition.modifier(active: Leave(p: 1, style: style, toBasket: toBasket),
                                       identity: Leave(p: 0, style: style, toBasket: toBasket))
        switch style {
        case .flutter: return t.animation(.easeIn(duration: 1.0))
        case .basket: return t.animation(.easeInOut(duration: 0.7))
        case .burn: return t.animation(.easeIn(duration: 0.9))
        case .slide: return t.animation(.spring(response: 0.6, dampingFraction: 0.9))
        case .fade: return t.animation(.easeOut(duration: 0.25))
        }
    }
    static func arrive(_ style: ArriveStyle) -> AnyTransition {
        .modifier(active: Arrive(p: 1, style: style), identity: Arrive(p: 0, style: style))
    }
}

// MARK: - A peg that pops off when a card is taken down

struct LoosePeg: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let hue: Double?
}

struct PegPop: ViewModifier, Animatable {
    var p: Double
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(620 * p))
            .offset(x: 34 * p, y: -46 * sin(.pi * min(1, p * 1.6)) + 260 * p * p)
            .opacity(1 - max(0, (p - 0.6) / 0.4))
    }
}

struct LoosePegView: View {
    let peg: LoosePeg
    @State private var p = 0.0
    var body: some View {
        Peg(hue: peg.hue, open: true)
            .modifier(PegPop(p: p))
            .position(x: peg.x, y: peg.y + 10)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.linear(duration: 0.85)) { p = 1 } }
    }
}

// MARK: - Fairy lights

/// Warm bulbs along the rope after dark, each twinkling at its own pace.
struct FairyLights: View {
    let width: CGFloat
    let sag: CGFloat
    let load: RopeLoad

    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.78, blue: 0.42),  // amber
        Color(red: 1.0, green: 0.93, blue: 0.78),  // warm white
        Color(red: 1.0, green: 0.62, blue: 0.58),  // soft red
        Color(red: 0.98, green: 0.86, blue: 0.48), // pale gold
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, _ in
                let step: CGFloat = 54
                var x = Layout.inset + 34
                var i = 0
                while x < width - Layout.inset - 30 {
                    let y = Layout.ropeY(x, sag: sag, width: width, load: load) + 7
                    let seed = Double(i) * 1.7
                    let glow = 0.62 + 0.38 * sin(t * (1.1 + Double(i % 5) * 0.23) + seed)
                    let color = Self.colors[i % Self.colors.count]
                    // Halo
                    let r: CGFloat = 13
                    g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                           with: .radialGradient(Gradient(colors: [color.opacity(0.55 * glow), color.opacity(0)]),
                                                 center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                    // Wire twist and bulb
                    g.fill(Path(CGRect(x: x - 1, y: y - 6, width: 2, height: 3)), with: .color(Color(white: 0.25)))
                    g.fill(Path(ellipseIn: CGRect(x: x - 2.6, y: y - 3.4, width: 5.2, height: 6.8)),
                           with: .color(color.opacity(0.55 + 0.45 * glow)))
                    g.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 2.4, width: 1.6, height: 2.2)),
                           with: .color(.white.opacity(0.7 * glow)))
                    x += step
                    i += 1
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Paper details

/// A rectangle with its bottom-right corner folded away, for clips a few days old.
struct DogEarMask: Shape {
    let fold: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - fold))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The underside of the folded corner.
struct DogEarFlap: View {
    let fold: CGFloat
    let dark: Bool
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: fold, y: 0))
            p.addLine(to: CGPoint(x: 0, y: fold))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.closeSubpath()
        }
        .fill(LinearGradient(colors: dark ? [Color(white: 0.34), Color(white: 0.22)] : [Color(white: 0.86), Color(white: 0.97)],
                             startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: fold, height: fold)
        .shadow(color: .black.opacity(0.3), radius: 1.5, x: -1, y: -1)
    }
}

/// A red wax seal for secret cards.
struct WaxSeal: View {
    var body: some View {
        ZStack {
            // A slightly irregular blob of wax
            Path { p in
                let n = 18
                for k in 0...n {
                    let a = Double(k) / Double(n) * 2 * .pi
                    let r = 15 + (k.isMultiple(of: 2) ? 1.6 : -0.6) + sin(a * 3) * 0.8
                    let pt = CGPoint(x: 17 + r * cos(a), y: 17 + r * sin(a))
                    if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
            }
            .fill(RadialGradient(colors: [Color(red: 0.86, green: 0.18, blue: 0.16), Color(red: 0.52, green: 0.05, blue: 0.07)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 22))
            Circle()
                .strokeBorder(Color(red: 0.42, green: 0.03, blue: 0.05).opacity(0.7), lineWidth: 1.4)
                .frame(width: 21, height: 21)
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(red: 0.98, green: 0.62, blue: 0.55).opacity(0.85))
                .shadow(color: .black.opacity(0.35), radius: 0.5, y: 0.5)
        }
        .frame(width: 34, height: 34)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1.5)
        .rotationEffect(.degrees(-12))
    }
}
