import Foundation
import Testing
@testable import MacAttackCore

// MARK: - Tracker

@Suite struct TrackerTests {
    let a = NormRect(x: 0.1, y: 0.3, width: 0.2, height: 0.4)
    let b = NormRect(x: 0.6, y: 0.3, width: 0.2, height: 0.4)

    @Test func confirmsAfterMinHits() {
        let t = PersonTracker()
        #expect(t.update(detections: [a], at: 0.0).isEmpty)
        #expect(t.update(detections: [a], at: 0.1).isEmpty)
        let s = t.update(detections: [a], at: 0.2)
        #expect(s.count == 1)
        #expect(s[0].id == "person-1")
    }

    @Test func singleFrameFalsePositiveNeverAppears() {
        let t = PersonTracker()
        t.update(detections: [a], at: 0)
        for i in 1...20 { #expect(t.update(detections: [], at: Double(i) * 0.1).isEmpty) }
    }

    @Test func survivesBriefDropoutThenLeaves() {
        let t = PersonTracker()
        for i in 0..<4 { t.update(detections: [a], at: Double(i) * 0.1) }
        #expect(t.update(detections: [], at: 0.8).count == 1)   // 0.5 s unseen: still there
        #expect(t.update(detections: [a], at: 0.9).first?.id == "person-1")  // same id after dropout
        #expect(t.update(detections: [], at: 2.3).isEmpty)       // 1.4 s unseen: gone
    }

    @Test func multiplePeopleKeepStableIds() {
        let t = PersonTracker()
        var s: [TrackSnapshot] = []
        for i in 0..<5 {
            let dx = Double(i) * 0.01
            s = t.update(detections: [NormRect(x: a.x + dx, y: a.y, width: a.width, height: a.height),
                                      NormRect(x: b.x - dx, y: b.y, width: b.width, height: b.height)],
                         at: Double(i) * 0.1)
        }
        #expect(s.count == 2)
        let left = s.min { $0.box.x < $1.box.x }!
        #expect(left.id == "person-1" || left.id == "person-2")
        // swap detection order: ids must follow positions, not array order
        let s2 = t.update(detections: [b, a], at: 0.5)
        #expect(Set(s2.map(\.id)) == Set(s.map(\.id)))
        #expect(s2.first { $0.box.x < 0.4 }!.id == left.id)
    }

    @Test func detectsLeftwardMovement() {
        let t = PersonTracker()
        var s: [TrackSnapshot] = []
        for i in 0..<12 {
            s = t.update(detections: [NormRect(x: 0.7 - Double(i) * 0.03, y: 0.3, width: 0.2, height: 0.4)], at: Double(i) * 0.1)
        }
        #expect(s.first?.movement == .left)
        #expect((s.first?.vx ?? 0) < -0.1)
    }

    @Test func stationaryIsStationary() {
        let t = PersonTracker()
        var s: [TrackSnapshot] = []
        for i in 0..<12 { s = t.update(detections: [a], at: Double(i) * 0.1) }
        #expect(s.first?.movement == .stationary)
        #expect((s.first?.dwell ?? 0) > 1.0)
    }
}

// MARK: - Sampling / Laya mapping

@Suite struct SamplingTests {
    @Test func temperatureSharpens() {
        var rng = SplitMix64(seed: 42)
        let p = ["a": 0.6, "b": 0.3, "c": 0.1]
        var counts: [String: Int] = [:]
        for _ in 0..<2000 { counts[Sampler.sample(p, temperature: 0.2, using: &rng)!, default: 0] += 1 }
        #expect(counts["a", default: 0] > 1900)
    }

    @Test func faithfulAtT1() {
        var rng = SplitMix64(seed: 7)
        let p = ["a": 0.7, "b": 0.3]
        var a = 0
        for _ in 0..<5000 where Sampler.sample(p, temperature: 1, using: &rng) == "a" { a += 1 }
        #expect(abs(Double(a) / 5000 - 0.7) < 0.03)
    }

    static func response(style: String) -> LayaResponse {
        func choice(_ p: [String: Double]) -> LayaAnswer {
            LayaAnswer(type: "choice", choice: p.max { $0.value < $1.value }?.key, probabilities: p)
        }
        return LayaResponse(answers: [
            "style": choice([style: 1.0]),
            "projectile": choice(["tomato_throw": 1.0]),
            "area": choice(["bubble_storm": 1.0]),
            "target": choice(["person-2": 1.0]),
            "intensity": LayaAnswer(type: "score", score: 3, probabilities: ["3": 1.0]),
            "reaction": choice(["spin": 1.0]),
            "hold_back": LayaAnswer(type: "noul", noul: 0.0),
            "mood": choice(["gleeful": 1.0]),
        ], situation: "test", latency_ms: 12)
    }

