import Foundation
import Darwin

/// Runs shell commands and captures output. Core utility for all libimobiledevice interactions.
enum Shell {

    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var succeeded: Bool { exitCode == 0 }
        var output: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private final class AsyncCommandState: @unchecked Sendable {
        private let lock = NSLock()
        private var stdoutData = Data()
        private var stderrData = Data()
        private var didFinish = false

        func append(_ data: Data, toStdout: Bool) {
            guard !data.isEmpty else { return }
            lock.lock()
            if toStdout {
                stdoutData.append(data)
            } else {
                stderrData.append(data)
            }
            lock.unlock()
        }

        func hasFinished() -> Bool {
            lock.lock()
            let value = didFinish
            lock.unlock()
            return value
        }

        func finish(timedOut: Bool, timeout: TimeInterval, exitCode: Int32) -> Result? {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return nil
            }
            didFinish = true
            let stdout = stdoutData
            var stderr = String(data: stderrData, encoding: .utf8) ?? ""
            if timedOut {
                let timeoutMessage = "Command timed out after \(Int(timeout))s"
                stderr = stderr.isEmpty ? timeoutMessage : stderr + "\n" + timeoutMessage
            }
            lock.unlock()

            return Result(
                exitCode: timedOut ? -2 : exitCode,
                stdout: String(data: stdout, encoding: .utf8) ?? "",
                stderr: stderr
            )
        }
    }

    private static func environmentWithToolPaths() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = "\(home)/.local/bin:\(home)/.local/pipx/venvs/pymobiledevice3/bin:/opt/homebrew/bin:/usr/local/bin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = extra + ":" + path
        } else {
            environment["PATH"] = extra + ":/usr/bin:/bin"
        }
        return environment
    }

    /// Run a command synchronously and return the result.
    @discardableResult
    static func run(_ command: String, arguments: [String] = [], timeout: TimeInterval = 60) -> Result {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = environmentWithToolPaths()

        let stdoutQueue = DispatchQueue(label: "com.phosphor.shell.stdout")
        let stderrQueue = DispatchQueue(label: "com.phosphor.shell.stderr")
        var stdoutData = Data()
        var stderrData = Data()
        let readGroup = DispatchGroup()
        let waitSemaphore = DispatchSemaphore(value: 0)

        // Use Process.terminationHandler rather than blocking a global dispatch
        // worker on a synchronous process wait. Phosphor may run many short device CLI
        // probes; tying up one worker per process can exhaust libdispatch's soft
        // thread limit and leave the app running but unresponsive.
        process.terminationHandler = { _ in
            waitSemaphore.signal()
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            return Result(exitCode: -1, stdout: "", stderr: "Failed to launch: \(error.localizedDescription)")
        }

        readGroup.enter()
        stdoutQueue.async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        readGroup.enter()
        stderrQueue.async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        var timedOut = false
        if waitSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if waitSemaphore.wait(timeout: .now() + 2) == .timedOut {
                process.interrupt()
                if waitSemaphore.wait(timeout: .now() + 1) == .timedOut {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = waitSemaphore.wait(timeout: .now() + 1)
                }
            }
        }

        process.terminationHandler = nil

        _ = readGroup.wait(timeout: .now() + 2)

        var stderr = String(data: stderrData, encoding: .utf8) ?? ""
        if timedOut {
            let timeoutMessage = "Command timed out after \(Int(timeout))s"
            stderr = stderr.isEmpty ? timeoutMessage : stderr + "\n" + timeoutMessage
        }

        return Result(
            exitCode: timedOut ? -2 : process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: stderr
        )
    }

    /// Run a command asynchronously.
    static func runAsync(_ command: String, arguments: [String] = [], timeout: TimeInterval = 300) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let state = AsyncCommandState()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = environmentWithToolPaths()

            @Sendable func finish(timedOut: Bool) {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                state.append(stdoutPipe.fileHandleForReading.availableData, toStdout: true)
                state.append(stderrPipe.fileHandleForReading.availableData, toStdout: false)

                guard let result = state.finish(
                    timedOut: timedOut,
                    timeout: timeout,
                    exitCode: process.terminationStatus
                ) else {
                    return
                }

                process.terminationHandler = nil
                continuation.resume(returning: result)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                state.append(handle.availableData, toStdout: true)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                state.append(handle.availableData, toStdout: false)
            }

            process.terminationHandler = { _ in
                finish(timedOut: false)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: Result(
                    exitCode: -1,
                    stdout: "",
                    stderr: "Failed to launch: \(error.localizedDescription)"
                ))
                return
            }

            Task {
                let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !state.hasFinished() else { return }

                process.terminate()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !state.hasFinished() else { return }

                process.interrupt()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !state.hasFinished() else { return }

                Darwin.kill(process.processIdentifier, SIGKILL)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                finish(timedOut: true)
            }
        }
    }

    /// Run a command with real-time output streaming via callback. Returns Process for termination.
    @discardableResult
    static func runStreaming(
        _ command: String,
        arguments: [String] = [],
        onOutput: @escaping (String) -> Void,
        onError: @escaping (String) -> Void = { _ in },
        completion: @escaping (Int32) -> Void
    ) -> Process? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = environmentWithToolPaths()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { onOutput(str) }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { onError(str) }
            }
        }

        process.terminationHandler = { proc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { completion(proc.terminationStatus) }
        }

        do {
            try process.run()
            return process
        } catch {
            onError("Failed to launch: \(error.localizedDescription)")
            completion(-1)
            return nil
        }
    }

    /// Check if a command-line tool is available.
    static func which(_ tool: String) -> String? {
        let result = run("which", arguments: [tool])
        return result.succeeded ? result.output : nil
    }

    /// Check if required device-management tools are installed.
    static func checkDependencies() -> [String: Bool] {
        let tools = [
            "idevice_id",
            "ideviceinfo",
            "idevicepair",
            "idevicebackup2",
            "idevicediagnostics",
            "idevicesyslog",
            "idevicename",
            "idevicescreenshot",
            "ideviceinstaller"
        ]
        var status: [String: Bool] = [:]
        for tool in tools {
            status[tool] = which(tool) != nil
        }

        // Check pymobiledevice3 using the same resolver used by the app's device
        // operations. GUI apps often do not inherit the terminal's Python/PATH,
        // and pipx installs expose a runnable binary rather than an importable
        // module from Homebrew's `python3`.
        status["pymobiledevice3"] = PyMobileDevice.available()

        return status
    }
}
