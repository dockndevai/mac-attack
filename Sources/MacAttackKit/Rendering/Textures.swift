import AppKit
import SpriteKit

/// Procedurally generated textures (emoji sprites, soft dots, bubbles, confetti). Cached forever;
/// the set is small and bounded.
@MainActor
public enum Textures {
    private static var cache: [String: SKTexture] = [:]

    public static func emoji(_ s: String, size: CGFloat = 128) -> SKTexture {
        let key = "e:\(s):\(Int(size))"
        if let t = cache[key] { return t }
        let str = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let b = str.size()
        let img = NSImage(size: NSSize(width: ceil(b.width) + 4, height: ceil(b.height) + 4), flipped: false) { _ in
            str.draw(at: NSPoint(x: 2, y: 2))
            return true
        }
        let t = SKTexture(image: img)
        cache[key] = t
        return t
    }

    public static var dot: SKTexture { draw("dot", 64) { r in
        let g = NSGradient(colors: [.white, NSColor.white.withAlphaComponent(0)])!
        g.draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: .zero)
    } }

    public static var disc: SKTexture { draw("disc", 64) { r in
        NSColor.white.setFill()
        NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)).fill()
    } }

    public static var ring: SKTexture { draw("ring", 128) { r in
        let p = NSBezierPath(ovalIn: r.insetBy(dx: 6, dy: 6))
        p.lineWidth = 6
        NSColor.white.setStroke()
        p.stroke()
    } }

    public static var bubble: SKTexture { draw("bubble", 96) { r in
        let inner = r.insetBy(dx: 4, dy: 4)
        NSColor(calibratedRed: 0.7, green: 0.9, blue: 1, alpha: 0.18).setFill()
        NSBezierPath(ovalIn: inner).fill()
        let p = NSBezierPath(ovalIn: inner)
        p.lineWidth = 3
        NSColor(calibratedRed: 0.85, green: 0.95, blue: 1, alpha: 0.9).setStroke()
        p.stroke()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: inner.minX + inner.width * 0.22, y: inner.minY + inner.height * 0.6,
                                    width: inner.width * 0.22, height: inner.height * 0.14)).fill()
    } }

    public static var confetti: SKTexture { draw("confetti", 24, height: 12) { r in
        NSColor.white.setFill()
        NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
    } }

    public static func gradient(_ size: CGSize, top: NSColor, bottom: NSColor) -> SKTexture {
        let img = NSImage(size: NSSize(width: max(8, size.width), height: max(8, size.height)), flipped: false) { r in
            NSGradient(starting: bottom, ending: top)!.draw(in: r, angle: 90)
            return true
        }
        return SKTexture(image: img)
    }

    private static func draw(_ key: String, _ w: CGFloat, height: CGFloat? = nil, _ body: @escaping (NSRect) -> Void) -> SKTexture {
        if let t = cache[key] { return t }
        let img = NSImage(size: NSSize(width: w, height: height ?? w), flipped: false) { r in body(r); return true }
        let t = SKTexture(image: img)
        cache[key] = t
        return t
    }
}

/// Cartoon text with an outline.
@MainActor
public func comicLabel(_ text: String, size: CGFloat, color: NSColor = .white, stroke: NSColor = .black) -> SKLabelNode {
    let font = NSFont(name: "Chalkboard SE Bold", size: size) ?? NSFont(name: "Marker Felt Wide", size: size)
        ?? .boldSystemFont(ofSize: size)
    let l = SKLabelNode()
    l.attributedText = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color, .strokeColor: stroke, .strokeWidth: -3.5,
    ])
    l.verticalAlignmentMode = .center
    l.horizontalAlignmentMode = .center
    return l
}

extension NSColor {
    public static let candy: [NSColor] = [
        NSColor(calibratedRed: 1, green: 0.35, blue: 0.45, alpha: 1), NSColor(calibratedRed: 1, green: 0.78, blue: 0.2, alpha: 1),
        NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.5, alpha: 1), NSColor(calibratedRed: 0.3, green: 0.65, blue: 1, alpha: 1),
        NSColor(calibratedRed: 0.72, green: 0.45, blue: 1, alpha: 1), NSColor(calibratedRed: 1, green: 0.55, blue: 0.2, alpha: 1),
    ]
    public static let rainbow: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple]
}
