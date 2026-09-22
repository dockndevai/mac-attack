import Foundation

/// Fake humans for testing the whole game without a camera. Produces the same `TrackSnapshot`s
/// the camera tracker does.
public final class SimulationWorld {
    public enum Behavior: String, CaseIterable, Sendable {
        case wander, stationary, left, right, zigzag, frantic
    }

    public struct SimPerson: Identifiable, Sendable {
        public let id: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var vx: Double
        public var vy: Double
        public var behavior: Behavior
        public var born: Double
        public var phase: Double
    }

    public private(set) var people: [SimPerson] = []
    public private(set) var time = 0.0
    public var autopilot = false
    public var maxPeople = 4
    private var nextNumber = 1
    private var autopilotTimer = 2.0

    public init() {}

    @discardableResult
    public func spawn(behavior: Behavior? = nil, x: Double? = nil) -> String {
        let id = "person-\(nextNumber)"
        nextNumber += 1
        let h = Double.random(in: 0.42...0.62)
        people.append(SimPerson(id: id, x: x ?? Double.random(in: 0.15...0.85), y: Double.random(in: 0.5...0.62),
                                width: h * 0.45, height: h, vx: 0, vy: 0,
                                behavior: behavior ?? Behavior.allCases.randomElement()!, born: time,
                                phase: Double.random(in: 0...6.28)))
        return id
    }

    public func remove(_ id: String) { people.removeAll { $0.id == id } }
    public func removeLast() { if !people.isEmpty { people.removeLast() } }
    public func clear() { people.removeAll() }

    public func setBehavior(_ id: String, _ b: Behavior) {
        if let i = people.firstIndex(where: { $0.id == id }) { people[i].behavior = b }
    }

    public func cycleBehaviors() {
        for i in people.indices {
            let all = Behavior.allCases
            people[i].behavior = all[(all.firstIndex(of: people[i].behavior)! + 1) % all.count]
        }
    }

    public func nudge(_ id: String, dx: Double) {
        if let i = people.firstIndex(where: { $0.id == id }) { people[i].x = min(0.9, max(0.1, people[i].x + dx)) }
    }

    public func tick(_ dt: Double) -> [TrackSnapshot] {
        time += dt
        if autopilot { runAutopilot(dt) }
        for i in people.indices {
            var p = people[i]
            p.phase += dt
            let target: (Double, Double)
            switch p.behavior {
            case .stationary: target = (0, 0)
            case .left: target = (-0.18, 0)
            case .right: target = (0.18, 0)
            case .wander: target = (sin(p.phase * 0.7) * 0.12, cos(p.phase * 0.5) * 0.02)
            case .zigzag: target = (sin(p.phase * 2.2) * 0.3, 0)
            case .frantic: target = (sin(p.phase * 5.1) * 0.7, cos(p.phase * 3.7) * 0.15)
            }
            p.vx += (target.0 - p.vx) * min(1, dt * 3)
            p.vy += (target.1 - p.vy) * min(1, dt * 3)
            p.x += p.vx * dt
            p.y += p.vy * dt
            let halfW = p.width / 2
            if p.x < halfW + 0.02 { p.x = halfW + 0.02; p.vx = abs(p.vx); if p.behavior == .left { p.behavior = .right } }
            if p.x > 0.98 - halfW { p.x = 0.98 - halfW; p.vx = -abs(p.vx); if p.behavior == .right { p.behavior = .left } }
            p.y = min(0.7, max(0.35, p.y))
            people[i] = p
        }
        return people.map { p in
            let speed = hypot(p.vx, p.vy)
            let movement: MovementState = speed < 0.06 ? .stationary
                : abs(p.vx) >= abs(p.vy) ? (p.vx < 0 ? .left : .right) : (p.vy < 0 ? .up : .down)
            return TrackSnapshot(id: p.id, box: .centered(x: p.x, y: p.y, width: p.width, height: p.height),
                                 vx: p.vx, vy: p.vy, movement: movement, dwell: time - p.born)
        }
    }

    private func runAutopilot(_ dt: Double) {
        autopilotTimer -= dt
        guard autopilotTimer <= 0 else { return }
        autopilotTimer = Double.random(in: 3...12)
        let r = Double.random(in: 0..<1)
        if people.isEmpty || (people.count < maxPeople && r < 0.45) {
            spawn()
        } else if r < 0.75 || people.count >= maxPeople {
            if let victim = people.randomElement() { remove(victim.id) }
            if people.isEmpty { autopilotTimer = Double.random(in: 5...15) }  // exercise idle mode too
        } else {
            cycleBehaviors()
        }
    }
}
