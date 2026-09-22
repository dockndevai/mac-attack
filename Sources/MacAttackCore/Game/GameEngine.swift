import Foundation
import Observation

/// Things the renderer should do. Drained once per frame.
public enum EngineOutput: Sendable {
    case spawned(Person)
    case escaped(Person)
    case event(GameEvent)
    case reaction(personID: String, ReactionKind, intensity: Double)
    case transformed(personID: String, CharacterType)
    case narration(String)
}

/// Throttled, UI-facing summary (SwiftUI must not re-render at 60 fps).
public struct EngineHUD: Sendable {
    public var phase: ScenePhase = .idle
    public var people: [Person] = []
    public var eventCount = 0
    public var combo = 0
    public var difficulty = 0.0
    public var idleSeconds = 0.0
    public var elapsed = 0.0
    public var lastDecision: DirectorDecision?
    public var narration = Narrator.idle[0]
    public var awaiting = false
}

/// The game's state machine. Independent of camera, Vision and rendering: fed tracks, ticked
/// with dt, and it emits `EngineOutput`s.
///
/// IDLE → PERSON_DETECTED → CHARACTER_SPAWNED → LAYA_DECISION → GAME_EVENT → CHARACTER_REACTION
/// → WAIT → (LAYA_DECISION | IDLE); any person leaving → CHARACTER_ESCAPE (→ IDLE if empty).
@MainActor
@Observable
public final class GameEngine {
    public typealias Decider = @MainActor (GameSnapshot, DecisionTrigger, Double) async -> DirectorDecision

    public private(set) var hud = EngineHUD()
    public var chaos = false { didSet { state.chaos = chaos } }

    @ObservationIgnored public private(set) var state = GameState()
    @ObservationIgnored private var outputs: [EngineOutput] = []
    @ObservationIgnored private let decider: Decider
    @ObservationIgnored private var phaseTimer = 0.0
    @ObservationIgnored private var pendingTrigger: DecisionTrigger?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var inFlightSince = 0.0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var currentEvent: GameEvent?
    @ObservationIgnored private var hudTimer = 0.0
    @ObservationIgnored private var boredTimer = 6.0
    @ObservationIgnored private var nextNumber = 1
    @ObservationIgnored private var lastHitAt = -100.0
    @ObservationIgnored public var decisionTimeout = 3.0

    public init(decider: @escaping Decider) {
        self.decider = decider
    }

    public convenience init(coordinator: DirectorCoordinator) {
        self.init { [weak coordinator] snap, trig, t in
            guard let coordinator else { return RandomDirector().decideNow(snap) }
            return await coordinator.decide(snap, trigger: trig, time: t)
        }
    }

    public var people: [Person] { state.people }
    public var phase: ScenePhase { state.phase }
    public var isAwaitingDecision: Bool { inFlight }

    public func drainOutputs() -> [EngineOutput] {
        defer { outputs.removeAll(keepingCapacity: true) }
        return outputs
    }

    // MARK: - Inputs

    /// Replace the set of people with the latest tracks (camera tracker or simulation).
    public func updatePeople(_ tracks: [TrackSnapshot]) {
        let ids = Set(tracks.map(\.id))
        let leaving = state.people.filter { !ids.contains($0.id) }
        state.people.removeAll { !ids.contains($0.id) }
        for p in leaving {
            emit(.escaped(p))
            say(Narrator.escape(remaining: state.people.count))
        }
        if !leaving.isEmpty {
            if state.people.isEmpty {
                enter(.escape, for: 1.6)
                pendingTrigger = nil
            } else if state.phase == .wait {
                pendingTrigger = pendingTrigger ?? .personLeft
                phaseTimer = min(phaseTimer, 1.0)
            }
        }

        for t in tracks {
            if let i = state.people.firstIndex(where: { $0.id == t.id }) {
                state.people[i].box = t.box
                state.people[i].vx = t.vx
                state.people[i].vy = t.vy
                state.people[i].movement = t.movement
                state.people[i].lifetime = t.dwell
            } else {
                let used = Set(state.people.map(\.character))
                let character = CharacterType.allCases.filter { !used.contains($0) }.randomElement() ?? .potato
                let p = Person(id: t.id, box: t.box, vx: t.vx, vy: t.vy, movement: t.movement,
                               character: character, lifetime: t.dwell, timesHit: 0, number: nextNumber)
                nextNumber += 1
                state.people.append(p)
                emit(.spawned(p))
                say(Narrator.arrival(count: state.people.count, character: character))
                pendingTrigger = .personArrived
                switch state.phase {
                case .idle, .escape:
                    enter(.personDetected, for: 0)
                case .wait:
                    phaseTimer = min(phaseTimer, 0.9)
                default:
                    break
                }
            }
        }
    }

