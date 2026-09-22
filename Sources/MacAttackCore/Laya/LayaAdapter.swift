import Foundation

// MARK: - Wire types (mirror LayaDirector/server.py and Laya's `system_one` answer format)

public struct LayaStatus: Decodable, Sendable {
    public var state: String            // loading | ready | error
    public var error: String?
    public var device: String?
    public var model: String?
    public var decisions: Int?
    public var last_latency_ms: Double?
    public var avg_latency_ms: Double?
}

public struct LayaAnswer: Decodable, Sendable {
    public var type: String
    public var choice: String?
    public var score: Double?
    public var noul: Double?
    public var probabilities: [String: Double]?
    public var confidence: Double?
}

public struct LayaResponse: Decodable, Sendable {
    public var answers: [String: LayaAnswer]?
    public var situation: String?
    public var latency_ms: Double?
    public var device: String?
    public var error: String?
}

public enum LayaError: Error, CustomStringConvertible {
    case notReady(String)
    case badResponse(String)
    case timeout

    public var description: String {
        switch self {
        case .notReady(let s): "Laya not ready (\(s))"
        case .badResponse(let s): "bad Laya response: \(s)"
        case .timeout: "Laya timed out"
        }
    }
}

// MARK: - HTTP client to the local sidecar

/// Talks to the local Laya sidecar on 127.0.0.1. Sends only `GameSnapshot` JSON.
public final class LayaAdapter: GameDirector, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession
    /// Debug hook: ask the sidecar to sleep this long before answering.
    public var artificialDelay: Double = 0
    public var chaosTemperature: Double = 1.8
    private var rng = SystemRandomNumberGenerator()

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8777")!) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.urlCache = nil
        session = URLSession(configuration: cfg)
    }

    public func status() async throws -> LayaStatus {
        var req = URLRequest(url: baseURL.appendingPathComponent("status"))
        req.timeoutInterval = 1.5
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(LayaStatus.self, from: data)
    }

    public func raw(_ snapshot: GameSnapshot) async throws -> LayaResponse {
        var comps = URLComponents(url: baseURL.appendingPathComponent("decide"), resolvingAgainstBaseURL: false)!
        if artificialDelay > 0 { comps.queryItems = [URLQueryItem(name: "delay", value: String(artificialDelay))] }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(snapshot)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw LayaError.badResponse("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let r = try JSONDecoder().decode(LayaResponse.self, from: data)
        if let e = r.error { throw LayaError.notReady(e) }
        return r
    }

    public func decide(_ snapshot: GameSnapshot) async throws -> DirectorDecision {
        let r = try await raw(snapshot)
        var g = rng
        let d = try LayaDecisionMapper.map(r, snapshot: snapshot,
                                           temperature: snapshot.chaos ? chaosTemperature : 1.0, using: &g)
        rng = g
        return d
    }
}

// MARK: - Probabilities → decision

