import AppKit
import MacAttackCore
import MacAttackKit
import os
import ScreenSaver
import SpriteKit

/// The Mac Attack screensaver.
///
/// It runs the same game engine and SpriteKit renderer as the app. What it cannot do is open the
/// camera: macOS attributes a screensaver's camera request to Apple's `legacyScreenSaver` host,
/// which has no camera permission, so the request is refused without ever prompting. Instead the
/// Mac Attack helper app owns the camera and publishes anonymous person boxes on 127.0.0.1; this
/// view renders the cartoon world from those boxes and asks Laya (also local) what should happen.
@objc(MacAttackSaverView)
public final class MacAttackSaverView: ScreenSaverView {
    private let log = Logger(subsystem: "local.macattack.saver", category: "saver")

    /// macOS creates one view per display; only the first runs the game, the rest show ambience.
    private static var primaryExists = false
    private let isPrimary: Bool

    private var skView: SKView?
    private var scene: GameScene?
    private var engine: GameEngine?
    private var coordinator: DirectorCoordinator?
    private var tracks: TracksClient?
    private var started = false

    public override init?(frame: NSRect, isPreview: Bool) {
        isPrimary = !Self.primaryExists
        if isPrimary { Self.primaryExists = true }
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(hostWillStop),
            name: NSNotification.Name("com.apple.screensaver.willstop"), object: nil)
    }

    required init?(coder: NSCoder) {
        isPrimary = !Self.primaryExists
        if isPrimary { Self.primaryExists = true }
        super.init(coder: coder)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Lifecycle

    public override func startAnimation() {
        super.startAnimation()
        guard !started else { return }
        started = true
        buildGame()
    }

    public override func stopAnimation() {
        teardown()
        super.stopAnimation()
    }

    @objc private func hostWillStop() {
        teardown()
    }

    public override func animateOneFrame() {
        // SpriteKit drives its own 60 fps loop; nothing to do per frame.
    }

    private func buildGame() {
        let coordinator = DirectorCoordinator()
        let engine = GameEngine(coordinator: coordinator)
        let scene = GameScene(engine: engine)
        scene.size = bounds.size
        scene.cameraBackdrop = false        // no camera feed here: cartoon world only
        scene.soundEnabled = false          // a screensaver should stay quiet
        scene.contentAspect = nil

        let view = SKView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.presentScene(scene)
        addSubview(view)

        self.coordinator = coordinator
        self.engine = engine
        self.scene = scene
        skView = view

        // Secondary displays and the System Settings thumbnail: ambience only, no camera, no Laya.
        guard isPrimary, !isPreview else { return }

        coordinator.start()
        let client = TracksClient()
        client.onTracks = { [weak self] t in
            guard let self else { return }
            self.engine?.updatePeople(t)
            if let a = self.tracks?.videoAspect { self.scene?.contentAspect = a }
            self.scene?.statusMessage = self.tracks?.hint
        }
        client.start()
        tracks = client
        log.notice("Mac Attack saver started (primary display)")
    }

    private func teardown() {
        guard started else { return }
        tracks?.stop()
        tracks = nil
        coordinator?.stop()
        coordinator = nil
        skView?.presentScene(nil)
        skView?.removeFromSuperview()
        skView = nil
        scene = nil
        engine = nil
        started = false
        if isPrimary { Self.primaryExists = false }
    }

    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
