import MacAttackCore
import SpriteKit

/// Layer that draws projectiles, area effects and particle bursts. Every node it creates removes
/// itself when done; `canSpawn` caps live nodes so a runaway director can't melt the renderer.
@MainActor
public final class FXLayer: SKNode {
    public var bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    public var canSpawn: Bool { children.count < 260 }

    public struct Target {
        var id: String
        var point: CGPoint
        var size: CGFloat
    }

    // MARK: - Primitives

    public func burst(at p: CGPoint, texture: SKTexture, count: Int, speed: CGFloat, lifetime: CGFloat, scale: CGFloat,
               colors: [NSColor]? = nil, gravity: CGFloat = 0, spin: Bool = false,
               angle: CGFloat = 0, angleRange: CGFloat = .pi * 2, emitDuration: CGFloat = 0.05,
               positionRange: CGVector = .zero, alphaFade: Bool = true) {
        guard canSpawn, count > 0 else { return }
        let palette: [NSColor] = colors ?? []
        let groups = max(1, min(4, palette.count))
        for g in 0..<groups {
            let e = SKEmitterNode()
            e.particleTexture = texture
            let n = max(1, count / groups)
            e.numParticlesToEmit = n
            e.particleBirthRate = CGFloat(n) / max(0.01, emitDuration)
            e.particleLifetime = lifetime
            e.particleLifetimeRange = lifetime * 0.4
            e.emissionAngle = angle
            e.emissionAngleRange = angleRange
            e.particleSpeed = speed
            e.particleSpeedRange = speed * 0.7
            e.particleAlpha = 1
            e.particleAlphaSpeed = alphaFade ? -1 / lifetime : 0
            e.particleScale = scale
            e.particleScaleRange = scale * 0.5
            e.particleScaleSpeed = -scale * 0.3 / lifetime
            e.yAcceleration = -gravity
            e.particlePositionRange = positionRange
            if spin {
                e.particleRotationRange = .pi * 2
                e.particleRotationSpeed = 4
            }
            if !palette.isEmpty {
                e.particleColorBlendFactor = 1
                e.particleColor = palette[g % palette.count]
                e.particleColorSequence = nil
            }
            e.position = p
            e.targetNode = self
            addChild(e)
            e.run(.sequence([.wait(forDuration: Double(emitDuration + lifetime * 1.5 + 0.3)), .removeFromParent()]))
        }
    }

