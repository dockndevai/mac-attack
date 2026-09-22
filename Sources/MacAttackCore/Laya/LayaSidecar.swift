import Foundation

/// Optionally launches `LayaDirector/run.sh` as a child process and stops it on quit.
/// The sidecar also watches our pid and exits if we die, so it can never outlive the game.
public final class LayaSidecar: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case notStarted, running(Int32), exited(Int32), missing(String)
    }

    public private(set) var state: State = .notStarted
    private var process: Process?
    public let directory: URL?
    public let logURL: URL

    public let port: Int

    public init(directory: URL?, port: Int = 8777) {
        self.directory = directory
        self.port = port
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacAttack")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        logURL = logs.appendingPathComponent(port == 8777 ? "laya-sidecar.log" : "laya-sidecar-\(port).log")
    }

    /// Launch unless something already answers on the port.
    public func launchIfNeeded(adapter: LayaAdapter) async {
        if (try? await adapter.status()) != nil { return }
        launch()
    }

    public var isRunning: Bool { process?.isRunning == true }

    public func launch() {
        guard !isRunning else { return }
        NSLog("MacAttack: launching Laya sidecar")
        process = nil
        guard let dir = directory else { state = .missing("LayaDirector path unknown"); return }
        let script = dir.appendingPathComponent("run.sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            state = .missing(script.path); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path, "--port", String(port), "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = env["HF_HUB_OFFLINE"] ?? "1"   // checkpoints are cached; never phone home
        p.environment = env
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: logURL) {
            p.standardOutput = h
            p.standardError = h
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async { self?.state = .exited(code) }
        }
        do {
            try p.run()
            process = p
            state = .running(p.processIdentifier)
        } catch {
            state = .missing("\(error)")
        }
    }

    public func terminate() {
        guard let p = process else { return }
        if p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(1.5)
            while p.isRunning && Date() < deadline { usleep(50_000) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        process = nil
    }
}
