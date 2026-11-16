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

    func kick(_ id: UUID, _ v: Double) {
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
        if next.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
}
