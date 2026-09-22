import AppKit
import MacAttackKit
import MacAttackCore
import Observation
import QuartzCore

enum InputMode: String, CaseIterable, Identifiable {
    case camera = "Camera"
    case simulation = "Simulation"
    var id: String { rawValue }
}

struct LaunchOptions {
    var simulate = false, autopilot = false, debug = false, chaos = false, noSidecar = false, noSound = false
    var slowLaya = false
    /// Open full screen (used for recording demos).
    var fullscreen = false
    /// Menu-bar-only mode: owns the camera for the screensaver, no game window.
    var helper = false
    var layaPort = 8777

    static func parse(_ args: [String] = CommandLine.arguments) -> LaunchOptions {
        var o = LaunchOptions()
        o.simulate = args.contains("--simulate")
        o.autopilot = args.contains("--autopilot")
        o.debug = args.contains("--debug")
        o.chaos = args.contains("--chaos")
        o.noSidecar = args.contains("--no-sidecar")
        o.noSound = args.contains("--no-sound")
        o.slowLaya = args.contains("--slow-laya")
        o.helper = args.contains("--helper")
        o.fullscreen = args.contains("--fullscreen")
        if let i = args.firstIndex(of: "--laya-port"), i + 1 < args.count, let p = Int(args[i + 1]) { o.layaPort = p }
        if o.autopilot { o.simulate = true }
        return o
    }
}

