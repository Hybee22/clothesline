import Foundation

/// Pendulum physics for the cards: each one swings on its peg and settles.
@Observable @MainActor
final class Swing {
    private(set) var angle: [UUID: Double] = [:]
    @ObservationIgnored private var velocity: [UUID: Double] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var last = Date()

    private let stiffness = 34.0   // ~1 s period
    private let damping = 2.1
    private let maxAngle = 0.42

    // The rope dipping under a card: a spring, so it sinks gently and bounces when tugged.
    private(set) var dipX: CGFloat = 0
    private(set) var dip: CGFloat = 0
    @ObservationIgnored private var dipV: CGFloat = 0
    @ObservationIgnored private var dipTarget: CGFloat = 0
    @ObservationIgnored private var dipTargetX: CGFloat = 0
    @ObservationIgnored private var dipActive = false

    /// Rest the rope at `depth` points below normal at `x` (0 lets it spring back).
    func setDip(x: CGFloat, depth: CGFloat) {
        guard x != dipTargetX || depth != dipTarget else { return }
        if dip < 0.3 && dipTarget == 0 { dipX = x }
        dipTargetX = x
        dipTarget = depth
        dipActive = true
        start()
    }

    /// Yank the rope down at `x`, as when a card is copied.
    func tug(x: CGFloat, strength: CGFloat = 110) {
        if dip < 0.3 && dipTarget == 0 { dipX = x }
        dipTargetX = x
        dipV += Motion.reduced ? strength * 0.3 : strength
        dipActive = true
        start()
    }

    func kick(_ id: UUID, _ v: Double) {
        let v = Motion.reduced ? v * 0.3 : v
        velocity[id, default: 0] = max(-6, min(6, velocity[id, default: 0] + v))
        if angle[id] == nil { angle[id] = 0 }
        start()
    }

    /// A ripple along the line, as when the line drops or gets tugged.
    func ripple(_ ids: [UUID], strength: Double = 1.4) {
        for (i, id) in ids.enumerated() {
            let delay = Double(i) * 0.045
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.kick(id, Double.random(in: 0.6...1.0) * strength * (i.isMultiple(of: 2) ? 1 : -1))
            }
        }
    }

    private func start() {
        guard timer == nil else { return }
        last = Date()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        let now = Date()
        let dt = min(1.0 / 30.0, now.timeIntervalSince(last))
        last = now
        var next = angle
        for (id, a) in angle {
            var v = velocity[id, default: 0]
            let acc = -stiffness * sin(a) - damping * v
            v += acc * dt
            var na = a + v * dt
            if abs(na) > maxAngle { na = maxAngle * (na > 0 ? 1 : -1); v *= -0.4 }
            if abs(na) < 0.0008 && abs(v) < 0.004 {
                next[id] = nil
                velocity[id] = nil
            } else {
                next[id] = na
                velocity[id] = v
            }
        }
        angle = next
        if dipActive {
            dipX += (dipTargetX - dipX) * min(1, CGFloat(dt) * 14)
            let acc = -170 * (dip - dipTarget) - 10 * dipV
            dipV += acc * CGFloat(dt)
            dip = max(-6, dip + dipV * CGFloat(dt))
            if abs(dip - dipTarget) < 0.05 && abs(dipV) < 0.08 && abs(dipX - dipTargetX) < 0.5 {
                dip = dipTarget
                dipV = 0
                dipX = dipTargetX
                dipActive = false
            }
        }
        if next.isEmpty && !dipActive {
            timer?.invalidate()
            timer = nil
        }
    }
}
