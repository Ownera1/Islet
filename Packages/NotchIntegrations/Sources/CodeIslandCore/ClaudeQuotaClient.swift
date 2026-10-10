import CryptoKit
import Foundation

/// The Claude Code OAuth login, as Claude Code itself stores it.
public struct ClaudeOAuthCredential: Equatable, Sendable {
    public let accessToken: String
    public let subscriptionType: String?
    public let expiresAt: Date?

    public init(accessToken: String, subscriptionType: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.subscriptionType = subscriptionType
        self.expiresAt = expiresAt
    }
}

/// Read-only access to the Claude Code login. Never refreshes the token —
/// rotating it from here would invalidate the copy Claude Code holds, so an
/// expired token is left to Claude Code itself (`ClaudeCLIRefresh`).
public enum ClaudeCredentialStore {
    /// Keychain generic-password service Claude Code writes on macOS.
    public static let keychainService = "Claude Code-credentials"

    /// `{"claudeAiOauth":{"accessToken":…,"subscriptionType":…,"expiresAt":ms}}`
    public static func parse(_ data: Data) -> ClaudeOAuthCredential? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        var expires: Date?
        if let ms = oauth["expiresAt"] as? NSNumber {
            expires = Date(timeIntervalSince1970: ms.doubleValue / 1000)
        }
        return ClaudeOAuthCredential(
            accessToken: token,
            subscriptionType: oauth["subscriptionType"] as? String,
            expiresAt: expires
        )
    }

    /// Raw item data from the login keychain, read through `/usr/bin/security`.
    ///
    /// Claude Code stores the item with that same tool, so `security` is on
    /// the item's access list and reads it silently. `SecItemCopyMatching`
    /// from our own process would instead raise the "wants to use your
    /// confidential information" prompt — and, for an ad-hoc signed build,
    /// raise it again after every rebuild.
    public static func readKeychain(service: String = keychainService, timeout: TimeInterval = 5) -> Data? {
        runCapturingStdout(
            path: "/usr/bin/security",
            args: ["find-generic-password", "-s", service, "-w"],
            timeout: timeout
        ).flatMap(trimmingSecretOutput)
    }

    /// Set once the child has exited, so the watchdog never signals a pid
    /// that may already have been reaped and reused.
    private final class ExitFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var exited = false
        func markExited() { lock.lock(); exited = true; lock.unlock() }
        var hasExited: Bool { lock.lock(); defer { lock.unlock() }; return exited }
    }

    /// Runs `path` with `args` (no shell) and returns stdout when the child
    /// exits normally with status 0.
    ///
    /// stdout is read on the calling thread until EOF; a watchdog kills the
    /// child at the deadline, which closes the pipe and ends the read. So the
    /// deadline covers the whole run — including a `security` blocked on a
    /// keychain unlock or access dialog — and the success path never depends
    /// on another thread being scheduled.
    static func runCapturingStdout(path: String, args: [String], timeout: TimeInterval) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        let flag = ExitFlag()
        let exited = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in
            flag.markExited()
            exited.signal()
        }
        do { try proc.run() } catch { return nil }

        let pid = proc.processIdentifier
        let watchdog = DispatchWorkItem {
            guard !flag.hasExited else { return }
            kill(pid, SIGTERM)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
                if !flag.hasExited { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let data = out.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        watchdog.cancel()
        guard proc.terminationReason == .exit, proc.terminationStatus == 0 else { return nil }
        return data
    }

    /// Like `runCapturingStdout` with all output discarded, so a grandchild
    /// still holding a pipe can never keep the caller past `timeout`.
    static func runQuietly(path: String, args: [String], environment: [String: String], timeout: TimeInterval) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.environment = environment
        proc.currentDirectoryURL = FileManager.default.temporaryDirectory
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        let flag = ExitFlag()
        let exited = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in
            flag.markExited()
            exited.signal()
        }
        do { try proc.run() } catch { return }
        let pid = proc.processIdentifier
        guard exited.wait(timeout: .now() + timeout) == .timedOut else { return }
        if !flag.hasExited { kill(pid, SIGTERM) }
        if exited.wait(timeout: .now() + 1) == .timedOut, !flag.hasExited { kill(pid, SIGKILL) }
    }

    /// `-w` prints the secret followed by a newline.
    static func trimmingSecretOutput(_ data: Data) -> Data? {
        var bytes = data
        while let last = bytes.last, last == UInt8(ascii: "\n") || last == UInt8(ascii: "\r") { bytes.removeLast() }
        return bytes.isEmpty ? nil : bytes
    }

    /// File fallback (`~/.claude/.credentials.json`) used by Claude Code where
    /// no keychain is available.
    public static func readFile(claudeHome: String = ClaudeConfigPaths.configDir()) -> Data? {
        FileManager.default.contents(atPath: claudeHome + "/.credentials.json")
    }

    public static func load() -> ClaudeOAuthCredential? {
        resolve(claudeHome: ClaudeConfigPaths.configDir())
    }

    /// Keychain service Claude Code uses for a given config dir. With
    /// `$CLAUDE_CONFIG_DIR` set it appends the first 8 hex digits of the
    /// SHA-256 of that (NFC) path, so two config dirs keep separate logins.
    public static func scopedKeychainService(configDir: String) -> String {
        let digest = SHA256.hash(data: Data(configDir.precomposedStringWithCanonicalMapping.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return keychainService + "-" + String(hex.prefix(8))
    }

    /// The login for `claudeHome` (nil means Claude Code's default
    /// `~/.claude`), read-only and without refreshing anything.
    ///
    /// Sources for the configured dir come first — its keychain item and its
    /// `.credentials.json` — and only when it has none at all does the default
    /// login stand in, so a custom dir never silently reports another
    /// account's quota while it has a login of its own. Within one tier an
    /// unexpired credential beats an expired one, then the later expiry wins
    /// (Claude Code rewrites whichever copy it refreshed). An expired-only
    /// result is still returned so the caller can say "run Claude Code once"
    /// instead of "not signed in".
    public static func resolve(
        claudeHome: String?,
        home: String = NSHomeDirectory(),
        now: Date = Date(),
        keychain: (String) -> Data? = { ClaudeCredentialStore.readKeychain(service: $0) },
        file: (String) -> Data? = { FileManager.default.contents(atPath: $0) }
    ) -> ClaudeOAuthCredential? {
        for tier in sourceTiers(claudeHome: claudeHome, home: home) {
            let found = tier.compactMap { source -> ClaudeOAuthCredential? in
                switch source {
                case .keychain(let service): return keychain(service).flatMap(parse)
                case .file(let path): return file(path).flatMap(parse)
                }
            }
            if let best = found.max(by: { rank($0, now: now) < rank($1, now: now) }) { return best }
        }
        return nil
    }

    enum Source: Equatable {
        case keychain(String)
        case file(String)
    }

    /// Where to look, most specific tier first. Exposed for tests.
    static func sourceTiers(claudeHome: String?, home: String) -> [[Source]] {
        let defaultDir = ClaudeConfigPaths.canonical(home + "/.claude")
        let configured = configuredDir(claudeHome, home: home)
        let defaultTier: [Source] = [.keychain(keychainService), .file(defaultDir + "/.credentials.json")]
        guard configured != defaultDir else {
            // `CLAUDE_CONFIG_DIR=~/.claude` set explicitly still gets the hashed name.
            return [defaultTier, [.keychain(scopedKeychainService(configDir: defaultDir))]]
        }
        return [
            [.keychain(scopedKeychainService(configDir: configured)), .file(configured + "/.credentials.json")],
            defaultTier,
        ]
    }

    /// `claudeHome` resolved the way Claude Code would, nil meaning `~/.claude`.
    static func configuredDir(_ claudeHome: String?, home: String) -> String {
        claudeHome
            .flatMap { ClaudeConfigPaths.normalized($0, homeDir: home) }
            .map(ClaudeConfigPaths.canonical) ?? ClaudeConfigPaths.canonical(home + "/.claude")
    }

    /// Orders credentials: unexpired over expired, then by expiry.
    private static func rank(_ credential: ClaudeOAuthCredential, now: Date) -> (Int, Date) {
        let expiry = credential.expiresAt ?? .distantPast
        let usable = credential.expiresAt.map { $0 > now } ?? true
        return (usable ? 1 : 0, expiry)
    }
}

/// Has Claude Code refresh its own expired login, which it otherwise does
/// only when the user runs it — Claude Desktop signs in on its own and never
/// touches the CLI's keychain item. A print-mode `/status` makes the CLI
/// check (and refresh, under its own lock) its login, then is rejected
/// locally: no turn, no model call. Persistence, hooks and MCP servers are
/// off, so it leaves no transcript and no notch card. Islet itself still
/// never uses the refresh token.
public enum ClaudeCLIRefresh {
    static let cooldown: TimeInterval = 600
    static let arguments = ["-p", "/status", "--no-session-persistence", "--strict-mcp-config", "--settings", #"{"disableAllHooks":true}"#]
    private static let lock = NSLock()
    private static var lastAttempt: [String: Date] = [:]

    /// Runs the CLI for `claudeHome` at most once per `cooldown`. True when it
    /// ran, i.e. the login is worth reading again.
    public static func refresh(claudeHome: String?, home: String = NSHomeDirectory()) async -> Bool {
        let dir = ClaudeCredentialStore.configuredDir(claudeHome, home: home)
        guard let binary = binary(home: home), reserve(dir) else { return false }
        let env = environment(configDir: dir, home: home)
        // Blocks for up to the timeout, so off the cooperative pool.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                ClaudeCredentialStore.runQuietly(path: binary, args: arguments, environment: env, timeout: 15)
                continuation.resume()
            }
        }
        return true
    }

    static func binary(home: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let paths = (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { String($0) + "/claude" }
        let candidates: [String] = [home + "/.local/bin/claude", home + "/.claude/local/claude"] + paths
            + ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Built from scratch so no `ANTHROPIC_*` / `CLAUDE_CODE_*` override or
    /// XPC variable reaches the CLI; a custom config dir is passed on so the
    /// CLI refreshes that dir's own login.
    static func environment(configDir: String, home: String, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = [
            "HOME": home,
            "PATH": [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].joined(separator: ":"),
            "BROWSER": "/usr/bin/false",
            "NO_COLOR": "1",
        ]
        for key in ["USER", "LOGNAME", "TMPDIR", "LANG"] { env[key] = base[key] }
        if configDir != ClaudeConfigPaths.canonical(home + "/.claude") { env["CLAUDE_CONFIG_DIR"] = configDir }
        return env
    }

    static func reserve(_ dir: String, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let last = lastAttempt[dir], now.timeIntervalSince(last) < cooldown { return false }
        lastAttempt[dir] = now
        return true
    }
}

public enum ClaudeQuotaClientError: Error, Equatable {
    /// No Claude Code login found (not signed in, or keychain access denied).
    case noCredential
    /// Token rejected — expired or revoked; Claude Code refreshes it on next run.
    case unauthorized
    case rateLimited
    case http(Int)
    case transport(String)
    case parse
}

public enum ClaudeQuotaClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public static func request(token: String) -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CodeIsland", forHTTPHeaderField: "User-Agent")
        return req
    }

    /// Map an HTTP response to a snapshot or a typed error.
    public static func interpret(data: Data, response: URLResponse, now: Date = Date()) throws -> ClaudeQuotaSnapshot {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            do { return try ClaudeQuotaSnapshot.parse(data, fetchedAt: now) }
            catch { throw ClaudeQuotaClientError.parse }
        case 401, 403: throw ClaudeQuotaClientError.unauthorized
        case 429: throw ClaudeQuotaClientError.rateLimited
        default: throw ClaudeQuotaClientError.http(status)
        }
    }

    /// Dedicated session for the bearer-token call: ephemeral, so nothing
    /// about the request lands in the app's on-disk URL cache or cookie jar.
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Refuses every redirect, so the Authorization header is only ever sent
    /// to `endpoint`; a 3xx surfaces as `.http(3xx)` instead of being followed.
    final class RedirectRefusal: NSObject, URLSessionTaskDelegate, Sendable {
        static let shared = RedirectRefusal()

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    /// One fetch. The credential is re-read every call so a token Claude Code
    /// rotated in the meantime is picked up without any state here.
    public static func fetch(
        credential: @escaping @Sendable () -> ClaudeOAuthCredential? = { ClaudeCredentialStore.load() },
        session: URLSession = ClaudeQuotaClient.session,
        now: Date = Date()
    ) async throws -> ClaudeQuotaSnapshot {
        // Off the caller's actor: the credential read runs security(1), which
        // can block on a keychain unlock / access dialog until its timeout.
        // A GCD queue rather than a detached Task — the blocking wait must not
        // sit on a cooperative-pool thread either.
        let loaded: ClaudeOAuthCredential? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: credential()) }
        }
        guard let cred = loaded else { throw ClaudeQuotaClientError.noCredential }
        return try await fetch(using: cred, session: session, now: now)
    }

    /// The network half of `fetch`, for a credential already in hand.
    static func fetch(
        using cred: ClaudeOAuthCredential,
        session: URLSession,
        now: Date
    ) async throws -> ClaudeQuotaSnapshot {
        // Known-expired: the server would reject it anyway, so don't send it.
        if let expiresAt = cred.expiresAt, expiresAt <= now { throw ClaudeQuotaClientError.unauthorized }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(
                for: request(token: cred.accessToken),
                delegate: RedirectRefusal.shared
            )
        } catch {
            throw ClaudeQuotaClientError.transport(error.localizedDescription)
        }
        return try interpret(data: data, response: response, now: now)
    }
}
