import AppKit
import MacAttackCore
import SpriteKit

/// The 60 fps canvas. Drives the engine tick, turns engine outputs into sprites, and keeps
/// characters glued to their (smoothed) tracked positions.
@MainActor
public final class GameScene: SKScene {
    public let engine: GameEngine
    /// Called every frame before the engine ticks (simulation input lives here).
    public var frameHandler: ((Double) -> Void)?
    /// Raw detector boxes for the debug overlay (normalized, top-left origin).
    public var debugBoxes: () -> [NormRect] = { [] }
    /// Aspect ratio of the camera image under aspect-fill, or nil to use the whole canvas.
    public var contentAspect: CGFloat?
    public var soundEnabled = true
    public var showDebugBoxes = false { didSet { boxLayer.isHidden = !showDebugBoxes } }
    public var cameraBackdrop = false { didSet { updateBackdrop() } }

    private let backdrop = SKSpriteNode()
    private let ambience = SKNode()
    private let boxLayer = SKNode()
    private let characterLayer = SKNode()
    public let fx = FXLayer()
    private let hud = SKNode()
    private var characters: [String: CharacterNode] = [:]
    private var idleLabel = comicLabel("Waiting for humans...", size: 44)
    private var banner = SKNode()
    private var statusNode: SKLabelNode?
    /// Small line at the bottom (screensaver setup hints). nil hides it.
    public var statusMessage: String? { didSet { updateStatusMessage() } }
    private var bubbleEmitter: SKEmitterNode?
    private var twinkleEmitter: SKEmitterNode?
    private var clouds: [SKSpriteNode] = []
    private var lastTime: TimeInterval = 0
    private var oldStatusMessage: String?
    private var boxNodes: [SKShapeNode] = []
    public private(set) var fps: Double = 60
    private var fpsAccum = 0.0, fpsFrames = 0

    public init(engine: GameEngine) {
        self.engine = engine
        super.init(size: CGSize(width: 1000, height: 640))
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
        backdrop.zPosition = -100
        backdrop.anchorPoint = .zero
        ambience.zPosition = -50
        boxLayer.zPosition = 5
        boxLayer.isHidden = true
        characterLayer.zPosition = 10
        fx.zPosition = 20
        hud.zPosition = 100
        [backdrop, ambience, boxLayer, characterLayer, fx, hud].forEach(addChild)
        hud.addChild(idleLabel)
        hud.addChild(banner)
        buildAmbience()
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        fx.bounds = CGRect(origin: .zero, size: size)
        updateBackdrop()
        bubbleEmitter?.position = CGPoint(x: size.width / 2, y: -20)
        bubbleEmitter?.particlePositionRange = CGVector(dx: size.width, dy: 0)
        twinkleEmitter?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        twinkleEmitter?.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        idleLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        statusNode?.position = CGPoint(x: size.width / 2, y: 44)
        banner.position = CGPoint(x: size.width / 2, y: size.height - 50)
    }

    // MARK: - Frame

