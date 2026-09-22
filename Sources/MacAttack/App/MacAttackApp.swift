import AppKit
import MacAttackKit
import SwiftUI

@main
struct MacAttackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let app = AppState.shared

    var body: some Scene {
        WindowGroup("Mac Attack") {
            RootView()
                .environment(app)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)

        // Helper mode: menu-bar only, owns the camera for the screensaver.
        MenuBarExtra("Mac Attack", systemImage: "eye.circle", isInserted: .constant(app.isHelper)) {
            HelperMenu().environment(app)
        }
    }
}

/// In helper mode there is no game window: the window group's window closes itself immediately.
struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.isHelper {
            Color.clear.frame(width: 1, height: 1)
                .onAppear { for w in NSApp.windows where w.isVisible && !(w is NSPanel) { w.close() } }
        } else {
            ContentView().frame(minWidth: 1040, minHeight: 640)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let helper = CommandLine.arguments.contains("--helper")
        NSApp.setActivationPolicy(helper ? .accessory : .regular)
        if !helper && !CommandLine.arguments.contains("--no-activate") { NSApp.activate(ignoringOtherApps: true) }
        MainActor.assumeIsolated { AppState.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !CommandLine.arguments.contains("--helper")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Camera capture must stop and the Laya sidecar must not outlive us.
        MainActor.assumeIsolated { AppState.shared.shutdown() }
    }
}
