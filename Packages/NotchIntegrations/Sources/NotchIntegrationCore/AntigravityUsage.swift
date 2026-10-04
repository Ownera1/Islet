import Foundation

/// Antigravity has independent quota groups. No Gemini CLI credentials are reused here.
public enum AntigravityUsageParser {
    public static func summary(_ data: Data, cli: Bool = false, now: Date = Date()) throws -> SubscriptionUsage {
        let root = try UsageParser.object(data)
        let payload: [String: Any]
        if cli {
            guard root["status"] as? String == "SUCCESS", let command = root["command"] as? [String: Any],
                  command["name"] as? String == "usage", let body = command["data"] as? [String: Any] else { throw UsageError.invalid }
            payload = body
        } else {
            try checkCode(root)
            payload = root["response"] as? [String: Any] ?? root["summary"] as? [String: Any] ?? root
        }
        var windows: [UsageWindow] = []
        for (index, group) in (payload["groups"] as? [[String: Any]] ?? []).enumerated() {
            let groupName = group["displayName"] as? String ?? group["name"] as? String ?? "模型"
            let title = groupName.lowercased().contains("gemini") ? "Gemini" : groupName.lowercased().contains("claude") ? "Claude / GPT" : groupName
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard bucket["disabled"] as? Bool != true,
                      let id = bucket["bucketId"] as? String ?? bucket["id"] as? String, !id.isEmpty else { continue }
                let remaining = bucket["remaining"] as? [String: Any]
                let value = bucket["remainingFraction"] ?? bucket["remaining_fraction"] ?? remaining?["remainingFraction"]
                    ?? (remaining?["case"] as? String == "remainingFraction" ? remaining?["value"] : nil)
                guard let fraction = UsageParser.number(value), fraction.isFinite else { continue }
                let window = bucket["window"] as? String
                let label = window == "5h" ? "5 小时" : window == "weekly" ? "每周" : bucket["displayName"] as? String ?? bucket["name"] as? String ?? "当前额度"
                let reset = UsageParser.date(bucket["resetTime"] as? String ?? bucket["reset_time"] as? String)
                windows.append(UsageWindow(id: "\(index):\(id)", label: title + " · " + label, usedPercent: (1 - fraction) * 100, resetsAt: reset))
            }
        }
        guard !windows.isEmpty else { throw UsageError.unavailable }
        let plan = (payload["planInfo"] as? [String: Any])?["planName"] as? String
            ?? payload["planName"] as? String
        return SubscriptionUsage(provider: .antigravity, plan: plan, windows: windows, fetchedAt: now, source: cli ? .antigravityCLI : .antigravityApp)
    }
    public static func models(_ data: Data, now: Date = Date()) throws -> SubscriptionUsage {
        let root = try UsageParser.object(data)
        try checkCode(root)
        let status = root["userStatus"] as? [String: Any]
        let models = root["clientModelConfigs"] as? [[String: Any]]
            ?? (status?["cascadeModelConfigData"] as? [String: Any])?["clientModelConfigs"] as? [[String: Any]] ?? []
        let windows = models.compactMap { model -> UsageWindow? in
            guard let quota = model["quotaInfo"] as? [String: Any], let fraction = UsageParser.number(quota["remainingFraction"]), fraction.isFinite,
                  let id = (model["modelOrAlias"] as? [String: Any])?["model"] as? String else { return nil }
            return UsageWindow(id: id, label: model["label"] as? String ?? id, usedPercent: (1 - fraction) * 100, resetsAt: UsageParser.date(quota["resetTime"] as? String))
        }
        guard !windows.isEmpty else { throw UsageError.unavailable }
        let plan = ((status?["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any])?["planName"] as? String
            ?? (status?["userTier"] as? [String: Any])?["name"] as? String
        return SubscriptionUsage(provider: .antigravity, plan: plan, windows: windows, fetchedAt: now, source: .antigravityApp)
    }
    private static func checkCode(_ root: [String: Any]) throws {
        if let code = root["code"], !["0", "ok", "success"].contains(String(describing: code).lowercased()) { throw UsageError.unavailable }
    }
}

enum AntigravityUsageClient {
    static func fetch(home: String) async throws -> SubscriptionUsage {
        try await fetch(cli: { try await fetchCLI(home: home) }, application: { try await fetchApplication() })
    }
    /// Read exactly one successful source. Never add or average shared quota snapshots.
    static func fetch(
        cli: () async throws -> SubscriptionUsage,
        application: () async throws -> SubscriptionUsage
    ) async throws -> SubscriptionUsage {
        try Task.checkCancellation()
        let cliFailure: Error
        do {
            return try sourced(await cli(), source: .antigravityCLI)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            cliFailure = error
        }
        try Task.checkCancellation()
        do {
            return try sourced(await application(), source: .antigravityApp)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw AntigravitySharedUsageError(
                cli: failureSummary(cliFailure), application: failureSummary(error),
                cliCredentialAccessDenied: (cliFailure as? AntigravityUsageError) == .credentialAccessDenied
            )
        }
    }
    private static func sourced(_ usage: SubscriptionUsage, source: SubscriptionUsageSource) throws -> SubscriptionUsage {
        guard !usage.windows.isEmpty else { throw UsageError.unavailable }
        return SubscriptionUsage(provider: .antigravity, plan: usage.plan, windows: usage.windows, fetchedAt: usage.fetchedAt, source: source)
    }
    private static func failureSummary(_ error: Error) -> String {
        if let error = error as? AntigravityUsageError {
            switch error {
            case .cliNotInstalled: return "未检测到 agy CLI"
            case .unsupportedCLI: return "需要 agy 1.1.11 或更新的稳定版本"
            case .authenticationRequired: return "未登录或登录已失效"
            case .credentialAccessDenied: return "无法访问已保存的登录凭据（钥匙串）"
            case .timedOut: return "读取超时"
            case .backgroundUnavailable: return "无法在后台安全读取"
            case .oversized: return "用量报告过大"
            case .failed: return "读取失败，请确认已登录"
            }
        }
        if let error = error as? UsageError {
            switch error {
            case .login: return "应用未运行或未登录"
            case .expired: return "登录已失效"
            case .unavailable: return "未返回可读取的配额"
            case .invalid: return "用量数据格式不支持"
            case .http(let status): return "服务不可用（HTTP \(status)）"
            }
        }
        return "读取失败，请稍后重试"
    }
    static func fetchApplication() async throws -> SubscriptionUsage {
        let endpoints = await Task.detached(priority: .utility) { AntigravityProcesses.endpoints() }.value
        let deadline = Date().addingTimeInterval(10)
        for endpoint in endpoints {
            for method in ["RetrieveUserQuotaSummary", "GetUserStatus", "GetCommandModelConfigs"] {
                try Task.checkCancellation()
                guard Date() < deadline else { break }
                do {
                    let data = try await request(endpoint, method: method, timeout: min(2, deadline.timeIntervalSinceNow))
                    return try method == "RetrieveUserQuotaSummary" ? AntigravityUsageParser.summary(data) : AntigravityUsageParser.models(data)
                } catch is CancellationError { throw CancellationError() } catch { continue }
            }
        }
        // The fallback only reads an existing service; it never starts an app or a CLI.
        throw UsageError.login(.antigravity)
    }
    static func fetchCLI(home: String) async throws -> SubscriptionUsage {
        guard let binary = cliBinary(home: home) else { throw AntigravityUsageError.cliNotInstalled }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("boringnotch-agy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let versionData = try await AntigravityCommand.run(binary, arguments: ["--version"], directory: directory, home: home, timeout: 3, limit: 4096)
        let version = String(decoding: versionData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard supportsUsage(version: version) else {
            throw AntigravityUsageError.unsupportedCLI
        }
        // Version gate is required: older agy versions could treat unknown slash commands as prompts.
        // A private, temporary log also lets us stop immediately if silent auth falls
        // back to interactive OAuth. It is removed with the probe directory, never shown.
        let diagnostics = directory.appendingPathComponent("usage.log")
        let report = try await AntigravityCommand.run(binary, arguments: ["-p", "/usage", "--output-format", "json", "--print-timeout", "25s", "--log-file", diagnostics.path], directory: directory, home: home, timeout: 27, limit: 1_048_576, diagnosticsFile: diagnostics)
        return try AntigravityUsageParser.summary(report, cli: true)
    }
    static func cliBinary(home: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let paths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = [home + "/.local/bin/agy", home + "/.gemini/antigravity-cli/bin/agy"]
            + paths.filter { $0.hasPrefix("/") }.map { $0 + "/agy" }
            + ["/opt/homebrew/bin/agy", "/usr/local/bin/agy", "/Applications/Antigravity.app/Contents/Resources/app/bin/agy"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func supportsUsage(version: String) -> Bool {
        // Reject prereleases and unrecognized output before submitting any slash command.
        let pattern = #"^(?:agy\s+)?v?(\d+)\.(\d+)\.(\d+)(?:\+[A-Za-z0-9.-]+)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: version, range: NSRange(version.startIndex..., in: version)) else { return false }
        let parts = (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: version) else { return nil }
            return Int(version[range])
        }
        return parts.count == 3 && (parts[0], parts[1], parts[2]) >= (1, 1, 11)
    }
    private static func request(_ endpoint: AntigravityProcesses.Endpoint, method: String, timeout: TimeInterval) async throws -> Data {
        let url = URL(string: "https://127.0.0.1:\(endpoint.port)/exa.language_server_pb.LanguageServerService/\(method)")!
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = max(0.1, timeout)
        request.httpBody = try JSONSerialization.data(withJSONObject: method == "RetrieveUserQuotaSummary" ? ["forceRefresh": true] : ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "locale": "en"]])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if !endpoint.token.isEmpty { request.setValue(endpoint.token, forHTTPHeaderField: "X-Codeium-Csrf-Token") }
        let delegate = AntigravityLoopbackDelegate(port: endpoint.port)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.waitsForConnectivity = false
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UsageError.unavailable }
        return data
    }
}

struct AntigravitySharedUsageError: LocalizedError {
    let cli: String
    let application: String
    let cliCredentialAccessDenied: Bool
    var errorDescription: String? {
        let recovery = cliCredentialAccessDenied
            ? "请重启 Islet 后重试，或打开已登录的 Antigravity，再刷新。"
            : "请手动运行 agy 登录，或打开已登录的 Antigravity，再刷新。"
        return "无法读取共享额度。\nagy CLI：\(cli)\nAntigravity：\(application)\n\(recovery)"
    }
}

private final class AntigravityLoopbackDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let port: Int
    init(port: Int) { self.port = port }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        // Antigravity's local server uses a self-signed certificate. This exception is confined
        // to a loopback port owned by a same-user Antigravity process, with its CSRF token.
        guard space.host == "127.0.0.1", space.port == port,
              space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
}

enum AntigravityUsageError: LocalizedError, Equatable {
    case cliNotInstalled, unsupportedCLI, failed, timedOut, oversized, authenticationRequired, credentialAccessDenied, backgroundUnavailable
    var errorDescription: String? {
        switch self {
        case .cliNotInstalled: return "未检测到 agy CLI，请安装后刷新用量。"
        case .unsupportedCLI: return "读取用量需要 agy 1.1.11 或更新版本，请更新 Antigravity CLI。"
        case .failed: return "无法读取 agy CLI 配额，请确认已登录后刷新用量。"
        case .authenticationRequired: return "agy CLI 未登录或登录已失效，请在终端手动运行 agy 登录后刷新。"
        case .credentialAccessDenied: return "无法访问 agy CLI 已保存的登录凭据，请重启 Islet 后重试。"
        case .backgroundUnavailable: return "系统无法安全地在后台读取 agy CLI 配额，请稍后重试。"
        case .timedOut: return "Antigravity 配额读取超时，稍后自动重试。"
        case .oversized: return "Antigravity 用量报告超过大小限制。"
        }
    }
}