    public override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.1, currentTime - lastTime)
        lastTime = currentTime
        fpsAccum += dt; fpsFrames += 1
        if fpsAccum >= 1 { fps = Double(fpsFrames) / fpsAccum; fpsAccum = 0; fpsFrames = 0 }

        frameHandler?(dt)
        engine.tick(dt)
        for o in engine.drainOutputs() { handle(o) }
        syncCharacters(dt)
        for c in clouds {
            c.position.x += (c.userData?["speed"] as? CGFloat ?? 15) * CGFloat(dt)
            if c.position.x > size.width + 120 {
                c.position = CGPoint(x: -120, y: size.height * CGFloat.random(in: 0.72...0.9))
            }
        }
        idleLabel.alpha += ((engine.people.isEmpty ? 1 : 0) - idleLabel.alpha) * CGFloat(min(1, dt * 4))
        if showDebugBoxes { drawBoxes() }
    }

    private func handle(_ o: EngineOutput) {
        switch o {
        case .spawned(let p):
            characters[p.id]?.removeFromParent()
            let n = CharacterNode(person: p)
            n.targetPosition = point(p.box.midX, p.box.midY)
            n.position = n.targetPosition
            n.targetSize = charSize(p)
            characterLayer.addChild(n)
            characters[p.id] = n
            n.spawnAnimation(fx: fx)
            play("Pop")
        case .escaped(let p):
            guard let n = characters.removeValue(forKey: p.id) else { return }
            let exitX: CGFloat = n.position.x < size.width / 2 ? -200 : size.width + 200
            n.removeAllActions()
            fx.burst(at: n.position, texture: Textures.emoji("💨", size: 64), count: 8, speed: 120, lifetime: 0.6, scale: 0.6)
            let run = SKAction.moveTo(x: exitX, duration: 0.7)
            run.timingMode = .easeIn
            n.run(.sequence([.group([run, .fadeOut(withDuration: 0.7)]), .removeFromParent()]))
        case .event(let ev):
            let targets = ev.targetPersonIDs.compactMap { id -> FXLayer.Target? in
                guard let n = characters[id] else { return nil }
                return FXLayer.Target(id: id, point: n.targetPosition, size: n.currentSize)
            }
            fx.play(ev, targets: targets)
            run(.sequence([.wait(forDuration: ev.delay), .run { [weak self] in self?.play(ev.sound) }]))
        case .reaction(let id, let r, let intensity):
            guard let n = characters[id] else { return }
            n.registerHit()
            n.react(r, intensity: intensity, fx: fx)
        case .transformed(let id, let c):
            characters[id]?.setCharacter(c)
        case .narration(let s):
            showBanner(s)
        }
    }

    private func syncCharacters(_ dt: Double) {
        for p in engine.people {
            guard let n = characters[p.id] else { continue }
            n.targetPosition = point(p.box.midX, p.box.midY)
            n.targetSize = charSize(p)
            n.step(dt)
        }
    }

    // MARK: - Coordinates

    /// Area the camera image occupies on screen under aspect-fill (may extend past the view).
    private var contentRect: CGRect {
        guard let a = contentAspect, a > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let viewAspect = size.width / size.height
        if viewAspect > a {
            let h = size.width / a
            return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        } else {
            let w = size.height * a
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
    }

    public func point(_ nx: Double, _ ny: Double) -> CGPoint {
        let r = contentRect
        return CGPoint(x: r.minX + CGFloat(nx) * r.width, y: r.maxY - CGFloat(ny) * r.height)
    }

    private func charSize(_ p: Person) -> CGFloat {
        min(260, max(80, CGFloat(p.box.height) * contentRect.height * 0.6))
    }

    // MARK: - Ambience / HUD

    private func buildAmbience() {
        let b = SKEmitterNode()
        b.particleTexture = Textures.bubble
        b.particleBirthRate = 1.3
        b.particleLifetime = 11
        b.particleSpeed = 60
        b.particleSpeedRange = 30
        b.emissionAngle = .pi / 2
        b.emissionAngleRange = 0.4
        b.particleScale = 0.35
        b.particleScaleRange = 0.25
        b.particleAlpha = 0.7
        b.xAcceleration = 0
        b.advanceSimulationTime(10)
        ambience.addChild(b)
        bubbleEmitter = b

        let t = SKEmitterNode()
        t.particleTexture = Textures.emoji("✨", size: 48)
        t.particleBirthRate = 2.5
        t.particleLifetime = 2.4
        t.particleLifetimeRange = 1
        t.particleSpeed = 0
        t.particleScale = 0.35
        t.particleScaleRange = 0.2
        t.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.9, 0], times: [0, 0.5, 1])
        t.advanceSimulationTime(3)
        ambience.addChild(t)
        twinkleEmitter = t

        for k in 0..<3 {
            let c = SKSpriteNode(texture: Textures.emoji("☁️", size: 128))
            c.alpha = 0.75
            c.setScale(CGFloat.random(in: 0.8...1.4))
            c.position = CGPoint(x: CGFloat(k) * 380 + 100, y: 520 - CGFloat(k) * 50)
            ambience.addChild(c)
            clouds.append(c)
            c.userData = ["speed": CGFloat.random(in: 12...25)]
        }
        idleLabel.run(.repeatForever(.sequence([.scale(to: 1.06, duration: 0.9), .scale(to: 0.96, duration: 0.9)])))
    }

    private func updateBackdrop() {
        guard size.width > 0 else { return }
        if cameraBackdrop {
            backdrop.isHidden = true
            ambience.alpha = 0.45
        } else {
            backdrop.isHidden = false
            backdrop.texture = Textures.gradient(size, top: NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.62, alpha: 1),
                                                 bottom: NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.75, alpha: 1))
            backdrop.size = size
            ambience.alpha = 1
        }
    }

    private func updateStatusMessage() {
        guard statusMessage != oldStatusMessage else { return }
        oldStatusMessage = statusMessage
        statusNode?.removeFromParent()
        statusNode = nil
        guard let m = statusMessage else { return }
        let l = comicLabel(m, size: 20, color: NSColor(white: 1, alpha: 0.85))
        l.position = CGPoint(x: size.width / 2, y: 44)
        hud.addChild(l)
        statusNode = l
    }

    private func showBanner(_ text: String) {
        banner.removeAllChildren()
        banner.removeAllActions()
        let l = comicLabel(text, size: 30, color: .white)
        let w = l.frame.width + 44
        let pill = SKShapeNode(rectOf: CGSize(width: w, height: 52), cornerRadius: 26)
        pill.fillColor = NSColor.black.withAlphaComponent(0.55)
        pill.strokeColor = NSColor.white.withAlphaComponent(0.8)
        pill.lineWidth = 2
        banner.addChild(pill)
        banner.addChild(l)
        banner.alpha = 1
        banner.setScale(0.6)
        banner.run(.sequence([.scale(to: 1.08, duration: 0.12), .scale(to: 1, duration: 0.08),
                              .wait(forDuration: 2.8), .fadeOut(withDuration: 0.5)]))
    }

    private func drawBoxes() {
        let boxes = debugBoxes()
        while boxNodes.count < boxes.count {
            let n = SKShapeNode()
            n.strokeColor = .systemGreen
            n.lineWidth = 2
            n.fillColor = .clear
            boxLayer.addChild(n)
            boxNodes.append(n)
        }
        for (i, n) in boxNodes.enumerated() {
            guard i < boxes.count else { n.isHidden = true; continue }
            let b = boxes[i]
            let p0 = point(b.x, b.y + b.height), p1 = point(b.x + b.width, b.y)
            n.path = CGPath(rect: CGRect(x: p0.x, y: p0.y, width: p1.x - p0.x, height: p1.y - p0.y), transform: nil)
            n.isHidden = false
        }
    }

    private func play(_ sound: String) {
        guard soundEnabled, let s = NSSound(named: NSSound.Name(sound))?.copy() as? NSSound else { return }
        s.volume = 0.25
        s.play()
    }

    public func clearAll() {
        for n in characters.values { n.removeFromParent() }
        characters.removeAll()
        fx.removeAllChildren()
        fx.removeAllActions()
    }

    public var liveNodeCount: Int { characterLayer.children.count + fx.children.count }
}
