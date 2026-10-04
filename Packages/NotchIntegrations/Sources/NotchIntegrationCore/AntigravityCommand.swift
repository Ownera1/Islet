import Foundation
import Darwin

/// Only runs the version check and the version-gated built-in /usage command.
/// The inherited OS sandbox prevents the CLI and its children from launching login UI.
enum AntigravityCommand {
    static let backgroundProfile = #"""
    (version 1)
    (allow default)
    (deny process-exec
        (literal "/usr/bin/open")
        (literal "/usr/bin/osascript")
        (regex #"\.app/Contents/MacOS/"))
    (deny mach-lookup
        (global-name-regex #"^com\.apple\.lsd")
        (global-name-regex #"^com\.apple\.coreservices\.launchservicesd")
        (global-name-regex #"^com\.apple\.appleevents"))
    """#
    static func run(_ binary: String, arguments: [String], directory: URL, home: String, timeout: TimeInterval, limit: Int, diagnosticsFile: URL? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            throw AntigravityUsageError.backgroundUnavailable
        }
        let state = RunningCommand()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.start(binary, arguments: arguments, directory: directory, home: home, timeout: timeout, limit: limit, diagnosticsFile: diagnosticsFile, continuation: continuation)
            }
        } onCancel: { state.cancel() }
    }
}

private final class RunningCommand: @unchecked Sendable {
    private let queue = DispatchQueue(label: "boringnotch.antigravity.usage")
    private let process = Process()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private var bytes = Data()
    private var diagnostics = Data()
    private var diagnosticsFile: URL?
    private var continuation: CheckedContinuation<Data, Error>?
    private var timer: DispatchSourceTimer?
    private var deadline = Date()
    private var owned: [Int32: AntigravityProcesses.Identity] = [:]
    private var cancelled = false
    private var error: Error?
    private var exited = false
    private var outputEnded = false
    private var diagnosticsEnded = false
    func cancel() { queue.async { self.cancelled = true; self.abort(CancellationError()) } }
    func start(_ binary: String, arguments: [String], directory: URL, home: String, timeout: TimeInterval, limit: Int, diagnosticsFile: URL?, continuation: CheckedContinuation<Data, Error>) {
        queue.async {
            self.continuation = continuation
            self.diagnosticsFile = diagnosticsFile
            guard !self.cancelled else { self.complete(.failure(CancellationError())); return }
            // Never retry without the sandbox, even when applying it fails.
            self.process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            self.process.arguments = ["-p", AntigravityCommand.backgroundProfile, binary] + arguments
            self.process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            // Child CLIs must resolve the login user's home, not the UI app's container
            // or the helper's XPC identity. The explicit background sandbox still applies.
            for key in ["CFFIXED_USER_HOME", "APP_SANDBOX_CONTAINER_ID", "XPC_SERVICE_NAME", "XPC_FLAGS"] {
                environment.removeValue(forKey: key)
            }
            environment["HOME"] = home
            environment["PATH"] = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].joined(separator: ":")
            environment["NO_COLOR"] = "1"
            environment["CI"] = "1"
            environment["TERM"] = "dumb"
            environment["BROWSER"] = "/usr/bin/false"
            self.process.environment = environment
            self.process.standardInput = FileHandle.nullDevice
            self.process.standardError = self.stderr
            self.process.standardOutput = self.stdout
            self.stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                self.queue.async {
                    guard self.continuation != nil else { return }
                    if data.isEmpty {
                        self.outputEnded = true; handle.readabilityHandler = nil; self.finishIfReady()
                    } else if self.bytes.count + data.count > limit { self.abort(AntigravityUsageError.oversized) }
                    else { self.bytes.append(data) }
                }
            }
            self.stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                self.queue.async {
                    guard self.continuation != nil else { return }
                    if data.isEmpty {
                        self.diagnosticsEnded = true; handle.readabilityHandler = nil; self.finishIfReady()
                    } else {
                        // Keep only enough diagnostics to classify failure; never expose raw CLI logs.
                        self.diagnostics.append(data)
                        self.diagnostics = Data(self.diagnostics.suffix(16_384))
                    }
                }
            }
            self.process.terminationHandler = { _ in
                self.queue.async { self.exited = true; self.finishIfReady() }
            }
            do { try self.process.run() } catch { self.complete(.failure(AntigravityUsageError.failed)); return }
            let pid = self.process.processIdentifier
            if let identity = AntigravityProcesses.identity(pid) { self.owned[pid] = identity }
            self.deadline = Date().addingTimeInterval(timeout)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(200))
            timer.setEventHandler { [self] in
                trackDescendants()
                if interactiveLoginStarted { abort(authenticationFailure); return }
                if Date() >= deadline { abort(authenticationFailed ? authenticationFailure : AntigravityUsageError.timedOut) }
            }
            self.timer = timer; timer.resume()
        }
    }
    private func trackDescendants() {
        var candidates: [Int32: AntigravityProcesses.Identity] = [:]
        for pid in AntigravityProcesses.allPIDs() { if let identity = AntigravityProcesses.identity(pid) { candidates[pid] = identity } }
        var changed = true
        while changed {
            changed = false
            for (pid, identity) in candidates where owned[pid] == nil {
                if let parent = owned[identity.parent], candidates[identity.parent]?.started == parent.started {
                    owned[pid] = identity; changed = true
                }
            }
        }
    }
    private func abort(_ failure: Error) {
        guard continuation != nil else { return }
        error = failure
        cleanupProcesses()
        complete(.failure(failure))
    }
    private func cleanupProcesses() {
        trackDescendants()
        let tracked = owned
        // PID and start-time checks prevent touching unrelated or reused processes.
        for (pid, identity) in owned where pid != process.processIdentifier {
            if AntigravityProcesses.identity(pid)?.started == identity.started { kill(pid, SIGTERM) }
        }
        if process.isRunning { process.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            for (pid, identity) in tracked {
                if AntigravityProcesses.identity(pid)?.started == identity.started { kill(pid, SIGKILL) }
            }
        }
    }
    private func finishIfReady() {
        guard exited, outputEnded, diagnosticsEnded else { return }
        if let error { complete(.failure(error)) }
        else if process.terminationStatus == 0 { complete(.success(bytes)) }
        else { complete(.failure(authenticationFailed ? authenticationFailure : AntigravityUsageError.failed)) }
    }
    private var authenticationFailure: AntigravityUsageError {
        let message = diagnosticMessage
        // macOS security exits with the low byte of errSecInteractionNotAllowed
        // (-25308 = exit 36) when the helper cannot access the login keychain.
        let keyringDenied = message.contains("failed to load stored token from keyring") && message.contains("exit status 36")
        return keyringDenied || message.contains("errsecinteractionnotallowed") || message.contains("user interaction is not allowed")
            ? .credentialAccessDenied : .authenticationRequired
    }
    private var authenticationFailed: Bool {
        let message = String(decoding: diagnostics, as: UTF8.self).lowercased()
        let reportedFailure = ["authentication required", "not authenticated", "not logged in", "sign in", "sign-in", "oauth", "login"].contains { message.contains($0) }
        // The private log normally says "not authenticated" before successful silent
        // auth. That startup message must not turn a later network timeout into login failure.
        return reportedFailure || interactiveLoginStarted || diagnosticMessage.contains("silent auth failed")
    }
    private var interactiveLoginStarted: Bool {
        let message = diagnosticMessage
        return ["triggering interactive oauth", "starting oauth authentication flow", "consumeroauth: starting oauth flow"].contains { message.contains($0) }
    }
    private var diagnosticMessage: String {
        var message = String(decoding: diagnostics, as: UTF8.self)
        if let diagnosticsFile, let handle = try? FileHandle(forReadingFrom: diagnosticsFile) {
            defer { try? handle.close() }
            if let length = try? handle.seekToEnd() {
                try? handle.seek(toOffset: length > 16_384 ? length - 16_384 : 0)
                if let data = try? handle.read(upToCount: 16_384) { message += String(decoding: data, as: UTF8.self) }
            }
        }
        return message.lowercased()
    }
    private func complete(_ result: Result<Data, Error>) {
        guard let pending = continuation else { return }
        continuation = nil; timer?.cancel(); timer = nil
        cleanupProcesses()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        try? stdout.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForReading.close(); try? stderr.fileHandleForWriting.close()
        process.terminationHandler = nil
        pending.resume(with: result)
    }
}
