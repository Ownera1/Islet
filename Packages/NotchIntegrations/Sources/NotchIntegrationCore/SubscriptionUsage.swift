import Foundation
import CodeIslandCore

public enum SubscriptionProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude, openai, gemini, antigravity
    /// Gemini remains decodable for compatibility, but is not monitored or displayed.
    public static let monitoredProviders: [SubscriptionProvider] = [.claude, .openai, .antigravity]
    public var id: String { rawValue }
    public var name: String { switch self { case .claude: return "Claude"; case .openai: return "OpenAI"; case .gemini: return "Gemini"; case .antigravity: return "Google AI" } }
    public var visibilityKey: String { "subscriptionVisible." + rawValue }
    public func isVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: visibilityKey) as? Bool ?? true
    }
    public var scope: String {
        switch self {
        case .claude: return "Claude 订阅"
        case .openai: return "Codex 订阅额度"
        case .gemini: return "Gemini CLI / Code Assist"
        case .antigravity: return "Antigravity / agy 共享配额"
        }
    }
    public var dashboard: URL? {
        switch self {
        case .claude: return URL(string: "https://claude.ai/settings/usage")!
        case .openai: return URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .gemini: return URL(string: "https://gemini.google.com")!
        case .antigravity: return nil
        }
    }
}
public struct UsageWindow: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public var remainingPercent: Double { 100 - usedPercent }
    public init(id: String, label: String, usedPercent: Double, resetsAt: Date? = nil) {
        self.id = id; self.label = label; self.usedPercent = min(100, max(0, usedPercent)); self.resetsAt = resetsAt
    }
}
public enum SubscriptionUsageSource: String, Codable, Sendable {
    case antigravityCLI = "antigravity-cli"
    case antigravityApp = "antigravity-app"
    public var name: String {
        switch self {
        case .antigravityCLI: return "agy CLI"
        case .antigravityApp: return "Antigravity 应用"
        }
    }
}
public struct SubscriptionUsage: Equatable, Codable, Sendable {
    public let provider: SubscriptionProvider
    public let plan: String?
    public let windows: [UsageWindow]
    public let fetchedAt: Date
    public let source: SubscriptionUsageSource?
    public init(provider: SubscriptionProvider, plan: String?, windows: [UsageWindow], fetchedAt: Date = Date(), source: SubscriptionUsageSource? = nil) {
        self.provider = provider; self.plan = plan; self.windows = windows; self.fetchedAt = fetchedAt
        self.source = source
    }
}
public enum UsageError: LocalizedError {
    case login(SubscriptionProvider), expired(SubscriptionProvider), unavailable, http(Int), invalid
    public var errorDescription: String? {
        switch self {
        case .login(.antigravity): return "Antigravity 应用未运行或未登录。"
        case .login(let provider): return "请先登录 \(provider == .openai ? "Codex" : provider == .gemini ? "Gemini CLI" : "Claude Code")。"
        case .expired(let provider): return "\(provider.name) 登录已过期，请打开对应 CLI 更新登录。"
        case .unavailable: return "该账户暂未返回可读取的配额。"
        case .http(429): return "请求过于频繁，稍后自动重试。"
        case .http(let status): return "用量服务暂不可用（HTTP \(status)）。"
        case .invalid: return "用量数据格式已变化，请稍后更新适配。"
        }
    }
}

/// Schemas verified against CodeIsland and CodexBar. Never infer missing limits as zero.
public enum UsageParser {
    public static func openai(_ data: Data, now: Date = Date()) throws -> SubscriptionUsage {
        let root = try object(data)
        var windows: [UsageWindow] = []
        func append(_ limits: [String: Any], prefix: String = "", title: String = "") {
            for (key, fallback) in [("primary_window", "当前窗口"), ("secondary_window", "每周") ] {
                guard let row = limits[key] as? [String: Any], let percent = number(row["used_percent"]), percent.isFinite else { continue }
                let seconds = number(row["limit_window_seconds"])
                let label = seconds == 18000 ? "5 小时" : seconds == 604800 ? "每周" : fallback
                let reset = number(row["reset_at"]).map { Date(timeIntervalSince1970: $0) }
                    ?? number(row["reset_after_seconds"]).map { now.addingTimeInterval($0) }
                windows.append(UsageWindow(id: prefix + key, label: title + label, usedPercent: percent, resetsAt: reset))
            }
        }
        if let limits = root["rate_limit"] as? [String: Any] { append(limits) }
        for (i, extra) in (root["additional_rate_limits"] as? [[String: Any]] ?? []).enumerated() {
            if let limits = extra["rate_limit"] as? [String: Any] {
                append(limits, prefix: "extra\(i)", title: (extra["limit_name"] as? String ?? "模型") + " · ")
            }
        }
        guard !windows.isEmpty else { throw UsageError.unavailable }
        return SubscriptionUsage(provider: .openai, plan: root["plan_type"] as? String, windows: windows, fetchedAt: now)
    }
    public static func openaiRPC(_ data: Data, now: Date = Date()) throws -> SubscriptionUsage {
        let root = try object(data)
        let all = root["rateLimitsByLimitId"] as? [String: [String: Any]]
        let fallback = root["rateLimits"] as? [String: Any]
        let groups = all?.isEmpty == false ? all! : fallback.map { ["codex": $0] } ?? [:]
        var windows: [UsageWindow] = []
        for (id, limits) in groups.sorted(by: { $0.key < $1.key }) {
            for (key, defaultLabel) in [("primary", "当前窗口"), ("secondary", "每周")] {
                guard let row = limits[key] as? [String: Any], let percent = number(row["usedPercent"]), percent.isFinite else { continue }
                let minutes = number(row["windowDurationMins"])
                let label = minutes == 300 ? "5 小时" : minutes == 10080 ? "每周" : defaultLabel
                windows.append(UsageWindow(id: id + key, label: (id == "codex" ? "" : id + " · ") + label, usedPercent: percent, resetsAt: number(row["resetsAt"]).map { Date(timeIntervalSince1970: $0) }))
            }
        }
        guard !windows.isEmpty else { throw UsageError.unavailable }
        return SubscriptionUsage(provider: .openai, plan: fallback?["planType"] as? String, windows: windows, fetchedAt: now)
    }
    public static func gemini(_ data: Data, plan: String? = nil, now: Date = Date()) throws -> SubscriptionUsage {
        let root = try object(data)
        // A model can have several quota buckets; the tightest bucket is authoritative.
        var models: [String: UsageWindow] = [:]
        for bucket in root["buckets"] as? [[String: Any]] ?? [] {
            guard let id = bucket["modelId"] as? String, let remaining = number(bucket["remainingFraction"]), remaining.isFinite else { continue }
            let window = UsageWindow(id: id, label: id, usedPercent: (1 - remaining) * 100, resetsAt: date(bucket["resetTime"] as? String))
            if models[id] == nil || window.usedPercent > models[id]!.usedPercent { models[id] = window }
        }
        guard !models.isEmpty else { throw UsageError.unavailable }
        return SubscriptionUsage(provider: .gemini, plan: plan, windows: models.values.sorted { $0.label < $1.label }, fetchedAt: now)
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageError.invalid }
        return root
    }
    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