    func snapshot(people: Int, trigger: DecisionTrigger = .timer) -> GameSnapshot {
        var st = GameState()
        st.people = (1...max(1, people)).prefix(people).map {
            Person(id: "person-\($0)", box: NormRect(x: 0.2, y: 0.3, width: 0.2, height: 0.4), vx: 0, vy: 0,
                   movement: .stationary, character: .frog, lifetime: 3, timesHit: 0, number: $0)
        }
        return GameSnapshot(state: st, trigger: trigger)
    }

    @Test func mapsProjectileDecision() throws {
        var rng = SplitMix64(seed: 1)
        let d = try LayaDecisionMapper.map(Self.response(style: "projectile"), snapshot: snapshot(people: 2),
                                           temperature: 1, using: &rng)
        #expect(d.effect == .tomatoThrow)
        #expect(d.target == .person("person-2"))
        #expect(d.reaction == .spin)
        #expect(d.mood == .gleeful)
        #expect(d.intensity > 0.75)
        #expect(d.source == .laya)
        #expect(!d.holdBack)
    }

    @Test func areaEffectTargetsEveryone() throws {
        var rng = SplitMix64(seed: 1)
        let d = try LayaDecisionMapper.map(Self.response(style: "area"), snapshot: snapshot(people: 2),
                                           temperature: 1, using: &rng)
        #expect(d.effect == .bubbleStorm)
        #expect(d.target == .everyone)
    }

    @Test func snapshotContainsOnlyAbstractFields() throws {
        let data = try JSONEncoder().encode(snapshot(people: 1))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let person = (obj["people"] as! [[String: Any]])[0]
        #expect(Set(person.keys) == ["id", "x", "y", "width", "height", "movement", "velocity", "dwell_time", "character", "times_hit"])
    }
}

// MARK: - Engine state machine

final class StubDirector: @unchecked Sendable {
    var calls: [DecisionTrigger] = []
    var decision = DirectorDecision(effect: .bubbleBlast, target: .person("person-1"), intensity: 0.5,
                                    reaction: .jump, delay: 0, source: .fallback)
}

@MainActor
@Suite struct EngineTests {
    func person(_ id: String, x: Double = 0.3) -> TrackSnapshot {
        TrackSnapshot(id: id, box: .centered(x: x, y: 0.5, width: 0.2, height: 0.5), dwell: 1)
    }

    func run(_ e: GameEngine, seconds: Double) async {
        var t = 0.0
        while t < seconds {
            e.tick(1.0 / 60)
            t += 1.0 / 60
            await Task.yield()
        }
    }

    @Test func fullLoopIdleToEventToWait() async {
        let stub = StubDirector()
        let e = GameEngine { _, trig, _ in stub.calls.append(trig); return stub.decision }
        #expect(e.phase == .idle)
        e.updatePeople([person("person-1")])
        e.tick(0.016)
        #expect(e.phase == .personDetected || e.phase == .characterSpawned)
        await run(e, seconds: 1.0)
        #expect(stub.calls.first == .personArrived)
        let outs = e.drainOutputs()
        #expect(outs.contains { if case .spawned = $0 { true } else { false } })
        #expect(outs.contains { if case .event(let ev) = $0 { ev.effect == .bubbleBlast } else { false } })
        await run(e, seconds: 1.2)
        let outs2 = e.drainOutputs()
        #expect(outs2.contains { if case .reaction(let id, .jump, _) = $0 { id == "person-1" } else { false } })
        await run(e, seconds: 1.2)
        #expect(e.phase == .wait || e.phase == .awaitingDecision || e.phase == .gameEvent)
        #expect(e.people[0].timesHit == 1)
        // cooldown elapses → timer-triggered decision
        await run(e, seconds: 6)
        #expect(stub.calls.contains(.timer))
    }

    @Test func personLeavingEscapesThenIdle() async {
        let stub = StubDirector()
        let e = GameEngine { _, trig, _ in stub.calls.append(trig); return stub.decision }
        e.updatePeople([person("person-1")])
        await run(e, seconds: 0.5)
        e.updatePeople([])
        #expect(e.phase == .escape)
        #expect(e.drainOutputs().contains { if case .escaped = $0 { true } else { false } })
        await run(e, seconds: 2)
        #expect(e.phase == .idle)
    }

