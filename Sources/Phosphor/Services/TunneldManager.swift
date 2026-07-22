import Foundation

/// Manages `pymobiledevice3 remote tunneld` — required for AFC file transfers on iOS 17+ devices.
/// Starts the daemon with elevated privileges via osascript and monitors it in the background.
@MainActor
final class TunneldManager: ObservableObject {

    enum State: Equatable {
        case unknown, checking, running, starting, stopped
        case failed(String)

        var isRunning: Bool { self == .running }
        var isStarting: Bool { self == .starting }
        var needsAttention: Bool {
            switch self { case .stopped, .failed: return true; default: return false }
        }
    }

    @Published var state: State = .unknown

    private var monitorTask: Task<Void, Never>?

    // MARK: - Public API

    func checkStatus() async {
        state = .checking
        state = await Self.detect() ? .running : .stopped
    }

    func start() async {
        guard let pymPath = Shell.which("pymobiledevice3") else {
            state = .failed("pymobiledevice3 not found. Install with: pipx install pymobiledevice3")
            return
        }
        state = .starting

        // Single-quoted path handles spaces; & detaches so osascript exits immediately.
        let cmd = "nohup '\(pymPath)' remote tunneld > /tmp/phosphor-tunneld.log 2>&1 &"
        let script = "do shell script \"\(cmd)\" with administrator privileges"

        // osascript shows the system auth dialog; Shell.runAsync suspends (not blocks) until done.
        let result = await Shell.runAsync("osascript", arguments: ["-e", script], timeout: 120)

        guard result.succeeded else {
            // User cancelled or auth failed — don't show error, just revert to stopped.
            state = .stopped
            return
        }

        // Give the daemon 2 s to initialize before verifying.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let running = await Self.detect()
        state = running ? .running : .failed("tunneld did not start. Try in Terminal: sudo pymobiledevice3 remote tunneld")
        if state.isRunning { startMonitoring() }
    }

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000) // poll every 8 s
                guard let self, !Task.isCancelled else { return }
                let running = await Self.detect()
                if self.state.isRunning && !running { self.state = .stopped }
                else if !self.state.isRunning && running { self.state = .running }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Private

    private static func detect() async -> Bool {
        let r = await Shell.runAsync("pgrep", arguments: ["-f", "remote tunneld"], timeout: 5)
        return r.succeeded && !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
