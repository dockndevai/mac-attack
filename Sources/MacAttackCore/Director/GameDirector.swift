import Foundation

public protocol GameDirector: AnyObject, Sendable {
    func decide(_ snapshot: GameSnapshot) async throws -> DirectorDecision
}

/// Deterministic-when-seeded RNG so tests and the director can share sampling code.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public enum Sampler {
    /// Sample a key from a probability table after temperature re-weighting (p^(1/T)).
    /// T < 1 sharpens toward the most likely option, T > 1 flattens toward chaos.
    public static func sample<G: RandomNumberGenerator>(_ probs: [String: Double], temperature: Double,
                                                        using rng: inout G) -> String? {
        let keys = probs.keys.sorted()
        guard !keys.isEmpty else { return nil }
        let t = max(0.05, temperature)
        let weights = keys.map { pow(max(probs[$0] ?? 0, 1e-6), 1 / t) }
        let total = weights.reduce(0, +)
        var r = Double.random(in: 0..<total, using: &rng)
        for (k, w) in zip(keys, weights) {
            if r < w { return k }
            r -= w
        }
        return keys.last
    }

    public static func top(_ probs: [String: Double], _ n: Int = 3) -> [(String, Double)] {
        probs.sorted { $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) }
    }
}

/// Local fallback director: weighted random with a bit of situational taste.
public final class RandomDirector: GameDirector, @unchecked Sendable {
    private var rng: any RandomNumberGenerator
    private let lock = NSLock()

    public init(seed: UInt64? = nil) {
        rng = seed.map { SplitMix64(seed: $0) } ?? SystemRandomNumberGenerator()
    }

    public func decide(_ s: GameSnapshot) async throws -> DirectorDecision {
        decideNow(s)
    }

    public func decideNow(_ s: GameSnapshot) -> DirectorDecision {
        lock.lock(); defer { lock.unlock() }
        let hold = Double.random(in: 0..<1, using: &rng) < (s.chaos ? 0.04 : 0.12) && s.trigger == DecisionTrigger.timer.rawValue
        var effectWeights: [EffectKind: Double] = [:]
        for e in EffectKind.projectiles { effectWeights[e] = 3 }
        for e in EffectKind.areas { effectWeights[e] = s.people_count >= 2 ? 2.5 : 1 }
        effectWeights[.transform] = 1
        effectWeights[.surprise] = s.chaos ? 1.5 : 0.5
        if s.trigger == DecisionTrigger.personArrived.rawValue { effectWeights[.confettiExplosion, default: 0] += 3 }
        if let last = s.last_event, let e = EffectKind(rawValue: last.effect) { effectWeights[e]? *= 0.3 }
        let effect = weighted(effectWeights)

        let target: EventTarget
        if s.people.isEmpty || effect.isArea || effect == .surprise {
            target = .everyone
        } else {
            // prefer newcomers and movers
            var tw: [String: Double] = [:]
            for p in s.people { tw[p.id] = 1 + (p.dwell_time < 4 ? 2 : 0) + p.velocity * 4 }
            target = .person(weighted(tw))
        }
        let reactionWeights: [ReactionKind: Double] = [.dodge: 2, .jump: 2, .shake: 2, .spin: 1.5, .shrink: 1,
                                                       .grow: 1, .explode: effect == .tomatoThrow ? 2 : 0.8, .celebrate: 1.5]
        let mood: DirectorMood = s.trigger == DecisionTrigger.personArrived.rawValue ? .alarmed
            : s.combo >= 3 ? .gleeful : [.mischievous, .mischievous, .bored, .gleeful].randomElement(using: &rng)!
        return DirectorDecision(holdBack: hold, effect: effect, target: target,
                                intensity: Double.random(in: s.chaos ? 0.6...1 : 0.3...0.9, using: &rng),
                                reaction: weighted(reactionWeights), mood: mood,
                                delay: Double.random(in: 0.1...0.5, using: &rng), source: .fallback)
    }

    private func weighted<K: Hashable & Comparable>(_ w: [K: Double]) -> K {
        let keys = w.keys.sorted()
        let total = keys.reduce(0) { $0 + (w[$1] ?? 0) }
        var r = Double.random(in: 0..<total, using: &rng)
        for k in keys {
            r -= w[k] ?? 0
            if r < 0 { return k }
        }
        return keys.last!
    }
}

extension EffectKind: Comparable {
    public static func < (a: EffectKind, b: EffectKind) -> Bool { a.rawValue < b.rawValue }
}

extension ReactionKind: Comparable {
    public static func < (a: ReactionKind, b: ReactionKind) -> Bool { a.rawValue < b.rawValue }
}
