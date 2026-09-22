import Foundation
import MacAttackCore
import Network
import Observation

/// Publishes anonymous person boxes on 127.0.0.1 so the screensaver (which macOS never grants
/// camera access) can render the game while this process owns the camera.
///
/// Only rectangles and motion cross the socket: no images, ever. The camera runs only while a
/// client is actually polling (a lease), so it switches off moments after the screensaver stops.
@MainActor
@Observable
public final class PerceptionServer {
    public struct Track: Codable, Sendable {
        public var id: String
        public var x: Double, y: Double, w: Double, h: Double
        public var vx: Double, vy: Double
        public var movement: String
        public var dwell: Double
    }

    public struct Snapshot: Codable, Sendable {
        public var camera: String
        public var width: Double
        public var height: Double
        public var tracks: [Track]
        public var t: Double
    }

    public private(set) var clientCount = 0
    public private(set) var lastRequest: Date?
    public private(set) var listening = false
    public private(set) var requests = 0
    public private(set) var lastError: String?
    /// Called when a client starts polling (true) or stops for `leaseTimeout` (false).
    public var onLease: ((Bool) -> Void)?
    public var leaseTimeout: Double = 4

    @ObservationIgnored private let port: UInt16
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var leaseActive = false
    @ObservationIgnored private var leaseTimer: Timer?
    @ObservationIgnored private var payload = Data("{\"camera\":\"starting\",\"width\":16,\"height\":9,\"tracks\":[],\"t\":0}".utf8)

    public init(port: UInt16 = 8778) { self.port = port }

    public func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        // Loopback only: the endpoint carries the port, so don't also pass `on:` (that combination
        // makes NWListener throw).
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = true
        let l: NWListener
        do {
            l = try NWListener(using: params)
        } catch {
            lastError = "listener: \(error)"
            NSLog("MacAttack: perception listener failed: %@", "\(error)")
            return
        }
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            Task { @MainActor in self?.serve(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.listening = (state == .ready)
                if case .failed(let e) = state {
                    self?.lastError = "\(e)"
                    NSLog("MacAttack: perception listener state failed: %@", "\(e)")
                }
            }
        }
        l.start(queue: .main)
        listener = l
        leaseTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkLease() }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        leaseTimer?.invalidate()
        leaseTimer = nil
        listening = false
        if leaseActive { leaseActive = false; onLease?(false) }
    }

    /// Latest tracks from the camera pipeline (called ~10×/s).
    public func publish(tracks: [TrackSnapshot], camera: String, size: CGSize) {
        let snap = Snapshot(
            camera: camera, width: size.width, height: size.height,
            tracks: tracks.map { t in
                Track(id: t.id, x: round(t.box.x * 1000) / 1000, y: round(t.box.y * 1000) / 1000,
                      w: round(t.box.width * 1000) / 1000, h: round(t.box.height * 1000) / 1000,
                      vx: round(t.vx * 1000) / 1000, vy: round(t.vy * 1000) / 1000,
                      movement: t.movement.rawValue, dwell: round(t.dwell * 10) / 10)
            },
            t: Date().timeIntervalSince1970)
        if let d = try? JSONEncoder().encode(snap) { payload = d }
    }

    // MARK: - Minimal HTTP

    private func serve(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, _, _ in
            guard let self, let data, let head = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            Task { @MainActor in
                self.requests += 1
                self.lastRequest = Date()
                if !self.leaseActive { self.leaseActive = true; self.onLease?(true) }
                let body = head.hasPrefix("GET /tracks") ? self.payload : Data("{\"ok\":true}".utf8)
                var resp = Data("""
                HTTP/1.1 200 OK\r
                Content-Type: application/json\r
                Content-Length: \(body.count)\r
                Connection: close\r
                \r\n
                """.utf8)
                resp.append(body)
                conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
    }

    private func checkLease() {
        guard leaseActive, let last = lastRequest else { return }
        if Date().timeIntervalSince(last) > leaseTimeout {
            leaseActive = false
            onLease?(false)
        }
    }

    public var isLeased: Bool { leaseActive }
}
