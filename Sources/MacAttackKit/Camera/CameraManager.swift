@preconcurrency import AVFoundation
import CoreMedia
import Observation

/// Owns the capture session. Frames are handed to `onFrame` on a private queue and never stored:
/// no recording, no file output, no persistence.
@MainActor
@Observable
public final class CameraManager: NSObject {
    public enum Status: Equatable {
        case idle, requesting, denied, restricted, unavailable(String), running, stopped

        public var label: String {
            switch self {
            case .idle: "IDLE"
            case .requesting: "REQUESTING PERMISSION"
            case .denied: "PERMISSION DENIED"
            case .restricted: "RESTRICTED"
            case .unavailable: "UNAVAILABLE"
            case .running: "ACTIVE"
            case .stopped: "STOPPED"
            }
        }
    }

    public private(set) var status: Status = .idle
    public private(set) var deviceName: String?
    public private(set) var dimensions = CGSize(width: 1280, height: 720)

    @ObservationIgnored public let session = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "macattack.camera.session")
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "macattack.camera.video", qos: .userInitiated)
    @ObservationIgnored private let frameSink = FrameSink()
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var wanted = false

    /// Called on the video queue for every frame. Must not retain the buffer.
    public var onFrame: (@Sendable (CVPixelBuffer) -> Void)? {
        get { frameSink.handler }
        set { frameSink.handler = newValue }
    }

    public override init() {
        super.init()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDisconnect() }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] n in
            let err = (n.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "runtime error"
            MainActor.assumeIsolated { self?.status = .unavailable(err) }
        })
    }

    public func start() {
        wanted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            status = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted, self.wanted { self.startSession() } else if !granted { self.status = .denied }
                }
            }
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        @unknown default:
            status = .unavailable("unknown authorization state")
        }
    }

    public func stop() {
        wanted = false
        let s = session
        sessionQueue.async { if s.isRunning { s.stopRunning() } }
        if status == .running || status == .requesting { status = .stopped }
    }

    /// Synchronous stop for app termination.
    public func stopNow() {
        wanted = false
        let s = session
        sessionQueue.sync { if s.isRunning { s.stopRunning() } }
        status = .stopped
    }

    private func startSession() {
        let s = session
        let sink = frameSink
        let q = videoQueue
        let needsConfig = !configured
        sessionQueue.async { [weak self] in
            var result: Result<(String, CGSize)?, CameraError> = .success(nil)
            if needsConfig { result = Self.configure(s, sink: sink, queue: q) }
            if case .failure(let e) = result {
                Task { @MainActor in self?.status = .unavailable(e.message) }
                return
            }
            if !s.isRunning { s.startRunning() }
            let running = s.isRunning
            Task { @MainActor in
                guard let self else { return }
                if case .success(let info?) = result {
                    self.configured = true
                    self.deviceName = info.0
                    self.dimensions = info.1
                }
                guard self.wanted else { s.stopRunning(); return }
                self.status = running ? .running : .unavailable("session failed to start")
            }
        }
    }

    public struct CameraError: Error { let message: String }

    nonisolated private static func configure(_ s: AVCaptureSession, sink: FrameSink, queue: DispatchQueue) -> Result<(String, CGSize)?, CameraError> {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                                         mediaType: .video, position: .unspecified)
        guard let device = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? discovery.devices.first ?? AVCaptureDevice.default(for: .video) else {
            return .failure(CameraError(message: "no camera found"))
        }
        s.beginConfiguration()
        defer { s.commitConfiguration() }
        s.sessionPreset = s.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard s.canAddInput(input) else { return .failure(CameraError(message: "cannot add camera input")) }
            s.addInput(input)
        } catch {
            return .failure(CameraError(message: error.localizedDescription))
        }
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        out.setSampleBufferDelegate(sink, queue: queue)
        guard s.canAddOutput(out) else { return .failure(CameraError(message: "cannot add video output")) }
        s.addOutput(out)
        // ~30 fps if the device supports it
        if (try? device.lockForConfiguration()) != nil {
            let fps30 = CMTime(value: 1, timescale: 30)
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameDuration <= fps30 && fps30 <= $0.maxFrameDuration }) {
                device.activeVideoMinFrameDuration = fps30
            }
            device.unlockForConfiguration()
        }
        let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return .success((device.localizedName, CGSize(width: Int(d.width), height: Int(d.height))))
    }

    private func handleDisconnect() {
        if status == .running { status = .unavailable("camera disconnected") }
    }
}

/// Sample-buffer delegate living off the main actor.
public final class FrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public var handler: (@Sendable (CVPixelBuffer) -> Void)?

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler?(pb)
    }
}
