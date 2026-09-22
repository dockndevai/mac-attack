import Foundation

/// Normalized rectangle in view space: origin top-left, y grows downward, all values 0...1.
public struct NormRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { max(0, width) * max(0, height) }

    public func iou(_ o: NormRect) -> Double {
        let ix = max(0, min(x + width, o.x + o.width) - max(x, o.x))
        let iy = max(0, min(y + height, o.y + o.height) - max(y, o.y))
        let inter = ix * iy
        let union = area + o.area - inter
        return union > 0 ? inter / union : 0
    }

    public func lerp(to o: NormRect, _ t: Double) -> NormRect {
        NormRect(x: x + (o.x - x) * t, y: y + (o.y - y) * t,
                 width: width + (o.width - width) * t, height: height + (o.height - height) * t)
    }

    public static func centered(x: Double, y: Double, width: Double, height: Double) -> NormRect {
        NormRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }
}

public enum MovementState: String, Codable, CaseIterable, Sendable {
    case stationary, left, right, up, down, approaching, retreating
}

public enum CharacterType: String, Codable, CaseIterable, Sendable {
    case frog, wizard, potato, alien, duck, robot, cat, dinosaur, ghost, octopus

    public var emoji: String {
        switch self {
        case .frog: "🐸"
        case .wizard: "🧙"
        case .potato: "🥔"
        case .alien: "👽"
        case .duck: "🦆"
        case .robot: "🤖"
        case .cat: "🐱"
        case .dinosaur: "🦖"
        case .ghost: "👻"
        case .octopus: "🐙"
        }
    }

    public var displayName: String { rawValue.uppercased() }
}

/// One tracked, anonymous human (from the tracker or the simulator). No identity, no pixels.
public struct TrackSnapshot: Equatable, Sendable {
    public var id: String
    public var box: NormRect
    public var vx: Double
    public var vy: Double
    public var movement: MovementState
    public var dwell: Double

    public init(id: String, box: NormRect, vx: Double = 0, vy: Double = 0,
                movement: MovementState = .stationary, dwell: Double = 0) {
        self.id = id; self.box = box; self.vx = vx; self.vy = vy; self.movement = movement; self.dwell = dwell
    }

    public var speed: Double { (vx * vx + vy * vy).squareRoot() }
}

/// A person as the game knows them: a track plus a cartoon identity.
public struct Person: Identifiable, Equatable, Sendable {
    public let id: String
    public var box: NormRect
    public var vx: Double
    public var vy: Double
    public var movement: MovementState
    public var character: CharacterType
    public var lifetime: Double
    public var timesHit: Int
    public var number: Int

    public var position: (x: Double, y: Double) { (box.midX, box.midY) }
    public var speed: Double { (vx * vx + vy * vy).squareRoot() }

    public static func == (a: Person, b: Person) -> Bool {
        a.id == b.id && a.box == b.box && a.character == b.character && a.timesHit == b.timesHit
            && a.movement == b.movement && a.lifetime == b.lifetime
    }
}

public enum EffectKind: String, Codable, CaseIterable, Sendable {
    // projectiles
    case bubbleBlast = "bubble_blast"
    case duckRain = "duck_rain"
    case tomatoThrow = "tomato_throw"
    case balloonAttack = "balloon_attack"
    case spongeShot = "sponge_shot"
    // area effects
    case confettiExplosion = "confetti_explosion"
    case bubbleStorm = "bubble_storm"
    case rainbowExplosion = "rainbow_explosion"
    case emojiExplosion = "emoji_explosion"
    // specials
    case transform
    case surprise

    public static let projectiles: [EffectKind] = [.bubbleBlast, .duckRain, .tomatoThrow, .balloonAttack, .spongeShot]
    public static let areas: [EffectKind] = [.confettiExplosion, .bubbleStorm, .rainbowExplosion, .emojiExplosion]

