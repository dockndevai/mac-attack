import CoreVideo
import Foundation
import MacAttackCore
import QuartzCore
import Vision

/// Local human-body detection with Apple Vision. Only body rectangles come out: no faces,
/// no landmarks, no recognition. Throttled to ~10 fps; frames are dropped, never queued or kept.
public final class VisionPersonDetector: @unchecked Sendable {
    public init() {}

    public struct Result: Sendable {
        public var rects: [NormRect]
        public var processingMs: Double
    }

    public var interval: Double = 0.1
    public var upperBodyOnly = true
    public var minConfidence: Float = 0.35
    /// Also use Vision face *rectangles* (bounding boxes only: no landmarks, no recognition) so a
    /// person sitting close to the Mac, with little body visible, still counts as present.
    public var faceAssist = true
    public var onResult: (@Sendable (Result) -> Void)?

    private var last: CFTimeInterval = 0
    private let request = VNDetectHumanRectanglesRequest()
    private let faceRequest = VNDetectFaceRectanglesRequest()

    /// Call on the camera's video queue.
    public func process(_ pixelBuffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        guard now - last >= interval else { return }
        last = now
        request.upperBodyOnly = upperBodyOnly
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform(faceAssist ? [request, faceRequest] : [request])
        } catch {
            return
        }
        // Vision boxes are normalized, origin bottom-left, un-mirrored: mirror x (the preview is
        // mirrored) and flip y to top-left origin.
        func convert(_ b: CGRect) -> NormRect { NormRect(x: 1 - b.maxX, y: 1 - b.maxY, width: b.width, height: b.height) }
        var rects: [NormRect] = (request.results ?? []).compactMap { obs in
            obs.confidence >= minConfidence ? convert(obs.boundingBox) : nil
        }
        if faceAssist {
            for f in faceRequest.results ?? [] where f.confidence >= 0.5 {
                let face = convert(f.boundingBox)
                // already covered by a body box? skip
                if rects.contains(where: { face.midX > $0.x && face.midX < $0.x + $0.width && face.midY > $0.y && face.midY < $0.y + $0.height }) { continue }
                // approximate head-and-shoulders box around the face
                let w = min(1, face.width * 2.4), h = min(1, face.height * 2.6)
                rects.append(NormRect(x: max(0, face.midX - w / 2), y: max(0, face.y - face.height * 0.3), width: w, height: h))
            }
        }
        onResult?(Result(rects: rects, processingMs: (CACurrentMediaTime() - now) * 1000))
    }
}
