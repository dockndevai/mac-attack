import Foundation

public enum ScenePhase: String, Sendable {
    case idle = "IDLE"
    case personDetected = "PERSON_DETECTED"
    case characterSpawned = "CHARACTER_SPAWNED"
    case awaitingDecision = "LAYA_DECISION"
    case gameEvent = "GAME_EVENT"
    case characterReaction = "CHARACTER_REACTION"
    case wait = "WAIT"
    case escape = "CHARACTER_ESCAPE"
}

public struct LastEventInfo: Sendable {
    public var effect: EffectKind
    public var target: EventTarget
    public var at: Double
}

public struct GameState: Sendable {
    public var people: [Person] = []
    public var phase: ScenePhase = .idle
    public var elapsedTime: Double = 0
    public var idleSeconds: Double = 0
    public var difficulty: Double = 0
    public var combo: Int = 0
    public var eventCount: Int = 0
    public var lastEvent: LastEventInfo?
    public var chaos: Bool = false

    public init() {}

    public var sceneState: String { people.isEmpty ? "idle" : "active" }
}

/// The ONLY thing that leaves the game for the director. Abstract facts, no pixels, no identity.
public struct GameSnapshot: Codable, Sendable {
    public struct PersonInfo: Codable, Sendable {
        public var id: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var movement: String
        public var velocity: Double
        public var dwell_time: Double
        public var character: String
        public var times_hit: Int
    }

    public struct LastEvent: Codable, Sendable {
        public var effect: String
        public var target: String
        public var seconds_ago: Double
    }

    public var people: [PersonInfo]
    public var people_count: Int
    public var scene_state: String
    public var idle_seconds: Double
    public var elapsed: Double
    public var combo: Int
    public var difficulty: Double
    public var chaos: Bool
    public var trigger: String
    public var last_event: LastEvent?

    public init(state: GameState, trigger: DecisionTrigger) {
        func r(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        people = state.people.map {
            PersonInfo(id: $0.id, x: r($0.box.midX), y: r($0.box.midY), width: r($0.box.width),
                       height: r($0.box.height), movement: $0.movement.rawValue, velocity: r($0.speed),
                       dwell_time: r($0.lifetime), character: $0.character.rawValue, times_hit: $0.timesHit)
        }
        people_count = state.people.count
        scene_state = state.sceneState
        idle_seconds = r(state.idleSeconds)
        elapsed = r(state.elapsedTime)
        combo = state.combo
        difficulty = r(state.difficulty)
        chaos = state.chaos
        self.trigger = trigger.rawValue
        last_event = state.lastEvent.map {
            LastEvent(effect: $0.effect.rawValue, target: $0.target.key, seconds_ago: r(state.elapsedTime - $0.at))
        }
    }
}