    public var isProjectile: Bool { Self.projectiles.contains(self) }
    public var isArea: Bool { Self.areas.contains(self) }

    public var title: String { rawValue.replacingOccurrences(of: "_", with: " ").uppercased() }

    public var emoji: String {
        switch self {
        case .bubbleBlast: "🫧"
        case .duckRain: "🦆"
        case .tomatoThrow: "🍅"
        case .balloonAttack: "🎈"
        case .spongeShot: "🧽"
        case .confettiExplosion: "🎊"
        case .bubbleStorm: "🫧"
        case .rainbowExplosion: "🌈"
        case .emojiExplosion: "🤪"
        case .transform: "🪄"
        case .surprise: "🎁"
        }
    }

    /// macOS system sound name (in /System/Library/Sounds).
    public var sound: String {
        switch self {
        case .bubbleBlast, .bubbleStorm: "Bottle"
        case .duckRain: "Frog"
        case .tomatoThrow: "Pop"
        case .balloonAttack: "Blow"
        case .spongeShot: "Tink"
        case .confettiExplosion: "Hero"
        case .rainbowExplosion: "Glass"
        case .emojiExplosion: "Funk"
        case .transform: "Purr"
        case .surprise: "Submarine"
        }
    }
}

public enum ReactionKind: String, Codable, CaseIterable, Sendable {
    case dodge, jump, shake, spin, shrink, grow, explode, celebrate
}

public enum DirectorMood: String, Codable, CaseIterable, Sendable {
    case bored, mischievous, alarmed, gleeful
}

public enum EventTarget: Equatable, Sendable, CustomStringConvertible {
    case person(String)
    case everyone

    public var key: String {
        switch self {
        case .person(let id): id
        case .everyone: "everyone"
        }
    }

    public var description: String { key.uppercased().replacingOccurrences(of: "-", with: "_") }
}

public enum DirectorSource: String, Sendable {
    case laya = "Laya"
    case fallback = "Local Fallback"
    case manual = "Manual"
}

public enum Trajectory: String, Sendable {
    case arc, straight, rain, burst, sweep
}

/// Why the director is being asked.
public enum DecisionTrigger: String, Codable, Sendable {
    case personArrived = "person_arrived"
    case personLeft = "person_left"
    case timer
    case manual
}

/// The director's answer, before it becomes a concrete event.
public struct DirectorDecision: Sendable {
    public var holdBack: Bool
    public var effect: EffectKind
    public var target: EventTarget
    public var intensity: Double          // 0...1
    public var reaction: ReactionKind
    public var mood: DirectorMood
    public var delay: Double
    public var source: DirectorSource
    public var latencyMs: Double?
    /// Top probabilities per question, for the debug panel ("why did it do that?").
    public var rationale: [String: [(String, Double)]]
    public var situation: String?

    public init(holdBack: Bool = false, effect: EffectKind, target: EventTarget, intensity: Double,
                reaction: ReactionKind, mood: DirectorMood = .mischievous, delay: Double = 0.2,
                source: DirectorSource, latencyMs: Double? = nil,
                rationale: [String: [(String, Double)]] = [:], situation: String? = nil) {
        self.holdBack = holdBack; self.effect = effect; self.target = target; self.intensity = intensity
        self.reaction = reaction; self.mood = mood; self.delay = delay; self.source = source
        self.latencyMs = latencyMs; self.rationale = rationale; self.situation = situation
    }
}

/// A concrete thing the renderer must draw.
public struct GameEvent: Identifiable, Sendable {
    public let id: UUID
    public var targetPersonIDs: [String]      // empty = aim at the room
    public var target: EventTarget
    public var effect: EffectKind
    public var trajectory: Trajectory
    public var intensity: Double
    public var delay: Double
    public var duration: Double
    public var sound: String
    public var reaction: ReactionKind
    public var source: DirectorSource
    public var transformTo: CharacterType?

    public var visualEffect: String { effect.rawValue }
}
