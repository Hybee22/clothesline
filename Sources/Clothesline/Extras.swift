import AppKit
import Foundation

// MARK: - Secrets

/// Spots text that looks like a key, token or password, so its card can be masked and expire.
enum Secrets {
    private static let patterns: [NSRegularExpression] = [
        #"\bsk-[A-Za-z0-9_\-]{20,}"#,                         // OpenAI / Anthropic
        #"\bgh[pousr]_[A-Za-z0-9]{30,}"#,                     // GitHub
        #"\bgithub_pat_[A-Za-z0-9_]{40,}"#,
        #"\bglpat-[A-Za-z0-9_\-]{20,}"#,                      // GitLab
        #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#,                      // AWS access key
        #"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#,                  // Slack
        #"\b[sr]k_(live|test)_[A-Za-z0-9]{16,}"#,             // Stripe
        #"\bAIza[0-9A-Za-z_\-]{35}\b"#,                       // Google
        #"\bnpm_[A-Za-z0-9]{36}\b"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#, // JWT
        #"\b[a-z][a-z0-9+.\-]*://[^\s:/@]+:[^\s@/]{3,}@"#,    // postgres://user:password@host
        #"(?i)(api[_-]?key|secret|token|passw(or)?d|pwd)[A-Za-z_]*\s*[:=]\s*["']?[^\s"']{8,}"#, // ACCESS_TOKEN=…
        #"\bBearer\s+[A-Za-z0-9._\-]{20,}"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    static func looksSecret(_ s: String) -> Bool {
        guard s.count <= 20_000 else { return false }
        let range = NSRange(s.startIndex..., in: s)
        if patterns.contains(where: { $0.firstMatch(in: s, range: range) != nil }) { return true }
        return isRandomToken(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// One long, random-looking word with upper case, lower case and digits (but not a path or URL).
    private static func isRandomToken(_ t: String) -> Bool {
        guard (32...512).contains(t.count), !t.contains(where: \.isWhitespace),
              !t.hasPrefix("/"), !t.hasPrefix("~"), !t.contains("://") else { return false }
        guard t.contains(where: \.isUppercase), t.contains(where: \.isLowercase), t.contains(where: \.isNumber) else { return false }
        var freq: [Character: Double] = [:]
        for ch in t { freq[ch, default: 0] += 1 }
        let n = Double(t.count)
        let entropy = -freq.values.reduce(0) { $0 + ($1 / n) * log2($1 / n) }
        return entropy >= 4.2
    }

    /// A safe glimpse of a secret: its first few characters and dots.
    static func mask(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("-----BEGIN") { return (t.split(separator: "\n").first.map(String.init) ?? "Private key") + "\n••••••••••••" }
        let keep = min(6, max(2, t.count / 6))
        return String(t.prefix(keep)) + String(repeating: "•", count: min(18, max(6, t.count - keep)))
    }
}

// MARK: - Colour formats

enum ColorFormats {
    static func all(_ text: String) -> [(label: String, value: String)] {
        guard let ns = ColorParse.color(text), let c = ns.usingColorSpace(.sRGB) else { return [] }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent, a = c.alphaComponent
        let R = Int((r * 255).rounded()), G = Int((g * 255).rounded()), B = Int((b * 255).rounded())
        let hasAlpha = a < 0.999
        let alpha2 = String(format: "%.2g", a)
        var hex = String(format: "#%02X%02X%02X", R, G, B)
        if hasAlpha { hex += String(format: "%02X", Int((a * 255).rounded())) }
        let (h, s, l) = hsl(r, g, b)
        let f: (CGFloat) -> String = { String(format: "%.3f", $0) }
        return [
            ("HEX", hex),
            ("RGB", hasAlpha ? "rgba(\(R), \(G), \(B), \(alpha2))" : "rgb(\(R), \(G), \(B))"),
            ("HSL", hasAlpha ? "hsla(\(h), \(s)%, \(l)%, \(alpha2))" : "hsl(\(h), \(s)%, \(l)%)"),
            ("SwiftUI", "Color(red: \(f(r)), green: \(f(g)), blue: \(f(b))" + (hasAlpha ? ", opacity: \(f(a)))" : ")")),
            ("Flutter", String(format: "Color(0x%02X%02X%02X%02X)", Int((a * 255).rounded()), R, G, B)),
        ]
    }

    private static func hsl(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (Int, Int, Int) {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, Int((l * 100).rounded())) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: CGFloat
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        return (Int(h.rounded()) % 360, Int((s * 100).rounded()), Int((l * 100).rounded()))
    }
}

// MARK: - Peg sound

/// A small wooden "click" made on the fly, so the app ships no sound files.
@MainActor
enum PegSound {
    private static let sound: NSSound? = {
        let rate = 44_100.0
        let count = Int(rate * 0.12)
        var samples = [Int16](repeating: 0, count: count)
        var seed: UInt32 = 0x9E37_79B9
        func noise() -> Double {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Double(seed) / Double(UInt32.max) * 2 - 1
        }
        var lp = 0.0
        for i in 0..<count {
            let t = Double(i) / rate
            // The spring snapping shut: a bright tick, then a softer second one.
            let tick = noise() * exp(-t / 0.0022)
            let t2 = t - 0.021
            let tick2 = t2 > 0 ? noise() * exp(-t2 / 0.003) * 0.45 : 0
            lp += 0.35 * (tick + tick2 - lp)
            // The wood knocking against the line.
            let knock = sin(2 * .pi * 210 * t) * exp(-t / 0.028) * 0.55 + sin(2 * .pi * 520 * t) * exp(-t / 0.012) * 0.25
            let v = max(-1, min(1, lp * 0.9 + knock))
            samples[i] = Int16(v * 22_000)
        }
        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = count * 2
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(UInt32(bytes))
        for s in samples { put(s) }
        let snd = NSSound(data: data)
        snd?.volume = 0.35
        return snd
    }()

    static func play() {
        guard Prefs.shared.pegSound, let s = sound else { return }
        if s.isPlaying { s.stop() }
        s.play()
    }
}