/// Credential files are read on a utility queue. Tokens remain in memory and are never logged.
public enum SubscriptionClient {
    public static func fetch(_ provider: SubscriptionProvider, home: String = HomePaths.userHome, claudeHome: String? = nil, codexHome: String? = nil) async throws -> SubscriptionUsage {
        switch provider {
        case .claude:
            let credential: @Sendable () -> ClaudeOAuthCredential? = {
                ClaudeCredentialStore.resolve(claudeHome: claudeHome, home: home)
            }
            let quota: ClaudeQuotaSnapshot
            do { quota = try await ClaudeQuotaClient.fetch(credential: credential) }
            catch ClaudeQuotaClientError.unauthorized {
                // Expired: let Claude Code refresh its own login, then read it again.
                guard await ClaudeCLIRefresh.refresh(claudeHome: claudeHome, home: home) else { throw ClaudeQuotaClientError.unauthorized }
                quota = try await ClaudeQuotaClient.fetch(credential: credential)
            }
            let windows = quota.limits.map { UsageWindow(id: $0.kind.rawValue + ($0.scopeLabel ?? ""), label: $0.scopeLabel ?? ($0.kind == .session ? "5 小时" : "每周"), usedPercent: $0.percent, resetsAt: $0.resetsAt) }
            return SubscriptionUsage(provider: provider, plan: nil, windows: windows, fetchedAt: quota.fetchedAt)
        case .openai:
            let rootPath = codexHome ?? home + "/.codex"
            do {
                let root = try await credentials(path: rootPath + "/auth.json", provider: provider)
                guard let tokens = root["tokens"] as? [String: Any], let token = tokens["access_token"] as? String, !token.isEmpty else { throw UsageError.login(provider) }
                let data = try await request("https://chatgpt.com/backend-api/wham/usage", token: token, provider: provider, account: tokens["account_id"] as? String)
                return try UsageParser.openai(data)
            } catch { return try await CodexUsageRPC.fetch(home: rootPath) }
        case .gemini:
            let root = try await credentials(path: home + "/.gemini/oauth_creds.json", provider: provider)
            let token = try await GeminiToken.resolve(root, home: home)
            let assist = try await request("https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist", token: token, provider: provider, body: ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]])
            let info = try UsageParser.object(assist)
            let project = info["cloudaicompanionProject"] as? String
                ?? (info["cloudaicompanionProject"] as? [String: Any])?["id"] as? String
                ?? (info["cloudaicompanionProject"] as? [String: Any])?["projectId"] as? String
            let plan = ((info["paidTier"] ?? info["currentTier"]) as? [String: Any])?["name"] as? String
                ?? (info["currentTier"] as? [String: Any])?["id"] as? String
            let data = try await request("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota", token: token, provider: provider, body: project.map { ["project": $0] } ?? [:])
            return try UsageParser.gemini(data, plan: plan)
        case .antigravity:
            return try await AntigravityUsageClient.fetch(home: home)
        }
    }
    private static func credentials(path: String, provider: SubscriptionProvider) async throws -> [String: Any] {
        let data: Data? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = FileManager.default.contents(atPath: path)
                continuation.resume(returning: result)
            }
        }
        guard let data else { throw UsageError.login(provider) }
        return try UsageParser.object(data)
    }
    private static func request(_ url: String, token: String, provider: SubscriptionProvider, body: [String: Any]? = nil, account: String? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!); request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let account { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        if let body {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await ClaudeQuotaClient.session.data(for: request, delegate: NoRedirect.shared)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw UsageError.expired(provider) }
        guard (200..<300).contains(status) else { throw UsageError.http(status) }
        return data
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        static let shared = NoRedirect()
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
