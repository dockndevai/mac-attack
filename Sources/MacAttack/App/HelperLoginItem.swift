import Foundation
import Observation

/// Installs the Mac Attack helper as a per-user launchd agent.
///
/// The screensaver cannot start the helper itself: anything it spawns inherits the screensaver's
/// sandbox and is refused camera access (and `open` is blocked outright). launchd starts the helper
/// in the normal user session, where the camera permission granted to Mac Attack applies.
/// Opt-in only — the user turns this on, and the helper keeps the camera off until the screensaver
/// actually asks for people.
@MainActor
@Observable
final class HelperLoginItem {
    static let label = "local.macattack.helper"

    private(set) var lastError: String?

    var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    var isRunning: Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "gui/\(getuid())/\(Self.label)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func install() {
        lastError = nil
        let exe = Bundle.main.executableURL?.path ?? ""
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [exe, "--helper"],
            "RunAtLoad": true,
            // Always keep it alive: quitting the game app must not silently take the
            // screensaver's camera helper down with it.
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardErrorPath": FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/MacAttack/helper.log").path,
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
            launchctl(["bootout", "gui/\(getuid())/\(Self.label)"])      // ignore failure: may not be loaded
            if launchctl(["bootstrap", "gui/\(getuid())", plistURL.path]) != 0 {
                lastError = "launchctl bootstrap failed"
            }
        } catch {
            lastError = "\(error)"
        }
    }

    /// Stop the helper for this session (it comes back at next login, or on Install again).
    func stopNow() {
        launchctl(["bootout", "gui/\(getuid())/\(Self.label)"])
    }

    func uninstall() {
        launchctl(["bootout", "gui/\(getuid())/\(Self.label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { lastError = "\(error)"; return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