/// Laya returns calibrated distributions; the game samples them rather than taking argmax, so the
/// same situation can play out differently while still following Laya's taste.
public enum LayaDecisionMapper {
    public static func map<G: RandomNumberGenerator>(_ r: LayaResponse, snapshot s: GameSnapshot,
                                                     temperature t: Double, using rng: inout G) throws -> DirectorDecision {
        guard let a = r.answers else { throw LayaError.badResponse("no answers") }
        func probs(_ k: String) throws -> [String: Double] {
            guard let p = a[k]?.probabilities, !p.isEmpty else { throw LayaError.badResponse("missing \(k)") }
            return p
        }
        var rationale: [String: [(String, Double)]] = [:]

        // How much a just-used effect is discouraged, newest first. Without this the game locks
        // onto whatever Laya likes in a given scene: for one stationary person it puts ~90% on
        // "surprise" every single time, so every decision came back the same.
        func recencyPenalty(_ effect: String) -> Double {
            // hard stop: the same gag never runs three times in a row
            if s.recent_effects.count >= 2, s.recent_effects[0] == effect, s.recent_effects[1] == effect { return 0 }
            guard let i = s.recent_effects.firstIndex(of: effect) else { return 1 }
            return [0.08, 0.25, 0.45, 0.7][min(i, 3)]
        }
        // Rarity priors + cooldowns: the stunts punctuate the game, they don't carry it. Laya is
        // very keen on "surprise" for a lone stationary person (~90%), so it gets a hard cooldown.
        let stylePrior = ["projectile": 1.3, "area": 1.0, "transform": 0.6, "surprise": 0.25]
        let cooldown = ["surprise": 5, "transform": 3]   // events that must pass before reuse

        var style = try probs("style")
        if s.people.isEmpty { style["projectile"] = 0; style["transform"] = 0 }
        for k in style.keys {
            style[k]! *= stylePrior[k] ?? 1
            // a style is stale if the effects it produces were just used
            switch k {
            case "surprise", "transform":
                style[k]! *= s.recent_effects.prefix(cooldown[k] ?? 0).contains(k) ? 0 : recencyPenalty(k)
            // a category stays attractive as long as ONE of its effects is still fresh
            case "projectile": style[k]! *= EffectKind.projectiles.map { recencyPenalty($0.rawValue) }.max() ?? 1
            case "area": style[k]! *= EffectKind.areas.map { recencyPenalty($0.rawValue) }.max() ?? 1
            default: break
            }
        }
        rationale["style"] = Sampler.top(style)
        let styleKey = Sampler.sample(style, temperature: t, using: &rng) ?? "projectile"

        func pick(_ k: String) throws -> EffectKind {
            var p = try probs(k)
            for key in p.keys { p[key]! *= recencyPenalty(key) }
            rationale[k] = Sampler.top(p)
            let key = Sampler.sample(p, temperature: t, using: &rng)
            guard let key, let e = EffectKind(rawValue: key) else { throw LayaError.badResponse("unknown effect \(key ?? "nil")") }
            return e
        }
        let effect: EffectKind
        switch styleKey {
        case "area": effect = try pick("area")
        case "transform": effect = .transform
        case "surprise": effect = .surprise
        default: effect = try pick("projectile")
        }

        var target = EventTarget.everyone
        if !effect.isArea && effect != .surprise && !s.people.isEmpty {
            let tp = try probs("target")
            rationale["target"] = Sampler.top(tp)
            let key = Sampler.sample(tp, temperature: t, using: &rng) ?? "everyone"
            if s.people.contains(where: { $0.id == key }) {
                target = .person(key)
            } else if effect == .transform {
                target = .person(s.people.randomElement(using: &rng)!.id)
            }
        }

        let ip = try probs("intensity")
        rationale["intensity"] = Sampler.top(ip, 4)
        let level = Double(Sampler.sample(ip, temperature: t, using: &rng) ?? "1") ?? 1
        var intensity = (level + Double.random(in: 0.2...0.8, using: &rng)) / 4
        if s.chaos { intensity = min(1, intensity + 0.2) }

        let rp = try probs("reaction")
        rationale["reaction"] = Sampler.top(rp)
        let reaction = ReactionKind(rawValue: Sampler.sample(rp, temperature: t, using: &rng) ?? "") ?? .jump

        let mp = try probs("mood")
        rationale["mood"] = Sampler.top(mp)
        let mood = DirectorMood(rawValue: Sampler.sample(mp, temperature: t, using: &rng) ?? "") ?? .mischievous

        // Laya's hold_back probability is usually high-ish; scale it so "doing nothing" is an
        // occasional dramatic pause, and never on arrivals.
        let hb = a["hold_back"]?.noul ?? 0
        rationale["hold_back"] = [("p", hb)]
        let holdBack = s.trigger == DecisionTrigger.timer.rawValue
            && Double.random(in: 0..<1, using: &rng) < hb * (s.chaos ? 0.08 : 0.3)

        return DirectorDecision(holdBack: holdBack, effect: effect, target: target, intensity: intensity,
                                reaction: reaction, mood: mood,
                                delay: Double.random(in: 0.1...0.4, using: &rng), source: .laya,
                                latencyMs: r.latency_ms, rationale: rationale, situation: r.situation)
    }
}
