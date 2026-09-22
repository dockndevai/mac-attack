import Foundation

/// Turns per-frame anonymous body rectangles into stable tracks with motion.
///
/// Matching is greedy by IoU (then centroid distance), boxes are EMA-smoothed, and a track must be
/// seen `minHits` times before it is reported (kills single-frame false positives) and is dropped
/// after `maxMissing` seconds unseen (survives brief detection dropouts). Ids are per-session
/// counters; nothing about a person's appearance is kept.
public final class PersonTracker {
    public struct Config {
        public var minHits = 3
        public var maxMissing: Double = 1.2
        public var smoothing: Double = 0.45       // weight of the new observation
        public var minIoU: Double = 0.05
        public var maxCentroidDistance: Double = 0.25
        public var stationarySpeed: Double = 0.06  // normalized widths per second
        public var depthRate: Double = 0.35        // relative area change per second
        public init() {}
    }

    struct Track {
        var number: Int?          // assigned on confirmation
        var box: NormRect
        var vx = 0.0, vy = 0.0, areaRate = 0.0
        var hits = 1
        var firstSeen: Double
        var lastSeen: Double
        var lastUpdate: Double
    }

    public var config: Config
    private var tracks: [Track] = []
    private var nextNumber = 1

    public init(config: Config = Config()) { self.config = config }

    public func reset() {
        tracks.removeAll()
    }

    /// - Returns: confirmed tracks after incorporating this frame's detections.
    @discardableResult
    public func update(detections: [NormRect], at t: Double) -> [TrackSnapshot] {
        var unmatched = Array(detections.indices)
        var pairs: [(Int, Int, Double)] = []
        for (ti, tr) in tracks.enumerated() {
            for di in detections.indices {
                let d = detections[di]
                let iou = tr.box.iou(d)
                let dist = hypot(tr.box.midX - d.midX, tr.box.midY - d.midY)
                guard iou >= config.minIoU || dist <= config.maxCentroidDistance else { continue }
                pairs.append((ti, di, iou - dist))   // higher is better
            }
        }
        pairs.sort { $0.2 > $1.2 }
        var usedT = Set<Int>(), usedD = Set<Int>()
        for (ti, di, _) in pairs where !usedT.contains(ti) && !usedD.contains(di) {
            usedT.insert(ti); usedD.insert(di)
            integrate(&tracks[ti], detections[di], at: t)
        }
        unmatched.removeAll { usedD.contains($0) }
        for di in unmatched {
            tracks.append(Track(box: detections[di], firstSeen: t, lastSeen: t, lastUpdate: t))
        }
        // unconfirmed tracks die fast; confirmed ones get the grace period
        tracks.removeAll { tr in
            let limit = tr.number == nil ? min(0.4, config.maxMissing) : config.maxMissing
            return t - tr.lastSeen > limit
        }
        for i in tracks.indices where tracks[i].number == nil && tracks[i].hits >= config.minHits {
            tracks[i].number = nextNumber
            nextNumber += 1
        }
        // decay velocity for tracks we did not see this frame
        for i in tracks.indices where tracks[i].lastSeen < t {
            tracks[i].vx *= 0.8; tracks[i].vy *= 0.8; tracks[i].areaRate *= 0.8
        }
        return snapshots(at: t)
    }

    public func snapshots(at t: Double) -> [TrackSnapshot] {
        tracks.compactMap { tr in
            guard let n = tr.number else { return nil }
            return TrackSnapshot(id: "person-\(n)", box: tr.box, vx: tr.vx, vy: tr.vy,
                                 movement: movement(tr), dwell: t - tr.firstSeen)
        }
    }

    private func integrate(_ tr: inout Track, _ d: NormRect, at t: Double) {
        let dt = max(1e-3, t - tr.lastUpdate)
        let a = config.smoothing
        let nb = tr.box.lerp(to: d, a)
        let ivx = (nb.midX - tr.box.midX) / dt
        let ivy = (nb.midY - tr.box.midY) / dt
        let iar = tr.box.area > 0 ? (nb.area - tr.box.area) / tr.box.area / dt : 0
        tr.vx = tr.vx * 0.6 + ivx * 0.4
        tr.vy = tr.vy * 0.6 + ivy * 0.4
        tr.areaRate = tr.areaRate * 0.6 + iar * 0.4
        tr.box = nb
        tr.hits += 1
        tr.lastSeen = t
        tr.lastUpdate = t
    }

    private func movement(_ tr: Track) -> MovementState {
        let speed = hypot(tr.vx, tr.vy)
        if abs(tr.areaRate) > config.depthRate && speed < config.stationarySpeed * 3 {
            return tr.areaRate > 0 ? .approaching : .retreating
        }
        if speed < config.stationarySpeed { return .stationary }
        if abs(tr.vx) >= abs(tr.vy) { return tr.vx < 0 ? .left : .right }
        return tr.vy < 0 ? .up : .down
    }
}