    public func tick(_ dt: Double) {
        let dt = min(max(dt, 0), 0.25)
        state.elapsedTime += dt
        phaseTimer -= dt
        hudTimer -= dt

        if state.people.isEmpty {
            state.idleSeconds += dt
            if state.phase == .escape && phaseTimer <= 0 { enter(.idle, for: 0) }
            if state.phase != .escape && state.phase != .idle && !inFlight { enter(.idle, for: 0) }
            if state.phase == .idle {
                boredTimer -= dt
                if boredTimer <= 0 {
                    boredTimer = Double.random(in: 8...14)
                    say(Narrator.idle.randomElement()!)
                }
            }
        } else {
            state.idleSeconds = 0
            advance()
        }

        if inFlight && state.elapsedTime - inFlightSince > decisionTimeout {
            // The coordinator already bounds Laya; this is a last-resort guard so the game can't stall.
            generation += 1
            inFlight = false
            receive(RandomDirector().decideNow(GameSnapshot(state: state, trigger: .timer)), generation: generation)
        }

        if hudTimer <= 0 { publishHUD() }
    }

    private func advance() {
        switch state.phase {
        case .idle, .escape:
            enter(.personDetected, for: 0)
        case .personDetected:
            enter(.characterSpawned, for: 0.8)
        case .characterSpawned:
            if phaseTimer <= 0 { requestDecision(pendingTrigger ?? .personArrived) }
        case .awaitingDecision:
            break
        case .gameEvent:
            if phaseTimer <= 0 { impact() }
        case .characterReaction:
            if phaseTimer <= 0 { enter(.wait, for: cooldown()) }
        case .wait:
            if phaseTimer <= 0 { requestDecision(pendingTrigger ?? .timer) }
        }
    }

    // MARK: - Decisions

    /// Ask the director. No-op if a request is already in flight.
    public func requestDecision(_ trigger: DecisionTrigger) {
        guard !inFlight else { return }
        pendingTrigger = nil
        inFlight = true
        inFlightSince = state.elapsedTime
        if !state.people.isEmpty, state.phase != .gameEvent, state.phase != .characterReaction {
            enter(.awaitingDecision, for: 0)
        }
        let snap = GameSnapshot(state: state, trigger: trigger)
        let gen = generation
        let now = state.elapsedTime
        let decider = self.decider
        Task { @MainActor [weak self] in
            let d = await decider(snap, trigger, now)
            self?.receive(d, generation: gen)
        }
        publishHUD()
    }

    private func receive(_ d: DirectorDecision, generation gen: Int) {
        guard gen == generation else { return }
        inFlight = false
        hud.lastDecision = d
        guard !state.people.isEmpty else { publishHUD(); return }
        if state.phase == .gameEvent || state.phase == .characterReaction {
            // a manual effect is playing; keep this decision for the debug log only
            publishHUD(); return
        }
        if d.holdBack {
            say(Narrator.holdBack(d.mood))
            enter(.wait, for: cooldown() * 0.7)
            publishHUD()
            return
        }
        play(d)
    }

    /// Developer/manual effect: plays immediately, interrupting whatever is happening.
    public func triggerEffect(_ effect: EffectKind, target: EventTarget? = nil) {
        let tgt = target ?? (effect.isArea || effect == .surprise || state.people.isEmpty
            ? .everyone : .person(state.people.randomElement()!.id))
        let d = DirectorDecision(effect: effect, target: tgt, intensity: chaos ? 1 : 0.7,
                                 reaction: ReactionKind.allCases.randomElement()!, mood: .gleeful,
                                 delay: 0.05, source: .manual)
        hud.lastDecision = d
        play(d)
    }

