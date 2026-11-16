// Draws Clothesline's app icon: a line across a dusk sky with three clips on pegs.
// Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)   // draw top-down

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

// Squircle background
let inset: CGFloat = 100
let bg = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let squircle = NSBezierPath(roundedRect: bg, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
color(0.2, 0.2, 0.3).setFill()
squircle.fill()
ctx.restoreGState()
ctx.saveGState()
squircle.addClip()
NSGradient(colors: [color(0.36, 0.55, 0.98), color(0.55, 0.42, 0.92), color(0.98, 0.56, 0.48)])!
    .draw(in: bg, angle: 90)
ctx.restoreGState()

// Rope
let left = CGPoint(x: bg.minX - 10, y: 330), right = CGPoint(x: bg.maxX + 10, y: 330)
let rope = NSBezierPath()
rope.move(to: left)
rope.curve(to: right, controlPoint1: CGPoint(x: 380, y: 430), controlPoint2: CGPoint(x: 640, y: 430))
ctx.saveGState()
squircle.addClip()
ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 10, color: NSColor.black.withAlphaComponent(0.3).cgColor)
rope.lineWidth = 16
color(0.95, 0.88, 0.74).setStroke()
rope.stroke()
ctx.restoreGState()
ctx.saveGState()
squircle.addClip()
rope.lineWidth = 16
rope.setLineDash([6, 12], count: 2, phase: 0)
color(0.68, 0.56, 0.42).setStroke()
rope.stroke()
ctx.restoreGState()

func ropeY(_ x: CGFloat) -> CGFloat {
    // y on the cubic, sampled
    var best: CGFloat = 330, bestD = CGFloat.greatestFiniteMagnitude
    for i in 0...200 {
        let t = CGFloat(i) / 200
        let mt = 1 - t
        let px = mt * mt * mt * left.x + 3 * mt * mt * t * 380 + 3 * mt * t * t * 640 + t * t * t * right.x
        let py = mt * mt * mt * left.y + 3 * mt * mt * t * 430 + 3 * mt * t * t * 430 + t * t * t * right.y
        if abs(px - x) < bestD { bestD = abs(px - x); best = py }
    }
    return best
}

func card(x: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat, fill: [NSColor], lines: Bool, peg: NSColor) {
    let y = ropeY(x)
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.rotate(by: angle)
    let r = NSRect(x: -w / 2, y: 18, width: w, height: h)
    let p = NSBezierPath(roundedRect: r, xRadius: 30, yRadius: 30)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 22), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    fill[0].setFill()
    p.fill()
    ctx.restoreGState()
    NSGradient(colors: fill)!.draw(in: p, angle: 90)
    if lines {
        color(0.55, 0.6, 0.75, 0.55).setFill()
        for (i, lw) in [0.72, 0.58, 0.66, 0.4].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: r.minX + 28, y: r.minY + 60 + CGFloat(i) * 38, width: (w - 56) * lw, height: 14),
                         xRadius: 7, yRadius: 7).fill()
        }
    }
    // peg
    let pegRect = NSRect(x: -20, y: -26, width: 40, height: 84)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 6, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    let halfL = NSBezierPath(roundedRect: NSRect(x: pegRect.minX, y: pegRect.minY, width: 18, height: pegRect.height), xRadius: 7, yRadius: 7)
    let halfR = NSBezierPath(roundedRect: NSRect(x: pegRect.minX + 22, y: pegRect.minY, width: 18, height: pegRect.height), xRadius: 7, yRadius: 7)
    peg.setFill()
    halfL.fill()
    halfR.fill()
    ctx.restoreGState()
    color(1, 1, 1, 0.35).setFill()
    NSBezierPath(rect: NSRect(x: pegRect.minX + 3, y: pegRect.minY + 8, width: 3, height: pegRect.height - 16)).fill()
    color(0.85, 0.86, 0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: -24, y: 2, width: 48, height: 12), xRadius: 6, yRadius: 6).fill()
    ctx.restoreGState()
}

ctx.saveGState()
squircle.addClip()
card(x: 300, w: 200, h: 250, angle: 0.06, fill: [color(1, 1, 1), color(0.92, 0.93, 0.97)], lines: true, peg: color(0.86, 0.68, 0.46))
card(x: 520, w: 190, h: 220, angle: -0.04, fill: [color(1, 0.62, 0.42), color(0.98, 0.45, 0.38)], lines: false, peg: color(0.55, 0.78, 0.98))
card(x: 730, w: 190, h: 240, angle: 0.08, fill: [color(0.42, 0.86, 0.72), color(0.25, 0.7, 0.6)], lines: false, peg: color(0.98, 0.82, 0.45))
ctx.restoreGState()

// Glass edge
ctx.saveGState()
squircle.lineWidth = 3
color(1, 1, 1, 0.35).setStroke()
squircle.stroke()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
