import Foundation
import MacAttackCore
import Observation

/// Runs the one-time Laya setup (virtualenv + checkpoint) for people who installed the app from a
/// package and never touch a terminal. Everything goes to ~/Library/Application Support/MacAttack.
@MainActor
@Observable
final class LayaSetup {
    enum State: Equatable {
        case unknown, ready, missing, running, failed(String)
    }

    private(set) var state: State = .unknown
    private(set) var lastLine = ""
    @ObservationIgnored private var process: Process?

    var venvURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacAttack/laya-venv")
    }

    var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MacAttack/laya-setup.log")
    }

    func refresh(layaDirectory: URL?) {
        if case .running = state { return }
        let fm = FileManager.default
        let devVenv = layaDirectory?.appendingPathComponent(".venv/bin/python").path
        let installed = fm.isExecutableFile(atPath: venvURL.appendingPathComponent("bin/python").path)
        let dev = devVenv.map { fm.isExecutableFile(atPath: $0) } ?? false
        state = (installed || dev) ? .ready : .missing
    }

    func run(layaDirectory: URL?) {
        guard case .running = state else { return start(layaDirectory) }
    }

    private func start(_ layaDirectory: URL?) {
        guard let dir = layaDirectory else { state = .failed("Laya files not found"); return }
        let script = dir.appendingPathComponent("setup_laya.sh")
        let fallback = dir.deletingLastPathComponent().appendingPathComponent("scripts/setup_laya.sh")
        let path = FileManager.default.isExecutableFile(atPath: script.path) ? script : fallback
        guard FileManager.default.isExecutableFile(atPath: path.path) else {
            state = .failed("setup script missing"); return
        }
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [path.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let log = logURL
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            if let fh = try? FileHandle(forWritingTo: log) {
                fh.seekToEndOfFile(); fh.write(d); try? fh.close()
            }
            let line = s.split(separator: "\n").last.map(String.init) ?? ""
            Task { @MainActor in self?.lastLine = line }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor in
                self?.state = code == 0 ? .ready : .failed("setup failed (exit \(code)) — see \(self?.logURL.path ?? "")")
                self?.process = nil
            }
        }
        do {
            try p.run()
            process = p
            state = .running
            lastLine = "starting…"
        } catch {
            state = .failed("\(error)")
        }
    }
}