    public func labelPop(_ text: String, at p: CGPoint, size: CGFloat, color: NSColor, rotate: Bool = true) {
        guard canSpawn else { return }
        let l = comicLabel(text, size: size, color: color)
        l.position = p
        l.zPosition = 50
        l.setScale(0.1)
        l.zRotation = rotate ? CGFloat.random(in: -0.25...0.25) : 0
        addChild(l)
        l.run(.sequence([
            .scale(to: 1.25, duration: 0.12), .scale(to: 1, duration: 0.08),
            .group([.moveBy(x: 0, y: 45, duration: 0.9), .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.4)])]),
            .removeFromParent(),
        ]))
    }

    public func sprite(_ tex: SKTexture, height: CGFloat) -> SKSpriteNode {
        let s = SKSpriteNode(texture: tex)
        let ts = tex.size()
        s.size = CGSize(width: height * ts.width / max(1, ts.height), height: height)
        return s
    }

    public func fly(_ node: SKSpriteNode, from: CGPoint, to: CGPoint, arc: CGFloat, delay: Double, duration: Double,
             spin: CGFloat, impact: (() -> Void)? = nil) {
        guard canSpawn else { return }
        let path = CGMutablePath()
        path.move(to: from)
        path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + arc))
        node.position = from
        node.alpha = 0
        addChild(node)
        var seq: [SKAction] = [.wait(forDuration: delay), .fadeIn(withDuration: 0.05),
                               .group([.follow(path, asOffset: false, orientToPath: false, duration: max(0.1, duration)),
                                       .rotate(byAngle: spin, duration: max(0.1, duration))])]
        if let impact { seq.append(.run(impact)) }
        seq.append(.removeFromParent())
        node.run(.sequence(seq))
    }

    private func origin(toward t: CGPoint) -> CGPoint {
        let left = t.x > bounds.midX ? true : Bool.random() && t.x > bounds.width * 0.3
        return CGPoint(x: left ? bounds.minX - 60 : bounds.maxX + 60,
                       y: CGFloat.random(in: bounds.minY + bounds.height * 0.1...bounds.minY + bounds.height * 0.55))
    }

    private func jitter(_ p: CGPoint, _ r: CGFloat) -> CGPoint {
        CGPoint(x: p.x + CGFloat.random(in: -r...r), y: p.y + CGFloat.random(in: -r...r))
    }

    // MARK: - Events

    public func play(_ ev: GameEvent, targets: [Target]) {
        let i = CGFloat(ev.intensity)
        let d = ev.delay, dur = ev.duration
        let centre = targets.isEmpty ? CGPoint(x: bounds.midX, y: bounds.midY)
            : CGPoint(x: targets.map(\.point.x).reduce(0, +) / CGFloat(targets.count),
                      y: targets.map(\.point.y).reduce(0, +) / CGFloat(targets.count))
        let aim = targets.isEmpty ? [Target(id: "room", point: centre, size: 160)] : targets

        switch ev.effect {
        case .bubbleBlast:
            for t in aim {
                let from = origin(toward: t.point)
                let n = Int(6 + i * 14)
                for k in 0..<n {
                    let s = sprite(Textures.bubble, height: CGFloat.random(in: 28...72))
                    let last = k == n - 1
                    let stagger = Double(k) * 0.03
                    fly(s, from: jitter(from, 30), to: jitter(t.point, t.size * 0.4), arc: CGFloat.random(in: -60...80),
                        delay: d + stagger, duration: dur - stagger, spin: 0) { [weak self] in
                        self?.pop(at: s.position, size: s.size.height)
                        if last { self?.labelPop("POP!", at: CGPoint(x: t.point.x, y: t.point.y + t.size * 0.6), size: 30, color: .cyan) }
                    }
                }
            }
        case .duckRain:
            for t in aim {
                let n = Int(6 + i * 16)
                for k in 0..<n where canSpawn {
                    let s = sprite(Textures.emoji("🦆", size: 128), height: CGFloat.random(in: 40...80))
                    if Bool.random() { s.xScale = -s.xScale }
                    let x = t.point.x + CGFloat.random(in: -t.size * 0.9...t.size * 0.9)
                    let start = CGPoint(x: x, y: bounds.maxY + 60)
                    let end = CGPoint(x: x, y: t.point.y + CGFloat.random(in: -t.size * 0.35...t.size * 0.3))
                    let stagger = Double.random(in: 0...min(0.45, dur * 0.4))
                    s.position = start
                    s.alpha = 0
                    addChild(s)
                    let fall = SKAction.move(to: end, duration: dur - stagger)
                    fall.timingMode = .easeIn
                    let last = k == n - 1
                    s.run(.sequence([
                        .wait(forDuration: d + stagger), .fadeIn(withDuration: 0.02), fall,
                        .run { [weak self] in if last { self?.labelPop("QUACK!", at: CGPoint(x: t.point.x, y: t.point.y + t.size * 0.7), size: 34, color: .systemYellow) } },
                        .group([.sequence([.moveBy(x: CGFloat.random(in: -40...40), y: 45, duration: 0.18),
                                           .moveBy(x: 0, y: -90, duration: 0.35)]),
                                .rotate(byAngle: CGFloat.random(in: -2...2), duration: 0.5),
                                .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.3)])]),
                        .removeFromParent(),
                    ]))
                }
            }
        case .tomatoThrow:
            for t in aim {
                let from = origin(toward: t.point)
                let n = Int(1 + i * 3)
                for k in 0..<n {
                    let s = sprite(Textures.emoji("🍅", size: 128), height: 64 + i * 30)
                    let to = jitter(t.point, t.size * 0.25)
                    let stagger = Double(k) * 0.09
                    fly(s, from: from, to: to, arc: bounds.height * 0.3, delay: d + stagger, duration: dur - stagger, spin: 7) { [weak self] in
                        self?.splat(at: to, color: NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1), size: t.size)
                        if k == 0 { self?.labelPop("SPLAT!", at: CGPoint(x: to.x, y: to.y + t.size * 0.6), size: 34, color: .systemRed) }
                    }
                }
            }
        case .balloonAttack:
            for t in aim {
                let from = origin(toward: t.point)
                let n = Int(2 + i * 4)
                for k in 0..<n {
                    let s = sprite(Textures.emoji("🎈", size: 128), height: 70)
                    s.color = NSColor.candy.randomElement()!
                    s.colorBlendFactor = 0.35
                    let to = jitter(t.point, t.size * 0.35)
                    let stagger = Double(k) * 0.07
                    fly(s, from: from, to: to, arc: bounds.height * 0.25, delay: d + stagger, duration: dur - stagger, spin: 1.5) { [weak self] in
                        self?.burst(at: to, texture: Textures.disc, count: 26, speed: 280, lifetime: 0.6, scale: 0.18,
                                    colors: [.systemTeal, .systemBlue, .white], gravity: 700)
                        if k == 0 { self?.labelPop("POP!", at: CGPoint(x: to.x, y: to.y + t.size * 0.6), size: 32, color: .systemTeal) }
                    }
                }
            }
        case .spongeShot:
            for t in aim {
                let from = origin(toward: t.point)
                let n = Int(1 + i * 2)
                for k in 0..<n {
                    let s = sprite(Textures.emoji("🧽", size: 128), height: 66)
                    let to = jitter(t.point, t.size * 0.2)
                    let stagger = Double(k) * 0.12
                    fly(s, from: from, to: to, arc: 40, delay: d + stagger, duration: dur - stagger, spin: 9) { [weak self] in
                        self?.burst(at: to, texture: Textures.bubble, count: 30, speed: 140, lifetime: 1.0, scale: 0.35, gravity: -60)
                        if k == 0 { self?.labelPop("SQUISH!", at: CGPoint(x: to.x, y: to.y + t.size * 0.6), size: 32, color: .systemYellow) }
                    }
                }
            }
        case .confettiExplosion:
            run(.sequence([.wait(forDuration: d + dur * 0.7), .run { [weak self] in
                guard let self else { return }
                let n = Int(120 + i * 200)
                self.burst(at: CGPoint(x: self.bounds.minX + 20, y: self.bounds.minY + 20), texture: Textures.confetti, count: n,
                           speed: 900, lifetime: 2.2, scale: 0.9, colors: NSColor.candy, gravity: 520, spin: true,
                           angle: .pi / 3, angleRange: 0.5, emitDuration: 0.2)
                self.burst(at: CGPoint(x: self.bounds.maxX - 20, y: self.bounds.minY + 20), texture: Textures.confetti, count: n,
                           speed: 900, lifetime: 2.2, scale: 0.9, colors: NSColor.candy, gravity: 520, spin: true,
                           angle: .pi * 2 / 3, angleRange: 0.5, emitDuration: 0.2)
                self.burst(at: centre, texture: Textures.confetti, count: n / 2, speed: 500, lifetime: 1.6, scale: 0.8,
                           colors: NSColor.candy, gravity: 400, spin: true)
                self.labelPop("CONFETTI!", at: CGPoint(x: centre.x, y: centre.y + 120), size: 44, color: .systemPink)
            }]))
        case .bubbleStorm:
            run(.sequence([.wait(forDuration: d + dur * 0.5), .run { [weak self] in
                guard let self else { return }
                self.burst(at: CGPoint(x: self.bounds.midX, y: self.bounds.minY - 30), texture: Textures.bubble,
                           count: Int(140 + i * 220), speed: 200, lifetime: 4.5, scale: 0.55, angle: .pi / 2,
                           angleRange: 0.7, emitDuration: 2.2, positionRange: CGVector(dx: self.bounds.width, dy: 20), alphaFade: false)
                self.labelPop("BUBBLE STORM!", at: CGPoint(x: self.bounds.midX, y: self.bounds.midY + 140), size: 46, color: .cyan)
            }]))
        case .rainbowExplosion:
            run(.sequence([.wait(forDuration: d + dur * 0.6), .run { [weak self] in
                guard let self else { return }
                for (k, c) in NSColor.rainbow.enumerated() {
                    let r = self.sprite(Textures.ring, height: 60)
                    r.color = c; r.colorBlendFactor = 1
                    r.position = centre
                    r.setScale(0.2)
                    self.addChild(r)
                    r.run(.sequence([.wait(forDuration: Double(k) * 0.06),
                                     .group([.scale(to: 9 + CGFloat(k) * 1.2 + i * 6, duration: 1.1), .fadeOut(withDuration: 1.1)]),
                                     .removeFromParent()]))
                }
                let bow = self.sprite(Textures.emoji("🌈", size: 256), height: 120)
                bow.position = centre
                self.addChild(bow)
                bow.run(.sequence([.scale(to: 3 + i * 2, duration: 0.6), .fadeOut(withDuration: 0.5), .removeFromParent()]))
                self.burst(at: centre, texture: Textures.emoji("✨", size: 48), count: 40, speed: 500, lifetime: 1.2, scale: 0.6)
                self.labelPop("RAINBOW!", at: CGPoint(x: centre.x, y: centre.y + 150), size: 46, color: .systemPurple)
            }]))
        case .emojiExplosion:
            run(.sequence([.wait(forDuration: d + dur * 0.6), .run { [weak self] in
                guard let self else { return }
                for e in ["🤪", "😂", "🥳", "😱", "🤡", "💩", "🫠", "🙃", "😎", "🥴"].shuffled().prefix(5) {
                    self.burst(at: centre, texture: Textures.emoji(e, size: 96), count: Int(8 + i * 10), speed: 600,
                               lifetime: 1.6, scale: 0.55, gravity: 450, spin: true)
                }
                self.labelPop("EMOJI EXPLOSION!", at: CGPoint(x: centre.x, y: centre.y + 150), size: 42, color: .systemOrange)
            }]))
        case .transform:
            guard let t = aim.first else { return }
            let wand = sprite(Textures.emoji("🪄", size: 128), height: 70)
            fly(wand, from: origin(toward: t.point), to: CGPoint(x: t.point.x, y: t.point.y + t.size * 0.4), arc: 80,
                delay: d, duration: dur, spin: 4) { [weak self] in
                self?.burst(at: t.point, texture: Textures.dot, count: 60, speed: 180, lifetime: 0.9, scale: 1.3,
                            colors: [NSColor(white: 0.85, alpha: 1), NSColor(white: 0.65, alpha: 1)])
                self?.burst(at: t.point, texture: Textures.emoji("✨", size: 48), count: 24, speed: 260, lifetime: 0.9, scale: 0.6)
                self?.labelPop("POOF!", at: CGPoint(x: t.point.x, y: t.point.y + t.size * 0.7), size: 38, color: .systemPurple)
            }
        case .surprise:
            let giant = ["🐙", "🦄", "🐳", "🦕", "🛸", "🍕", "🐔", "🥑"].randomElement()!
            let h = bounds.height * (0.55 + i * 0.3)
            let s = sprite(Textures.emoji(giant, size: 256), height: h)
            let ltr = Bool.random()
            s.position = CGPoint(x: ltr ? bounds.minX - h : bounds.maxX + h, y: bounds.midY)
            if !ltr { s.xScale = -s.xScale }
            s.zPosition = 40
            addChild(s)
            let travel = SKAction.moveTo(x: ltr ? bounds.maxX + h : bounds.minX - h, duration: dur + 1.0)
            let wob = SKAction.repeatForever(.sequence([.rotate(toAngle: 0.15, duration: 0.25), .rotate(toAngle: -0.15, duration: 0.25)]))
            s.run(wob)
            s.run(.sequence([.wait(forDuration: d), travel, .removeFromParent()]))
            run(.sequence([.wait(forDuration: d + 0.2), .run { [weak self] in
                guard let self else { return }
                self.labelPop("SURPRISE!!!", at: CGPoint(x: self.bounds.midX, y: self.bounds.maxY - 120), size: 60, color: .systemYellow, rotate: false)
            }]))
        }
    }

    private func pop(at p: CGPoint, size: CGFloat) {
        guard canSpawn else { return }
        let r = sprite(Textures.ring, height: size)
        r.color = .white; r.colorBlendFactor = 1; r.alpha = 0.8
        r.position = p
        addChild(r)
        r.run(.sequence([.group([.scale(to: 1.8, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }

    private func splat(at p: CGPoint, color: NSColor, size: CGFloat) {
        burst(at: p, texture: Textures.disc, count: 34, speed: 320, lifetime: 0.7, scale: 0.22, colors: [color], gravity: 800)
        guard canSpawn else { return }
        let s = sprite(Textures.disc, height: size * 0.45)
        s.color = color; s.colorBlendFactor = 1; s.alpha = 0.85
        s.position = p
        s.xScale *= 1.5
        s.zRotation = CGFloat.random(in: 0...3)
        addChild(s)
        s.run(.sequence([.scale(by: 1.2, duration: 0.08), .wait(forDuration: 0.9),
                         .group([.moveBy(x: 0, y: -40, duration: 0.8), .fadeOut(withDuration: 0.8)]), .removeFromParent()]))
    }
}
