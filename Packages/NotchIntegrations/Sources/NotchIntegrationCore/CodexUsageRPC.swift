import Foundation
import CodeIslandCore

@MainActor
final class CodexUsageRPC {
    private let client: CodexAppServerClient
    private var continuation: CheckedContinuation<SubscriptionUsage, Error>?
    private var initialization: CodexRequestID?
    private var usageRequest: CodexRequestID?
    private var timeout: Task<Void, Never>?
    private init(binary: String, home: String) {
        var environment = ProcessInfo.processInfo.environment; environment["CODEX_HOME"] = home
        client = CodexAppServerClient(executableURL: URL(fileURLWithPath: binary), environment: environment)
    }
    static func fetch(home: String) async throws -> SubscriptionUsage {
        let paths = [CodexAppServerClient.defaultExecutablePath, HomePaths.userHome + "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", HomePaths.userHome + "/.local/bin/codex"]
        guard let binary = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw UsageError.login(.openai) }
        let probe = CodexUsageRPC(binary: binary, home: home)
        return try await withCheckedThrowingContinuation { continuation in probe.start(continuation) }
    }
    private func start(_ continuation: CheckedContinuation<SubscriptionUsage, Error>) {
        self.continuation = continuation
        client.onMessage = { [self] message in Task { @MainActor in handle(message) } }
        client.onExit = { [self] _ in Task { @MainActor in finish(.failure(UsageError.unavailable)) } }
        timeout = Task { [self] in
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled { finish(.failure(UsageError.unavailable)) }
        }
        do { try client.start(); initialization = try client.initializeHandshake(clientName: "boringnotch-usage", clientVersion: "1.0") }
        catch { finish(.failure(error)) }
    }
    private func handle(_ message: CodexJSONRPCMessage) {
        guard continuation != nil, case .response(let id) = message.kind else { return }
        if message.raw["error"] != nil { finish(.failure(UsageError.unavailable)); return }
        do {
            if id == initialization {
                try client.sendNotification(method: "initialized")
                usageRequest = try client.sendRequest(method: "account/rateLimits/read")
            } else if id == usageRequest, let result = message.raw["result"]?.asObject {
                let data = try JSONSerialization.data(withJSONObject: result.mapValues(json))
                finish(.success(try UsageParser.openaiRPC(data)))
            }
        } catch { finish(.failure(error)) }
    }
    private func finish(_ result: Result<SubscriptionUsage, Error>) {
        let pending = continuation; continuation = nil; timeout?.cancel(); timeout = nil
        client.onMessage = nil; client.onExit = nil; client.stop()
        pending?.resume(with: result)
    }
    private func json(_ value: AnyCodableLike) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(json)
        case .object(let value): return value.mapValues(json)
        }
    }
}
