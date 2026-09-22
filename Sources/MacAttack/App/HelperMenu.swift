import MacAttackCore
import MacAttackKit
import SwiftUI

/// The menu-bar UI of the screensaver helper. Makes it obvious when the camera is on and why.
struct HelperMenu: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Text(app.helperClientActive ? "👀 Screensaver is watching" : "💤 Idle — camera off")
        Text(app.helperClientActive ? "Camera: \(app.camera.status.label)" : "Camera: off")
        Text("Laya: \(app.coordinator.health.label)")
        Divider()
        Text("Serving anonymous person boxes on 127.0.0.1:8778.")
        Text("No video leaves this Mac. Nothing is recorded.")
        Divider()
        Button("Open Mac Attack game…") {
            let url = Bundle.main.bundleURL
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
        Button("Stop Helper (until next login)") {
            app.helperAgent.stopNow()
            NSApp.terminate(nil)
        }
    }
}
