import MacAttackCore
import MacAttackKit
import SwiftUI

/// Phase 1 developer panel: live facts, Laya's last decision (with probabilities), the decision
/// log, and manual controls.
struct DebugPanel: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DevControls()
                if app.mode == .simulation { SimulationControls() }
                ScreensaverSection()
                CameraSection()
                PeopleSection()
                LayaSection()
                DecisionLogSection()
            }
            .padding(14)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

struct DevControls: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Section(title: "DEVELOPER CONTROLS") {
            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 6) {
                Button("Spawn Human") { app.spawnHumans(1) }
                Button("Spawn 2 Humans") { app.spawnHumans(2) }
                Button("Clear Humans") { app.clearHumans() }
                Button(app.chaos ? "Calm Mode" : "Chaos Mode") { app.chaos.toggle() }
                Button("Trigger Laya") { app.triggerLaya() }
                Button("Bubble Attack") { app.trigger(.bubbleBlast) }
                Button("Confetti") { app.trigger(.confettiExplosion) }
                Button("Duck Rain") { app.trigger(.duckRain) }
                Menu("More Effects") {
                    ForEach(EffectKind.allCases, id: \.self) { e in
                        Button("\(e.emoji) \(e.title)") { app.trigger(e) }
                    }
                }
                Button("Reset") { app.resetGame() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

struct SimulationControls: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Section(title: "SIMULATION") {
            Toggle("Autopilot (random humans come & go)", isOn: $app.autopilot)
            Button("Change Movement (all)") { app.cycleMovement() }.controlSize(.small)
            if app.simPeople.isEmpty { Text("No simulated humans.").foregroundStyle(.secondary) }
            ForEach(app.simPeople) { p in
                HStack(spacing: 4) {
                    Text(p.id).frame(width: 70, alignment: .leading)
                    Picker("", selection: Binding(get: { p.behavior }, set: { app.setBehavior(p.id, $0) })) {
                        ForEach(SimulationWorld.Behavior.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 96)
                    Button("◀") { app.nudge(p.id, -0.08) }
                    Button("▶") { app.nudge(p.id, 0.08) }
                    Button("✕") { app.removeSim(p.id) }
                }
                .controlSize(.small)
            }
        }
    }
}

struct CameraSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Section(title: "CAMERA / PERCEPTION") {
            Text("Camera: \(app.mode == .camera ? app.camera.status.label : "OFF (simulation)")")
            if let n = app.camera.deviceName { Text("Device: \(n) \(Int(app.camera.dimensions.width))×\(Int(app.camera.dimensions.height))") }
            if app.mode == .camera {
                Text(String(format: "Detection: %.1f fps, %.0f ms, raw boxes %d", app.detectionFPS, app.detectionMs, app.rawCount))
                Toggle("Upper body only (desk mode)", isOn: $app.upperBodyOnly)
                Toggle("Face-box assist (boxes only, no recognition)", isOn: $app.faceAssist)
                Button(app.camera.status == .running ? "Stop Camera" : "Start Camera") { app.toggleCamera() }.controlSize(.small)
            }
            Toggle("Show detection boxes", isOn: $app.showBoxes)
            Text(String(format: "Render: %.0f fps, nodes %d", app.scene.fps, app.scene.liveNodeCount))
                .foregroundStyle(.secondary)
            Text("Privacy: anonymous boxes only · no face recognition · no frames stored · Laya sees JSON only")
                .foregroundStyle(.green).font(.system(size: 10))
        }
    }
}

struct PeopleSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let hud = app.engine.hud
        Section(title: "PEOPLE DETECTED: \(hud.people.count)") {
            ForEach(hud.people) { p in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(p.character.emoji) Person #\(p.number)  (\(p.id))").fontWeight(.semibold)
                    Text("Position: \(pct(p.box.midX)), \(pct(p.box.midY))")
                    Text("Movement: \(p.movement.rawValue.uppercased())")
                    Text(String(format: "Velocity: %.2f   Dwell: %.1fs   Hits: %d", p.speed, p.lifetime, p.timesHit))
                }
                .padding(.bottom, 4)
            }
        }
    }
}

