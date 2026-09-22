import MacAttackCore
import SpriteKit

/// A cartoon stand-in for one anonymous person. Container position follows the track (lerped at
/// 60 fps); `body` carries reactions; `bobber` carries the idle wobble.
@MainActor
public final class CharacterNode: SKNode {
    public let personID: String
    private(set) var character: CharacterType
    public let bobber = SKNode()
    public let body: SKSpriteNode
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 100, height: 22))
    private let tag: SKLabelNode
    private var hitsLabel: SKLabelNode?
    public var targetPosition: CGPoint = .zero
    public var targetSize: CGFloat = 140
    private(set) var currentSize: CGFloat = 140
    private var hits = 0

    public init(person: Person) {
        personID = person.id
        character = person.character
        body = SKSpriteNode(texture: Textures.emoji(person.character.emoji, size: 256))
        tag = comicLabel("\(person.character.displayName) #\(person.number)", size: 16, color: .white)
        super.init()
        shadow.fillColor = NSColor.black.withAlphaComponent(0.28)
        shadow.strokeColor = .clear
        addChild(shadow)
        addChild(bobber)
        bobber.addChild(body)
        addChild(tag)
        applySize(targetSize)
        let bob = SKAction.sequence([
            .moveBy(x: 0, y: 8, duration: 0.55), .moveBy(x: 0, y: -8, duration: 0.55),
        ])
        bob.timingMode = .easeInEaseOut
        bobber.run(.repeatForever(bob), withKey: "bob")
        let wobble = SKAction.sequence([.rotate(toAngle: 0.06, duration: 0.8), .rotate(toAngle: -0.06, duration: 0.8)])
        wobble.timingMode = .easeInEaseOut
        bobber.run(.repeatForever(wobble), withKey: "wobble")
    }

    public required init?(coder: NSCoder) { fatalError() }

    public func step(_ dt: Double) {
        let k = CGFloat(min(1, dt * 9))
        position = CGPoint(x: position.x + (targetPosition.x - position.x) * k,
                           y: position.y + (targetPosition.y - position.y) * k)
        let s = currentSize + (targetSize - currentSize) * CGFloat(min(1, dt * 4))
        if abs(s - currentSize) > 0.5 { applySize(s) }
    }

    private func applySize(_ s: CGFloat) {
        currentSize = s
        body.size = CGSize(width: s * body.texture!.size().width / body.texture!.size().height, height: s)
        shadow.setScale(s / 140)
        shadow.position = CGPoint(x: 0, y: -s * 0.52)
        tag.position = CGPoint(x: 0, y: -s * 0.52 - 18)
        hitsLabel?.position = CGPoint(x: s * 0.45, y: s * 0.45)
    }

    public func setCharacter(_ c: CharacterType) {
        character = c
        body.texture = Textures.emoji(c.emoji, size: 256)
        applySize(currentSize)
        if let n = tag.attributedText?.string.split(separator: "#").last {
            tag.attributedText = comicLabel("\(c.displayName) #\(n)", size: 16).attributedText
        }
    }

    public func registerHit() {
        hits += 1
        if hitsLabel == nil {
            let l = comicLabel("", size: 18, color: .systemYellow)
            addChild(l)
            hitsLabel = l
        }
        hitsLabel?.attributedText = comicLabel("💥×\(hits)", size: 18, color: .systemYellow).attributedText
        applySize(currentSize)
        hitsLabel?.run(.sequence([.scale(to: 1.6, duration: 0.1), .scale(to: 1, duration: 0.2)]))
    }

    // MARK: - Reactions

    public func react(_ r: ReactionKind, intensity: Double, fx: FXLayer) {
        body.removeAction(forKey: "react")
        body.setScale(1); body.zRotation = 0; body.alpha = 1; body.position = .zero
        let i = CGFloat(0.6 + intensity * 0.8)
        let a: SKAction
        switch r {
        case .dodge:
            let dx = (Bool.random() ? 1 : -1) * 90 * i
            let out = SKAction.moveBy(x: dx, y: 10, duration: 0.14); out.timingMode = .easeOut
            let back = SKAction.moveBy(x: -dx, y: -10, duration: 0.35); back.timingMode = .easeInEaseOut
            a = .sequence([out, .wait(forDuration: 0.25), back])
        case .jump:
            let up = SKAction.moveBy(x: 0, y: 110 * i, duration: 0.22); up.timingMode = .easeOut
            let down = SKAction.moveBy(x: 0, y: -110 * i, duration: 0.25); down.timingMode = .easeIn
            let squash = SKAction.sequence([.scaleX(to: 1.25, y: 0.75, duration: 0.07), .scale(to: 1, duration: 0.12)])
            a = .sequence([up, down, squash])
        case .shake:
            let s = SKAction.sequence([.rotate(toAngle: 0.25, duration: 0.05), .rotate(toAngle: -0.25, duration: 0.05)])
            a = .sequence([.repeat(s, count: Int(4 + intensity * 5)), .rotate(toAngle: 0, duration: 0.05)])
        case .spin:
            a = .sequence([.rotate(byAngle: .pi * 2 * CGFloat(1 + Int(intensity * 2.5)), duration: 0.7), .rotate(toAngle: 0, duration: 0)])
            fx.labelPop("@_@", at: parentPoint(dy: currentSize * 0.7), size: 26, color: .systemPink)
        case .shrink:
            a = .sequence([.scale(to: 0.35, duration: 0.18), .wait(forDuration: 0.7), .scale(to: 1, duration: 0.3)])
            fx.labelPop("eep!", at: parentPoint(dy: currentSize * 0.4), size: 22, color: .white)
        case .grow:
            let g = SKAction.scale(to: 1 + 0.9 * i, duration: 0.25); g.timingMode = .easeOut
            a = .sequence([g, .wait(forDuration: 0.6), .scale(to: 1, duration: 0.35)])
            fx.labelPop("POWER UP!", at: parentPoint(dy: currentSize * 0.9), size: 24, color: .systemGreen)
        case .explode:
            fx.burst(at: parentPoint(), texture: Textures.emoji(character.emoji, size: 64), count: Int(14 + intensity * 20),
                     speed: 420, lifetime: 1.0, scale: 0.45, gravity: 600, spin: true)
            fx.burst(at: parentPoint(), texture: Textures.dot, count: 40, speed: 300, lifetime: 0.6, scale: 0.5, colors: NSColor.candy)
            a = .sequence([.fadeOut(withDuration: 0.05), .scale(to: 0, duration: 0), .wait(forDuration: 0.9),
                           .fadeIn(withDuration: 0), .scale(to: 1.25, duration: 0.18), .scale(to: 1, duration: 0.12)])
        case .celebrate:
            let hop = SKAction.sequence([.moveBy(x: 0, y: 60, duration: 0.15), .moveBy(x: 0, y: -60, duration: 0.15)])
            a = .group([.repeat(hop, count: 3),
                        .sequence([.rotate(toAngle: 0.3, duration: 0.15), .rotate(toAngle: -0.3, duration: 0.3), .rotate(toAngle: 0, duration: 0.15)])])
            fx.burst(at: parentPoint(dy: currentSize * 0.5), texture: Textures.emoji("🎉", size: 64), count: 10, speed: 260,
                     lifetime: 1.0, scale: 0.5, gravity: 300, spin: true)
            fx.labelPop("YAY!", at: parentPoint(dy: currentSize * 0.8), size: 28, color: .systemYellow)
        }
        body.run(a, withKey: "react")
    }

    public func spawnAnimation(fx: FXLayer) {
        setScale(0.01)
        run(.sequence([.scale(to: 1.25, duration: 0.22), .scale(to: 0.92, duration: 0.1), .scale(to: 1, duration: 0.08)]))
        fx.burst(at: position, texture: Textures.emoji("✨", size: 48), count: 14, speed: 220, lifetime: 0.8, scale: 0.6)
    }

    private func parentPoint(dy: CGFloat = 0) -> CGPoint { CGPoint(x: position.x, y: position.y + dy) }
}
