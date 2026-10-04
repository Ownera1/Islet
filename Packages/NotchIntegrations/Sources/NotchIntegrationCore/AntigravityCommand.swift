import Foundation
import Darwin

/// Only runs the version check and the version-gated built-in /usage command, never a shell.
enum AntigravityCommand {
    static func run(_ binary: String, arguments: [String], directory: URL, home: String, timeout: TimeInterval, limit: Int) async throws -> Data {
        try Task.checkCancellation()
        let state = RunningCommand()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.start(binary, arguments: arguments, directory: directory, home: home, timeout: timeout, limit: limit, continuation: continuation)
            }
        } onCancel: { state.cancel() }
    }
}

private final class RunningCommand: @unchecked Sendable {
    private let queue = DispatchQueue(label: "boringnotch.antigravity.usage")
    private let process = Process()
    private let stdout = Pipe()
    private var bytes = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var timer: DispatchSourceTimer?
    private var deadline = Date()
    private var owned: [Int32: AntigravityProcesses.Identity] = [:]
    private var cancelled = false
    private var error: Error?
    private var exited = false
    private var outputEnded = false
    func cancel() { queue.async { self.cancelled = true; self.abort(CancellationError()) } }
    func start(_ binary: String, arguments: [String], directory: URL, home: String, timeout: TimeInterval, limit: Int, continuation: CheckedContinuation<Data, Error>) {
        queue.async {
            self.continuation = continuation
            guard !self.cancelled else { self.complete(.failure(CancellationError())); return }
            self.process.executableURL = URL(fileURLWithPath: binary); self.process.arguments = arguments
            self.process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            environment["HOME"] = home
            environment["PATH"] = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].joined(separator: ":")
            environment["NO_COLOR"] = "1"
            self.process.environment = environment
            self.process.standardInput = FileHandle.nullDevice; self.process.standardError = FileHandle.nullDevice
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
                if Date() >= deadline { abort(AntigravityUsageError.timedOut) }
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
        // PID and start-time checks prevent touching unrelated or reused processes.
        for (pid, identity) in owned where pid != process.processIdentifier {
            if AntigravityProcesses.identity(pid)?.started == identity.started { kill(pid, SIGTERM) }
        }
        if process.isRunning { process.terminate() }
    }
    private func finishIfReady() {
        guard exited, outputEnded else { return }
        if let error { complete(.failure(error)) }
        else if process.terminationStatus == 0 { complete(.success(bytes)) }
        else { complete(.failure(AntigravityUsageError.failed)) }
    }
    private func complete(_ result: Result<Data, Error>) {
        guard let pending = continuation else { return }
        continuation = nil; timer?.cancel(); timer = nil
        cleanupProcesses()
        stdout.fileHandleForReading.readabilityHandler = nil
        try? stdout.fileHandleForReading.close(); try? stdout.fileHandleForWriting.close()
        process.terminationHandler = nil
        pending.resume(with: result)
    }
}