struct LayaSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var c = app.coordinator
        let hud = app.engine.hud
        Section(title: "LAYA") {
            Text("Status: \(c.health.label)\(c.layaDevice.map { " on \($0)" } ?? "")")
            if case .unavailable(let why) = c.health { Text(why).foregroundStyle(.orange) }
            Text("Director: \(c.useLaya && c.health == .ready ? "Laya" : "Local Fallback")")
            Text("Decisions: Laya \(c.layaDecisions) · Fallback \(c.fallbackDecisions)")
            if let l = c.lastLatencyMs { Text(String(format: "Last Laya latency: %.0f ms", l)) }
            switch app.layaSetup.state {
            case .missing:
                Text("Laya is not set up on this Mac — the local fallback director is running.")
                    .foregroundStyle(.orange)
                Button("Set Up Laya (~2.5 GB download)") { app.runLayaSetup() }.controlSize(.small)
            case .running:
                Text("Setting up Laya… \(app.layaSetup.lastLine)").foregroundStyle(.secondary)
            case .failed(let why):
                Text(why).foregroundStyle(.red)
                Button("Retry Laya Setup") { app.runLayaSetup() }.controlSize(.small)
            case .ready, .unknown:
                EmptyView()
            }
            Toggle("Use Laya", isOn: $c.useLaya)
            Toggle("Simulate slow Laya (+3 s)", isOn: $c.simulateSlowLaya)
            Text("Phase: \(hud.phase.rawValue)\(hud.awaiting ? " (asking…)" : "")")
            if let d = hud.lastDecision {
                Divider()
                Text("Decision: \(d.holdBack ? "HOLD BACK" : d.effect.rawValue.uppercased())").fontWeight(.bold)
                Text("Target: \(d.target.description)")
                Text(String(format: "Intensity: %.2f", d.intensity))
                Text("Reaction: \(d.reaction.rawValue.uppercased())   Mood: \(d.mood.rawValue)")
                Text("Source: \(d.source.rawValue)")
                ForEach(d.rationale.keys.sorted(), id: \.self) { k in
                    Text("\(k): " + d.rationale[k]!.map { "\($0.0) \(pct($0.1))" }.joined(separator: " · "))
                        .foregroundStyle(.secondary).font(.system(size: 10, design: .monospaced))
                }
                if let s = d.situation {
                    Text("Laya read: \"\(s)\"").foregroundStyle(.secondary).font(.system(size: 10))
                }
            }
        }
    }
}

struct DecisionLogSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Section(title: "DECISION LOG") {
            ForEach(app.coordinator.log.prefix(20)) { e in
                let d = e.decision
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%6.1fs ", e.time) + "[\(d.source == .laya ? "LAYA" : "LOCAL")] \(e.trigger.rawValue)")
                    Text("  → " + (d.holdBack ? "hold back" : "\(d.effect.rawValue) @ \(d.target.key) i=\(String(format: "%.2f", d.intensity)) \(d.reaction.rawValue)"))
                    if let n = e.note { Text("  \(n)").foregroundStyle(.orange) }
                }
                .font(.system(size: 10, design: .monospaced))
            }
        }
    }
}


/// Screensaver setup. The .saver renders the game, but macOS never grants it camera access, so a
/// helper process (this app in --helper mode, started by launchd) owns the camera and publishes
/// anonymous person boxes on 127.0.0.1:8778.
struct ScreensaverSection: View {
    @Environment(AppState.self) private var app
    var body: some View {
        Section(title: "SCREENSAVER HELPER") {
            Text(app.helperInstalled ? (app.helperRunning ? "Helper: installed & running" : "Helper: installed (not running)")
                                     : "Helper: not installed")
                .foregroundStyle(app.helperInstalled && app.helperRunning ? .green : .orange)
            Text("The screensaver needs this helper for the camera. It keeps the camera OFF until the screensaver is actually on screen.")
                .foregroundStyle(.secondary).font(.system(size: 10))
            HStack {
                Button(app.helperInstalled ? "Remove Helper" : "Install Helper (runs at login)") {
                    app.toggleHelperAgent()
                }
                Button("Refresh") { app.refreshHelperStatus() }
            }
            .controlSize(.small)
            if let e = app.helperAgent.lastError { Text(e).foregroundStyle(.red).font(.system(size: 10)) }
            Text("Then pick Mac Attack in System Settings › Screen Saver.")
                .foregroundStyle(.secondary).font(.system(size: 10))
        }
        .onAppear { app.refreshHelperStatus() }
    }
}