    private func play(_ decision: DirectorDecision) {
        var d = decision
        if case .person(let id) = d.target, !state.people.contains(where: { $0.id == id }) {
            d.target = state.people.randomElement().map { .person($0.id) } ?? .everyone
        }
        if d.effect == .transform, d.target == .everyone, let p = state.people.randomElement() {
            d.target = .person(p.id)
        }
        let ids: [String] = {
            switch d.target {
            case .person(let id): [id]
            case .everyone: state.people.map(\.id)
            }
        }()
        let trajectory: Trajectory
        let duration: Double
        switch d.effect {
        case .duckRain: trajectory = .rain; duration = 1.3
        case .bubbleBlast, .spongeShot: trajectory = .straight; duration = 0.9
        case .tomatoThrow, .balloonAttack: trajectory = .arc; duration = 1.0
        case .confettiExplosion, .rainbowExplosion, .emojiExplosion, .bubbleStorm: trajectory = .burst; duration = 0.9
        case .transform: trajectory = .burst; duration = 0.6
        case .surprise: trajectory = .sweep; duration = 1.6
        }
        var transformTo: CharacterType?
        if d.effect == .transform, let id = ids.first, let p = state.people.first(where: { $0.id == id }) {
            transformTo = CharacterType.allCases.filter { $0 != p.character }.randomElement()
        }
        let ev = GameEvent(id: UUID(), targetPersonIDs: ids, target: d.target, effect: d.effect,
                           trajectory: trajectory, intensity: max(0, min(1, d.intensity)), delay: d.delay,
                           duration: duration, sound: d.effect.sound, reaction: d.reaction,
                           source: d.source, transformTo: transformTo)
        currentEvent = ev
        state.eventCount += 1
        state.lastEvent = LastEventInfo(effect: d.effect, target: d.target, at: state.elapsedTime)
        emit(.event(ev))
        let targetName: String = {
            if case .person(let id) = d.target, let p = state.people.first(where: { $0.id == id }) {
                return p.character.displayName
            }
            return "everyone"
        }()
        say(Narrator.attack(d.effect, target: targetName, mood: d.mood))
        enter(.gameEvent, for: ev.delay + ev.duration)
        publishHUD()
    }

    private func impact() {
        guard let ev = currentEvent else { enter(.wait, for: cooldown()); return }
        currentEvent = nil
        combo(hit: state.elapsedTime)
        for id in ev.targetPersonIDs {
            guard let i = state.people.firstIndex(where: { $0.id == id }) else { continue }
            state.people[i].timesHit += 1
            if let to = ev.transformTo {
                state.people[i].character = to
                emit(.transformed(personID: id, to))
            }
            emit(.reaction(personID: id, ev.reaction, intensity: ev.intensity))
        }
        enter(.characterReaction, for: 1.0)
    }

    private func combo(hit t: Double) {
        state.combo = t - lastHitAt < 9 ? state.combo + 1 : 1
        lastHitAt = t
        state.difficulty = min(1, state.elapsedTime / 300 + Double(state.combo) * 0.05)
    }

    private func cooldown() -> Double {
        chaos ? Double.random(in: 1.0...2.2) : Double.random(in: 2.5...5.0)
    }

    // MARK: - Controls

    public func reset() {
        generation += 1
        inFlight = false
        currentEvent = nil
        pendingTrigger = nil
        let chaos = state.chaos
        let departed = state.people
        state = GameState()
        state.chaos = chaos
        for p in departed { emit(.escaped(p)) }
        hud = EngineHUD()
        say(Narrator.idle[0])
    }

    // MARK: - Helpers

    private func enter(_ p: ScenePhase, for seconds: Double) {
        state.phase = p
        phaseTimer = seconds
    }

    private func emit(_ o: EngineOutput) {
        outputs.append(o)
        if outputs.count > 500 { outputs.removeFirst(outputs.count - 500) }  // renderer stalled; don't grow forever
    }

    private func say(_ s: String) {
        emit(.narration(s))
        hud.narration = s
    }

    private func publishHUD() {
        hudTimer = 0.2
        hud.phase = state.phase
        hud.people = state.people
        hud.eventCount = state.eventCount
        hud.combo = state.combo
        hud.difficulty = state.difficulty
        hud.idleSeconds = state.idleSeconds
        hud.elapsed = state.elapsedTime
        hud.awaiting = inFlight
    }
}