/// Wires camera → detector → tracker → engine ← director, and simulation → engine.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    private(set) var mode: InputMode
    var debug: Bool
    var sound: Bool { didSet { scene.soundEnabled = sound } }
    var chaos: Bool { didSet { engine.chaos = chaos } }
    var showBoxes = true { didSet { scene.showDebugBoxes = debug && showBoxes } }
    var upperBodyOnly = true { didSet { detector.upperBodyOnly = upperBodyOnly } }
    var faceAssist = true { didSet { detector.faceAssist = faceAssist } }
    var autopilot: Bool { didSet { sim.autopilot = autopilot } }
    private(set) var detectionFPS = 0.0
    private(set) var detectionMs = 0.0
    private(set) var rawCount = 0
    private(set) var simPeople: [SimulationWorld.SimPerson] = []
    private(set) var helperClientActive = false
    private(set) var helperInstalled = false
    private(set) var helperRunning = false

    @ObservationIgnored let coordinator: DirectorCoordinator
    @ObservationIgnored let engine: GameEngine
    @ObservationIgnored let camera = CameraManager()
    @ObservationIgnored let detector = VisionPersonDetector()
    @ObservationIgnored let tracker = PersonTracker()
    @ObservationIgnored let sim = SimulationWorld()
    @ObservationIgnored let scene: GameScene
    @ObservationIgnored let sidecar: LayaSidecar
    @ObservationIgnored let perception = PerceptionServer()
    @ObservationIgnored let helperAgent = HelperLoginItem()
    @ObservationIgnored let layaSetup = LayaSetup()
    @ObservationIgnored private let options: LaunchOptions
    @ObservationIgnored private var rawDetections: [NormRect] = []
    @ObservationIgnored private var detCount = 0
    @ObservationIgnored private var detWindowStart = CACurrentMediaTime()
    @ObservationIgnored private var simPublishTimer = 0.0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var sidecarWatchdog: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var helperHeartbeat: Timer?
    @ObservationIgnored private var lastTracks: [TrackSnapshot] = []

    var isHelper: Bool { options.helper }
    var wantsFullscreen: Bool { options.fullscreen }

    private init() {
        options = LaunchOptions.parse()
        coordinator = DirectorCoordinator(laya: LayaAdapter(baseURL: URL(string: "http://127.0.0.1:\(options.layaPort)")!))
        coordinator.simulateSlowLaya = options.slowLaya
        engine = GameEngine(coordinator: coordinator)
        scene = GameScene(engine: engine)
        sidecar = LayaSidecar(directory: Self.locateLayaDirector(), port: options.layaPort)
        mode = options.simulate ? .simulation : .camera
        debug = options.debug
        sound = !options.noSound
        chaos = options.chaos
        autopilot = options.autopilot
        engine.chaos = chaos
        sim.autopilot = autopilot
        scene.soundEnabled = sound
        scene.frameHandler = { [weak self] dt in self?.frame(dt) }
        scene.debugBoxes = { [weak self] in
            guard let self else { return [] }
            return self.mode == .camera ? self.rawDetections : self.engine.people.map(\.box)
        }

        let det = detector
        camera.onFrame = { pb in det.process(pb) }
        detector.onResult = { r in
            Task { @MainActor in AppState.shared.handleDetections(r) }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        NSLog("MacAttack: start mode=%@ laya=%@", mode.rawValue, sidecar.directory?.path ?? "nil")
        coordinator.start()
        refreshLayaSetup()
        if !options.noSidecar {
            let sc = sidecar, adapter = coordinator.laya
            Task.detached { await sc.launchIfNeeded(adapter: adapter) }
            // Watchdog: if the sidecar dies or was never reachable, (re)launch it.
            sidecarWatchdog = Task { [weak self] in
                var unreachableFor = 0.0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard let self else { return }
                    if case .unavailable(let why) = self.coordinator.health, why.contains("not reachable"),
                       self.coordinator.useLaya, !self.sidecar.isRunning {
                        unreachableFor += 3
                        if unreachableFor >= 6 { self.sidecar.launch(); unreachableFor = 0 }
                    } else {
                        unreachableFor = 0
                    }
                }
            }
        }
        if options.helper {
            startHelperMode()
        } else {
            applyMode()
        }
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                self?.logStats()
            }
        }
    }

    /// One line a minute to ~/Library/Logs/MacAttack/stats-<port>.log (for soak tests). Counts only.
    private func logStats() {
        let c = coordinator, h = engine.hud
        let line = String(format: "%@ elapsed=%.0f fps=%.1f detfps=%.1f nodes=%d people=%d events=%d laya=%d fallback=%d health=%@ latency=%.0f\n",
                          ISO8601DateFormatter().string(from: Date()), h.elapsed, scene.fps, detectionFPS, scene.liveNodeCount,
                          h.people.count, h.eventCount, c.layaDecisions, c.fallbackDecisions, c.health.label, c.lastLatencyMs ?? -1)
        let url = sidecar.logURL.deletingLastPathComponent().appendingPathComponent("stats-\(options.layaPort).log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(Data(line.utf8)); try? fh.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Screensaver support: serve anonymous tracks, and run the camera only while it is watching.
    private func startHelperMode() {
        mode = .camera
        scene.cameraBackdrop = true
        perception.onLease = { [weak self] active in
            guard let self else { return }
            self.helperClientActive = active
            if active {
                self.camera.start()
            } else {
                self.camera.stop()
                // publish an explicit "camera off" so a late poll can't report a stale ACTIVE
                self.perception.publish(tracks: [], camera: "OFF", size: self.camera.dimensions)
            }
            NSLog("MacAttack helper: screensaver %@ → camera %@", active ? "attached" : "detached", active ? "ON" : "OFF")
        }
        perception.start()
        NSLog("MacAttack: helper mode, perception server starting")
        // Republish once a second so clients always see the true camera state, even when no
        // detections are flowing (camera off, permission denied, no device…).
        helperHeartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.perception.publish(tracks: self.helperClientActive ? self.lastTracks : [],
                                        camera: self.camera.status.label, size: self.camera.dimensions)
            }
        }
    }

    func shutdown() {
        helperHeartbeat?.invalidate()
        perception.stop()
        statsTask?.cancel()
        sidecarWatchdog?.cancel()
        camera.stopNow()
        coordinator.stop()
        sidecar.terminate()
    }

    // MARK: - Mode

    func setMode(_ m: InputMode) {
        guard m != mode else { return }
        mode = m
        applyMode()
    }

    private func applyMode() {
        engine.reset()
        tracker.reset()
        rawDetections = []
        switch mode {
        case .camera:
            sim.clear()
            scene.cameraBackdrop = true
            scene.contentAspect = camera.dimensions.width / max(1, camera.dimensions.height)
            camera.start()
        case .simulation:
            camera.stop()
            scene.cameraBackdrop = false
            scene.contentAspect = nil
        }
        scene.showDebugBoxes = debug && showBoxes
    }

    func refreshLayaSetup() { layaSetup.refresh(layaDirectory: sidecar.directory) }

    func runLayaSetup() {
        layaSetup.run(layaDirectory: sidecar.directory)
    }

    func refreshHelperStatus() {
        helperInstalled = helperAgent.isInstalled
        helperRunning = helperAgent.isRunning
    }

    func toggleHelperAgent() {
        if helperAgent.isInstalled { helperAgent.uninstall() } else { helperAgent.install() }
        refreshHelperStatus()
    }

    func toggleCamera() {
        if camera.status == .running { camera.stop() } else { camera.start() }
    }

    // MARK: - Frame / detection plumbing

    private func frame(_ dt: Double) {
        guard mode == .simulation else { return }
        engine.updatePeople(sim.tick(dt))
        simPublishTimer -= dt
        if simPublishTimer <= 0 {
            simPublishTimer = 0.25
            simPeople = sim.people
        }
    }

    private func handleDetections(_ r: VisionPersonDetector.Result) {
        guard mode == .camera, camera.status == .running else { return }
        rawDetections = r.rects
        scene.contentAspect = camera.dimensions.width / max(1, camera.dimensions.height)
        let tracks = tracker.update(detections: r.rects, at: CACurrentMediaTime())
        engine.updatePeople(tracks)
        if options.helper {
            lastTracks = tracks
            perception.publish(tracks: tracks, camera: camera.status.label, size: camera.dimensions)
        }
        detCount += 1
        let now = CACurrentMediaTime()
        if now - detWindowStart >= 1 {
            detectionFPS = Double(detCount) / (now - detWindowStart)
            detectionMs = r.processingMs
            rawCount = r.rects.count
            detCount = 0
            detWindowStart = now
        }
    }

    // MARK: - Developer controls

    func spawnHumans(_ n: Int) {
        if mode != .simulation { setMode(.simulation) }
        for _ in 0..<n { sim.spawn() }
        simPeople = sim.people
    }

    func clearHumans() {
        sim.clear()
        tracker.reset()
        simPeople = []
    }

    func removeSim(_ id: String) { sim.remove(id); simPeople = sim.people }
    func setBehavior(_ id: String, _ b: SimulationWorld.Behavior) { sim.setBehavior(id, b); simPeople = sim.people }
    func nudge(_ id: String, _ dx: Double) { sim.nudge(id, dx: dx); simPeople = sim.people }
    func cycleMovement() { sim.cycleBehaviors(); simPeople = sim.people }

    func triggerLaya() { engine.requestDecision(.manual) }
    func trigger(_ e: EffectKind) { engine.triggerEffect(e) }

    func resetGame() {
        clearHumans()
        engine.reset()
        scene.clearAll()
    }

    // MARK: - Paths

    /// LayaDirector lives in the repo, not the bundle: env var, then Info.plist (set by
    /// build_app.sh), then walking up from the executable (for `swift run`), then cwd.
    /// A developer checkout keeps its own venv next to the sources; prefer that when present.
    private static func isDevCheckout() -> Bool {
        if let p = Bundle.main.object(forInfoDictionaryKey: "MacAttackLayaDirectory") as? String {
            return FileManager.default.isExecutableFile(atPath: p + "/.venv/bin/python")
        }
        return false
    }

    static func locateLayaDirector() -> URL? {
        let fm = FileManager.default
        func ok(_ u: URL) -> Bool { fm.fileExists(atPath: u.appendingPathComponent("run.sh").path) }
        // inside an installed app the sidecar ships in Resources
        if let r = Bundle.main.resourceURL?.appendingPathComponent("LayaDirector"), ok(r), !isDevCheckout() {
            return r
        }
        if let e = ProcessInfo.processInfo.environment["MACATTACK_LAYA_DIR"] {
            let u = URL(fileURLWithPath: e)
            if ok(u) { return u }
        }
        if let p = Bundle.main.object(forInfoDictionaryKey: "MacAttackLayaDirectory") as? String {
            let u = URL(fileURLWithPath: p)
            if ok(u) { return u }
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            let u = dir.appendingPathComponent("LayaDirector")
            if ok(u) { return u }
            dir.deleteLastPathComponent()
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("LayaDirector")
        return ok(cwd) ? cwd : nil
    }
}
