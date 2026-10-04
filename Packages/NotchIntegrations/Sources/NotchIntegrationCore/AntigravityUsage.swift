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
        return SubscriptionUsage(provider: .antigravity, plan: nil, windows: windows, fetchedAt: now)
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
        return SubscriptionUsage(provider: .antigravity, plan: plan, windows: windows, fetchedAt: now)
    }
    private static func checkCode(_ root: [String: Any]) throws {
        if let code = root["code"], !["0", "ok", "success"].contains(String(describing: code).lowercased()) { throw UsageError.unavailable }
    }
}

enum AntigravityUsageClient {
    static func fetch(home: String) async throws -> SubscriptionUsage {
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
        let candidates = [home + "/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy", "/Applications/Antigravity.app/Contents/Resources/app/bin/agy"]
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw UsageError.login(.antigravity) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("boringnotch-agy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let versionData = try await AntigravityCommand.run(binary, arguments: ["--version"], directory: directory, home: home, timeout: 3, limit: 4096)
        let version = String(decoding: versionData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3, (parts[0], parts[1], parts[2]) >= (1, 1, 11) else {
            throw AntigravityUsageError.unsupportedCLI
        }
        // Version gate is required: older agy versions could treat unknown slash commands as prompts.
        let report = try await AntigravityCommand.run(binary, arguments: ["-p", "/usage", "--output-format", "json", "--print-timeout", "25s"], directory: directory, home: home, timeout: 27, limit: 1_048_576)
        return try AntigravityUsageParser.summary(report, cli: true)
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

enum AntigravityUsageError: LocalizedError {
    case unsupportedCLI, failed, timedOut, oversized
    var errorDescription: String? {
        switch self {
        case .unsupportedCLI: return "读取用量需要 agy 1.1.11 或更新版本，请更新 Antigravity CLI。"
        case .failed: return "无法读取 Antigravity 配额，请确认应用或 agy CLI 已登录。"
        case .timedOut: return "Antigravity 配额读取超时，稍后自动重试。"
        case .oversized: return "Antigravity 用量报告超过大小限制。"
        }
    }
}
