@preconcurrency import AVFoundation
import SwiftUI

/// Live mirrored camera preview. Display only; nothing is captured from this layer.
public struct CameraPreviewView: NSViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) { self.session = session }

    public func makeNSView(context: Context) -> PreviewNSView {
        let v = PreviewNSView()
        v.previewLayer.session = session
        return v
    }

    public func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session { nsView.previewLayer.session = session }
        nsView.applyMirroring()
    }

    public final class PreviewNSView: NSView {
        public let previewLayer = AVCaptureVideoPreviewLayer()

        public override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        public required init?(coder: NSCoder) { fatalError() }

        public override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
            applyMirroring()
        }

        /// Mirror like a mirror, so the detector (which flips x) and the preview agree.
        public func applyMirroring() {
            guard let c = previewLayer.connection, c.isVideoMirroringSupported else { return }
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
    }
}
