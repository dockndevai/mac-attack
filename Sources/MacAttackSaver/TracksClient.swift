import Foundation
import MacAttackCore
import MacAttackKit

/// Polls the Mac Attack helper for anonymous person boxes, and starts the helper if it isn't
/// running. A screensaver can never get camera access itself (macOS attributes the request to
/// Apple's screensaver host), so the helper owns the camera and sends only rectangles.
@MainActor
final class TracksClient {
    enum State: Equatable {
        case connecting, running(String), helperMissing(String), launching

        var label: String {
            switch self {
            case .connecting: "connecting to helper…"
            case .running(let c): "helper camera: \(c)"
            case .helperMissing(let why): "helper unavailable (\(why))"
            case .launching: "starting helper…"
            }
        }
    }

    private(set) var state: State = .connecting
    private var badSince: Date?

    /// What (if anything) to tell the viewer at the bottom of the screen.
    var hint: String? {
        switch state {
        case .running(let camera):
            return camera == "ACTIVE" || camera.isEmpty ? nil : "Camera: \(camera.lowercased())"
        case .connecting, .launching:
            return (badSince.map { Date().timeIntervalSince($0) > 5 } ?? false) ? "Starting the Mac Attack helper…" : nil
        case .helperMissing:
            return "Open Mac Attack → Debug Mode → Install Helper, so the screensaver can see the room"
        }
    }
    private(set) var videoAspect: CGFloat?
    var onTracks: (([TrackSnapshot]) -> Void)?

    private let url = URL(string: "http://127.0.0.1:8778/tracks")!
    private let session: URLSession
    private var task: Task<Void, Never>?
    private var launchAttempts = 0
    private var helperProcess: Process?

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        cfg.urlCache = nil
        session = URLSession(configuration: cfg)
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: 100_000_000)   // 10 Hz, matches detection rate
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        // The helper's lease expires a few seconds later and its camera switches off.
    }

    private func pollOnce() async {
        do {
            let (data, _) = try await session.data(from: url)
            let snap = try JSONDecoder().decode(PerceptionServer.Snapshot.self, from: data)
            launchAttempts = 0
            badSince = nil
            state = .running(snap.camera)
            if snap.height > 0 { videoAspect = snap.width / snap.height }
            onTracks?(snap.tracks.map {
                TrackSnapshot(id: $0.id, box: NormRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h),
                              vx: $0.vx, vy: $0.vy,
                              movement: MovementState(rawValue: $0.movement) ?? .stationary, dwell: $0.dwell)
            })
        } catch {
            if badSince == nil { badSince = Date() }
            onTracks?([])
            launchHelperIfNeeded()
        }
    }

    /// A screensaver can spawn processes, but anything it spawns inherits its sandbox and is then
    /// denied the camera (and `open` is blocked), so this is only a best-effort nudge: the helper
    /// is really meant to be started by launchd (Install Helper in the app).
    private func launchHelperIfNeeded() {
        if case .launching = state, helperProcess?.isRunning == true { return }
        guard launchAttempts < 3 else {
            state = .helperMissing("start Mac Attack helper manually")
            return
        }
        guard let path = Bundle(for: MacAttackSaverView.self).object(forInfoDictionaryKey: "MacAttackAppPath") as? String,
              FileManager.default.fileExists(atPath: path) else {
            state = .helperMissing("app not found")
            return
        }
        launchAttempts += 1
        state = .launching
        // Launch through LaunchServices (`open`), not directly: a process spawned by the
        // screensaver inherits its sandbox and would be denied the camera.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", "-a", path, "--args", "--helper"]
        do {
            try p.run()
            helperProcess = p
        } catch {
            state = .helperMissing(error.localizedDescription)
        }
    }
}
