import Foundation
import Observation

public enum LayaHealth: Equatable, Sendable {
    case unknown, loading, ready, unavailable(String), disabled

    public var label: String {
        switch self {
        case .unknown: "CONNECTING"
        case .loading: "LOADING"
        case .ready: "READY"
        case .unavailable: "OFFLINE"
        case .disabled: "DISABLED"
        }
    }
}

public struct DecisionLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public var time: Double
    public var trigger: DecisionTrigger
    public var decision: DirectorDecision
    public var note: String?
}

/// Asks Laya when it is healthy and answers in time; otherwise the local RandomDirector decides.
/// The game never waits longer than `timeout` for a decision.
@MainActor
@Observable
public final class DirectorCoordinator {
    public private(set) var health: LayaHealth = .unknown
    public private(set) var lastSource: DirectorSource = .fallback
    public private(set) var lastLatencyMs: Double?
    public private(set) var layaDevice: String?
    public private(set) var log: [DecisionLogEntry] = []
    public private(set) var layaDecisions = 0
    public private(set) var fallbackDecisions = 0
    public private(set) var lastError: String?

    public var useLaya = true { didSet { if !useLaya { health = .disabled } else if health == .disabled { health = .unknown; pokeStatus() } } }
    public var simulateSlowLaya = false { didSet { laya.artificialDelay = simulateSlowLaya ? 3.0 : 0 } }
    public var timeout: Double = 2.0

    @ObservationIgnored public let laya: LayaAdapter
    @ObservationIgnored public let fallback: RandomDirector
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var failures = 0

    public init(laya: LayaAdapter = LayaAdapter(), fallback: RandomDirector = RandomDirector()) {
        self.laya = laya
        self.fallback = fallback
    }

    public var directorLabel: String { lastSource == .laya ? "Laya" : lastSource.rawValue }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            var backoff = 1.0
            while !Task.isCancelled {
                guard let self else { return }
                let ok = await self.pollOnce()
                backoff = ok ? (self.health == .ready ? 5 : 1) : min(10, backoff * 1.6)
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1e9))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pokeStatus() { Task { _ = await pollOnce() } }

    @discardableResult
    func pollOnce() async -> Bool {
        guard useLaya else { health = .disabled; return true }
        do {
            let s = try await laya.status()
            layaDevice = s.device
            switch s.state {
            case "ready": health = .ready; failures = 0
            case "loading": health = .loading
            default: health = .unavailable(s.error ?? s.state)
            }
            return true
        } catch {
            health = .unavailable("sidecar not reachable")
            return false
        }
    }

    /// Always returns a decision. Laya first (bounded by `timeout`), local fallback otherwise.
    public func decide(_ snapshot: GameSnapshot, trigger: DecisionTrigger, time: Double) async -> DirectorDecision {
        var note: String?
        if useLaya && health == .ready {
            do {
                let d = try await withTimeout(timeout) { [laya] in try await laya.decide(snapshot) }
                failures = 0
                lastSource = .laya
                lastLatencyMs = d.latencyMs
                layaDecisions += 1
                append(DecisionLogEntry(time: time, trigger: trigger, decision: d, note: nil))
                return d
            } catch {
                failures += 1
                note = "fallback: \(error)"
                lastError = "\(error)"
                if failures >= 3 { health = .unavailable("\(failures) failures"); pokeStatus() }
            }
        } else if useLaya {
            note = "fallback: Laya \(health.label.lowercased())"
        } else {
            note = "fallback: Laya disabled"
        }
        let d = fallback.decideNow(snapshot)
        lastSource = .fallback
        fallbackDecisions += 1
        append(DecisionLogEntry(time: time, trigger: trigger, decision: d, note: note))
        return d
    }

    public func recordManual(_ d: DirectorDecision, time: Double) {
        append(DecisionLogEntry(time: time, trigger: .manual, decision: d, note: "manual"))
    }

    private func append(_ e: DecisionLogEntry) {
        log.insert(e, at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
    }
}

public func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { g in
        g.addTask { try await op() }
        g.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            throw LayaError.timeout
        }
        defer { g.cancelAll() }
        return try await g.next()!
    }
}
