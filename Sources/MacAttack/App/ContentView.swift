import MacAttackCore
import MacAttackKit
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
        HeaderBar()
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    if app.mode == .camera && app.camera.status == .running {
                        CameraPreviewView(session: app.camera.session)
                    } else if app.mode == .camera {
                        Color.black
                    }
                    GameCanvasView(scene: app.scene, debug: app.debug)
                    CameraStatusOverlay()
                }
                StatusBar()
            }
            if app.debug {
                Divider()
                DebugPanel().frame(width: 340)
            }
        }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HeaderBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 16) {
            Text("MAC ATTACK")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.pink, .orange, .yellow], startPoint: .leading, endPoint: .trailing))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            Picker("Mode", selection: Binding(get: { app.mode }, set: { app.setMode($0) })) {
                ForEach(InputMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .labelsHidden()
            Toggle("Chaos", isOn: $app.chaos).toggleStyle(.switch).fixedSize()
            Toggle("Sound", isOn: $app.sound).toggleStyle(.switch).fixedSize()
            Toggle("Debug Mode", isOn: $app.debug).toggleStyle(.checkbox).fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct StatusBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let hud = app.engine.hud
        let c = app.coordinator
        HStack(spacing: 18) {
            stat("Humans", "\(hud.people.count)")
            stat("Director", c.useLaya && c.health == .ready ? "Laya" : "Local Fallback")
            stat("Laya", c.health.label, color: c.health == .ready ? .green : .orange)
            stat("Events", "\(hud.eventCount)")
            stat("Combo", "\(hud.combo)")
            stat("Mode", app.chaos ? "CHAOS" : "NORMAL", color: app.chaos ? .red : .primary)
            Spacer()
            Text(hud.phase.rawValue).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func stat(_ k: String, _ v: String, color: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(k + ":").foregroundStyle(.secondary)
            Text(v).fontWeight(.semibold).foregroundStyle(color)
        }
        .lineLimit(1)
        .fixedSize()
        .font(.system(.callout, design: .rounded))
    }
}

struct CameraStatusOverlay: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.mode == .camera {
            switch app.camera.status {
            case .denied, .restricted:
                card("Camera access is off",
                     "Mac Attack needs the camera to see humans. Nothing is recorded or uploaded.\nSystem Settings › Privacy & Security › Camera › Mac Attack",
                     primary: ("Open Privacy Settings", {
                         NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                     }))
            case .unavailable(let why):
                card("Camera unavailable", why, primary: ("Retry", { app.camera.start() }))
            case .requesting:
                card("Waiting for camera permission…", "Approve the macOS prompt to let Mac Attack watch for humans (locally).", primary: nil)
            case .stopped:
                card("Camera stopped", "Capture is off.", primary: ("Start Camera", { app.camera.start() }))
            default:
                EmptyView()
            }
        }
    }

    private func card(_ title: String, _ body: String, primary: (String, () -> Void)?) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.title2.bold())
            Text(body).multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack {
                if let primary { Button(primary.0, action: primary.1).buttonStyle(.borderedProminent) }
                Button("Use Simulation Mode") { app.setMode(.simulation) }
            }
        }
        .padding(24)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