    @Test func holdBackDoesNothing() async {
        let stub = StubDirector()
        stub.decision.holdBack = true
        let e = GameEngine { _, _, _ in stub.decision }
        e.updatePeople([person("person-1")])
        await run(e, seconds: 1.5)
        let outs = e.drainOutputs()
        #expect(!outs.contains { if case .event = $0 { true } else { false } })
        #expect(e.phase == .wait)
    }

    @Test func multiplePeopleGetDistinctCharacters() {
        let e = GameEngine { _, _, _ in StubDirector().decision }
        e.updatePeople((1...4).map { person("person-\($0)", x: Double($0) * 0.2) })
        #expect(Set(e.people.map(\.character)).count == 4)
    }

    @Test func staleTargetIsRetargeted() async {
        let stub = StubDirector()
        stub.decision.target = .person("person-99")
        let e = GameEngine { _, _, _ in stub.decision }
        e.updatePeople([person("person-1")])
        await run(e, seconds: 1.2)
        let ev = e.drainOutputs().compactMap { if case .event(let ev) = $0 { ev } else { nil } }.first
        #expect(ev?.targetPersonIDs == ["person-1"])
    }

    @Test func stuckDirectorFallsBackLocally() async {
        // director never answers: engine's own guard must keep the game moving
        let e = GameEngine { _, _, _ in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            return StubDirector().decision
        }
        e.decisionTimeout = 0.5
        e.updatePeople([person("person-1")])
        await run(e, seconds: 2.5)
        #expect(e.drainOutputs().contains { if case .event(let ev) = $0 { ev.source == .fallback } else { false } })
    }

    @Test func manualEffectPlaysImmediately() {
        let e = GameEngine { _, _, _ in StubDirector().decision }
        e.updatePeople([person("person-1")])
        e.triggerEffect(.confettiExplosion)
        #expect(e.phase == .gameEvent)
        #expect(e.drainOutputs().contains { if case .event(let ev) = $0 { ev.source == .manual && ev.target == .everyone } else { false } })
    }

    @Test func transformChangesCharacter() async {
        let stub = StubDirector()
        stub.decision.effect = .transform
        let e = GameEngine { _, _, _ in stub.decision }
        e.updatePeople([person("person-1")])
        let before = e.people[0].character
        await run(e, seconds: 2.5)
        #expect(e.people[0].character != before)
    }

    @Test func repeatedEnterLeaveIsStable() async {
        let e = GameEngine { _, _, _ in StubDirector().decision }
        for i in 0..<50 {
            e.updatePeople(i % 2 == 0 ? [person("person-\(i)")] : [])
            await run(e, seconds: 0.3)
            _ = e.drainOutputs()
        }
        e.updatePeople([])
        await run(e, seconds: 2)
        #expect(e.phase == .idle)
        #expect(e.people.isEmpty)
    }
}

// MARK: - Coordinator fallback

@MainActor
@Suite struct CoordinatorTests {
    @Test func unreachableLayaUsesFallback() async {
        let c = DirectorCoordinator(laya: LayaAdapter(baseURL: URL(string: "http://127.0.0.1:9")!))
        _ = await c.pollOnce()
        if case .unavailable = c.health {} else { Issue.record("expected unavailable, got \(c.health)") }
        let d = await c.decide(GameSnapshot(state: GameState(), trigger: .timer), trigger: .timer, time: 0)
        #expect(d.source == .fallback)
        #expect(c.directorLabel == "Local Fallback")
        #expect(c.log.first?.note?.contains("fallback") == true)
    }

    @Test func timeoutHelperThrows() async {
        await #expect(throws: LayaError.self) {
            try await withTimeout(0.1) { try await Task.sleep(nanoseconds: 2_000_000_000); return 1 }
        }
    }
}

// MARK: - Simulation

@Suite struct SimulationTests {
    @Test func producesTracksAndStaysInBounds() {
        let w = SimulationWorld()
        w.spawn(behavior: .frantic)
        w.spawn(behavior: .left)
        var s: [TrackSnapshot] = []
        for _ in 0..<600 { s = w.tick(1.0 / 60) }
        #expect(s.count == 2)
        for t in s { #expect(t.box.x >= 0 && t.box.x + t.box.width <= 1) }
    }

    @Test func autopilotChangesPopulation() {
        let w = SimulationWorld()
        w.autopilot = true
        var counts = Set<Int>()
        for _ in 0..<(60 * 120) { counts.insert(w.tick(1.0 / 60).count) }
        #expect(counts.count >= 2)
        #expect(counts.max()! <= w.maxPeople)
    }
}
