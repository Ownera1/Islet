import XCTest
@testable import CodeIslandCore

final class ClaudeQuotaTests: XCTestCase {
    /// Trimmed copy of a real `/api/oauth/usage` response (Max plan, 2026-09-03).
    static let fixture = """
    {"five_hour":{"utilization":3.0,"resets_at":"2026-09-03T19:50:00.017533+00:00"},
     "seven_day":{"utilization":30.0,"resets_at":"2026-09-04T00:00:00.017553+00:00"},
     "seven_day_opus":null,
     "limits":[
       {"kind":"session","group":"session","percent":3,"severity":"normal","resets_at":"2026-09-03T19:50:00.017533+00:00","scope":null,"is_active":false},
       {"kind":"weekly_all","group":"weekly","percent":30,"severity":"normal","resets_at":"2026-09-04T00:00:00.017553+00:00","scope":null,"is_active":false},
       {"kind":"weekly_scoped","group":"weekly","percent":48,"severity":"normal","resets_at":"2026-09-04T00:00:00.017765+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true},
       {"kind":"something_new","percent":1}
     ]}
    """.data(using: .utf8)!

    private let now = ISO8601DateFormatter().date(from: "2026-09-03T15:00:00Z")!

    func testParsesNormalisedLimitsAndIgnoresUnknownKinds() throws {
        let snap = try ClaudeQuotaSnapshot.parse(Self.fixture, fetchedAt: now)
        XCTAssertEqual(snap.limits.count, 3)
        XCTAssertEqual(snap.ordered.map(\.kind), [.session, .weeklyAll, .weeklyScoped])
        let scoped = try XCTUnwrap(snap.limit(.weeklyScoped))
        XCTAssertEqual(scoped.percent, 48)
        XCTAssertEqual(scoped.scopeLabel, "Fable")
        let resets = try XCTUnwrap(snap.limit(.session)?.resetsAt)
        XCTAssertEqual(resets.timeIntervalSince1970, ISO8601DateFormatter().date(from: "2026-09-03T19:50:00Z")!.timeIntervalSince1970, accuracy: 0.1)
    }

    func testFallsBackToLegacyFieldsWhenLimitsMissing() throws {
        let json = """
        {"five_hour":{"utilization":12.5,"resets_at":"2026-09-03T19:50:00Z"},
         "seven_day":{"utilization":70,"resets_at":null},
         "seven_day_sonnet":{"utilization":5,"resets_at":null}}
        """.data(using: .utf8)!
        let snap = try ClaudeQuotaSnapshot.parse(json, fetchedAt: now)
        XCTAssertEqual(snap.limit(.session)?.percent, 12.5)
        XCTAssertEqual(snap.limit(.weeklyAll)?.percent, 70)
        XCTAssertNil(snap.limit(.weeklyAll)?.resetsAt)
        XCTAssertEqual(snap.limit(.weeklyScoped)?.scopeLabel, "Sonnet")
    }

    func testParseRejectsGarbage() {
        XCTAssertThrowsError(try ClaudeQuotaSnapshot.parse(Data("nope".utf8)))
        XCTAssertThrowsError(try ClaudeQuotaSnapshot.parse(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? ClaudeQuotaSnapshot.ParseError, .noLimits)
        }
    }

    // MARK: formatting + levels

    func testCountdownFormats() {
        XCTAssertEqual(ClaudeQuotaFormat.countdown(until: now.addingTimeInterval(30), now: now), "1m")
        XCTAssertEqual(ClaudeQuotaFormat.countdown(until: now.addingTimeInterval(45 * 60), now: now), "45m")
        XCTAssertEqual(ClaudeQuotaFormat.countdown(until: now.addingTimeInterval(80 * 60), now: now), "1h20m")
        XCTAssertEqual(ClaudeQuotaFormat.countdown(until: now.addingTimeInterval(3 * 3600), now: now), "3h")
        XCTAssertEqual(ClaudeQuotaFormat.countdown(until: now.addingTimeInterval(2 * 86_400 + 4 * 3600), now: now), "2d 4h")
        XCTAssertEqual(ClaudeQuotaFormat.countdown(until: now.addingTimeInterval(7 * 86_400), now: now), "7d")
        XCTAssertNil(ClaudeQuotaFormat.countdown(until: now.addingTimeInterval(-1), now: now))
        XCTAssertEqual(ClaudeQuotaFormat.percent(47.6), "48%")
    }

    func testSeverityLevels() {
        XCTAssertEqual(ClaudeQuotaLimit(kind: .session, percent: 10, severity: "normal").level, .normal)
        XCTAssertEqual(ClaudeQuotaLimit(kind: .session, percent: 10, severity: "warning").level, .warning)
        XCTAssertEqual(ClaudeQuotaLimit(kind: .session, percent: 10, severity: "exceeded").level, .critical)
        XCTAssertEqual(ClaudeQuotaLimit(kind: .session, percent: 100, severity: "normal").level, .critical)
    }

    // MARK: credential + client

    func testCredentialParse() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"r","expiresAt":1788472382000,"subscriptionType":"max"}}
        """.data(using: .utf8)!
        let cred = try XCTUnwrap(ClaudeCredentialStore.parse(json))
        XCTAssertEqual(cred.accessToken, "sk-ant-oat01-abc")
        XCTAssertEqual(cred.subscriptionType, "max")
        XCTAssertEqual(cred.expiresAt?.timeIntervalSince1970, 1_788_472_382)
        XCTAssertNil(ClaudeCredentialStore.parse(Data("{\"claudeAiOauth\":{\"accessToken\":\"\"}}".utf8)))
    }

    func testRequestCarriesBearerAndBetaHeader() {
        let req = ClaudeQuotaClient.request(token: "tok")
        XCTAssertEqual(req.url, ClaudeQuotaClient.endpoint)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
    }

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: ClaudeQuotaClient.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testInterpretMapsStatusCodes() {
        XCTAssertNoThrow(try ClaudeQuotaClient.interpret(data: Self.fixture, response: response(200)))
        func err(_ status: Int, _ data: Data = Data()) -> ClaudeQuotaClientError? {
            do { _ = try ClaudeQuotaClient.interpret(data: data, response: response(status)); return nil }
            catch { return error as? ClaudeQuotaClientError }
        }
        XCTAssertEqual(err(401), .unauthorized)
        XCTAssertEqual(err(403), .unauthorized)
        XCTAssertEqual(err(429), .rateLimited)
        XCTAssertEqual(err(503), .http(503))
        XCTAssertEqual(err(200, Data("{}".utf8)), .parse)
    }

    // MARK: token hygiene

    func testRequestAndSessionKeepTheTokenOffDisk() {
        XCTAssertEqual(ClaudeQuotaClient.request(token: "tok").cachePolicy, .reloadIgnoringLocalCacheData)
        let config = ClaudeQuotaClient.session.configuration
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
    }

    func testRedirectsAreNeverFollowed() async {
        // Never resumed — no network.
        let task = ClaudeQuotaClient.session.dataTask(with: ClaudeQuotaClient.endpoint)
        let redirect = HTTPURLResponse(url: ClaudeQuotaClient.endpoint, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": "https://example.com/"])!
        let next = await ClaudeQuotaClient.RedirectRefusal.shared.urlSession(
            ClaudeQuotaClient.session, task: task,
            willPerformHTTPRedirection: redirect,
            newRequest: URLRequest(url: URL(string: "https://example.com/")!)
        )
        XCTAssertNil(next)
    }

    /// Counts requests that reach the wire; answers every one with a 500.
    private final class CountingProtocol: URLProtocol {
        nonisolated(unsafe) static var count = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.count += 1
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func testKnownExpiredTokenIsNeverSent() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingProtocol.self]
        let session = URLSession(configuration: config)
        CountingProtocol.count = 0
        // `fetch(using:)` skips the utility-QoS credential hop, which a loaded
        // machine can starve for tens of seconds.
        let expired = ClaudeOAuthCredential(accessToken: "tok", expiresAt: now.addingTimeInterval(-60))
        do {
            _ = try await ClaudeQuotaClient.fetch(using: expired, session: session, now: now)
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? ClaudeQuotaClientError, .unauthorized)
        }
        XCTAssertEqual(CountingProtocol.count, 0)
        // A live token does go out (and the stubbed 500 maps through).
        let live = ClaudeOAuthCredential(accessToken: "tok", expiresAt: now.addingTimeInterval(3600))
        do {
            _ = try await ClaudeQuotaClient.fetch(using: live, session: session, now: now)
            XCTFail("expected http(500)")
        } catch {
            XCTAssertEqual(error as? ClaudeQuotaClientError, .http(500))
        }
        XCTAssertEqual(CountingProtocol.count, 1)
    }

    // MARK: Credential resolution

    private func credentialJSON(_ token: String, expiresAt: Date?) -> Data {
        let expiry = expiresAt.map { ",\"expiresAt\":\(Int64($0.timeIntervalSince1970 * 1000))" } ?? ""
        return Data("{\"claudeAiOauth\":{\"accessToken\":\"\(token)\"\(expiry)}}".utf8)
    }

    func testScopedKeychainServiceHashesTheConfigDir() {
        let service = ClaudeCredentialStore.scopedKeychainService(configDir: "/Users/test/.claude-work")
        XCTAssertTrue(service.hasPrefix("Claude Code-credentials-"))
        XCTAssertEqual(service.count, "Claude Code-credentials-".count + 8)
        XCTAssertNotEqual(service, ClaudeCredentialStore.scopedKeychainService(configDir: "/Users/test/.claude"))
        // NFC and NFD spellings of one path name the same item.
        XCTAssertEqual(
            ClaudeCredentialStore.scopedKeychainService(configDir: "/Users/te\u{0301}st/.claude"),
            ClaudeCredentialStore.scopedKeychainService(configDir: "/Users/t\u{00E9}st/.claude")
        )
    }

    func testCLIRefreshIsThrottledPerConfigDirAndScrubsTheEnvironment() {
        let dir = "/tmp/claude-refresh-test-" + UUID().uuidString
        XCTAssertTrue(ClaudeCLIRefresh.reserve(dir, now: now))
        XCTAssertFalse(ClaudeCLIRefresh.reserve(dir, now: now.addingTimeInterval(ClaudeCLIRefresh.cooldown - 1)))
        XCTAssertTrue(ClaudeCLIRefresh.reserve(dir + "-other", now: now))
        XCTAssertTrue(ClaudeCLIRefresh.reserve(dir, now: now.addingTimeInterval(ClaudeCLIRefresh.cooldown)))

        let base = ["USER": "test", "ANTHROPIC_API_KEY": "x", "CLAUDE_CODE_OAUTH_TOKEN": "x", "XPC_SERVICE_NAME": "x"]
        let plain = ClaudeCLIRefresh.environment(configDir: "/Users/test/.claude", home: "/Users/test", base: base)
        XCTAssertEqual(plain["HOME"], "/Users/test")
        XCTAssertEqual(plain["USER"], "test")
        XCTAssertNil(plain["CLAUDE_CONFIG_DIR"])
        XCTAssertTrue(plain.keys.allSatisfy { !$0.hasPrefix("ANTHROPIC_") && !$0.hasPrefix("CLAUDE_CODE_") && !$0.hasPrefix("XPC_") })
        let custom = ClaudeCLIRefresh.environment(configDir: "/Users/test/work", home: "/Users/test", base: base)
        XCTAssertEqual(custom["CLAUDE_CONFIG_DIR"], "/Users/test/work")
    }

    func testSourceTiersPutTheConfiguredDirFirst() {
        let home = "/Users/test"
        let scoped = ClaudeCredentialStore.scopedKeychainService(configDir: "/Users/test/work")
        XCTAssertEqual(ClaudeCredentialStore.sourceTiers(claudeHome: "~/work/", home: home), [
            [.keychain(scoped), .file("/Users/test/work/.credentials.json")],
            [.keychain("Claude Code-credentials"), .file("/Users/test/.claude/.credentials.json")],
        ])
        for dir in [nil, "/Users/test/.claude", "~/.claude", "  "] as [String?] {
            XCTAssertEqual(ClaudeCredentialStore.sourceTiers(claudeHome: dir, home: home).first,
                           [.keychain("Claude Code-credentials"), .file("/Users/test/.claude/.credentials.json")])
        }
    }

    func testResolvePrefersTheConfiguredDirOverTheDefaultLogin() {
        let home = "/Users/test"
        let scoped = ClaudeCredentialStore.scopedKeychainService(configDir: "/Users/test/work")
        let later = now.addingTimeInterval(7200)
        let keychain: [String: Data] = [
            scoped: credentialJSON("work", expiresAt: now.addingTimeInterval(600)),
            "Claude Code-credentials": credentialJSON("default", expiresAt: later),
        ]
        let resolved = ClaudeCredentialStore.resolve(claudeHome: "/Users/test/work", home: home, now: now,
                                                     keychain: { keychain[$0] }, file: { _ in nil })
        XCTAssertEqual(resolved?.accessToken, "work")
        // No login of its own: the default one stands in.
        let fallback = ClaudeCredentialStore.resolve(claudeHome: "/Users/test/other", home: home, now: now,
                                                     keychain: { keychain[$0] }, file: { _ in nil })
        XCTAssertEqual(fallback?.accessToken, "default")
    }

    func testResolvePicksTheFreshestUsableCopyWithinATier() {
        let files: [String: Data] = [
            "/Users/test/.claude/.credentials.json": credentialJSON("file", expiresAt: now.addingTimeInterval(3600)),
        ]
        let expiredKeychain = { (_: String) -> Data? in self.credentialJSON("stale", expiresAt: self.now.addingTimeInterval(-60)) }
        XCTAssertEqual(ClaudeCredentialStore.resolve(claudeHome: nil, home: "/Users/test", now: now,
                                                     keychain: expiredKeychain, file: { files[$0] })?.accessToken, "file")
        // Only expired copies: still returned, so the caller reports "expired" rather than "not signed in".
        XCTAssertEqual(ClaudeCredentialStore.resolve(claudeHome: nil, home: "/Users/test", now: now,
                                                     keychain: expiredKeychain, file: { _ in nil })?.accessToken, "stale")
        XCTAssertNil(ClaudeCredentialStore.resolve(claudeHome: nil, home: "/Users/test", now: now,
                                                   keychain: { _ in nil }, file: { _ in nil }))
    }

    // MARK: security(1) runner

    func testRunnerReturnsStdoutAndSecretIsTrimmed() throws {
        let out = try XCTUnwrap(ClaudeCredentialStore.runCapturingStdout(path: "/bin/echo", args: ["secret"], timeout: 5))
        XCTAssertEqual(ClaudeCredentialStore.trimmingSecretOutput(out), Data("secret".utf8))
        XCTAssertNil(ClaudeCredentialStore.trimmingSecretOutput(Data("\n".utf8)))
        XCTAssertNil(ClaudeCredentialStore.runCapturingStdout(path: "/usr/bin/false", args: [], timeout: 5))
        // Larger than a pipe buffer: must not wedge the child.
        let big = ClaudeCredentialStore.runCapturingStdout(
            path: "/bin/dd", args: ["if=/dev/zero", "bs=1024", "count=200"], timeout: 5)
        XCTAssertEqual(big?.count, 200 * 1024)
    }

    func testRunnerDeadlineCoversAChildThatNeverExits() {
        // A security(1) waiting on a keychain dialog looks like this: alive,
        // stdout open, nothing written. The deadline must still fire.
        let started = Date()
        XCTAssertNil(ClaudeCredentialStore.runCapturingStdout(path: "/bin/sleep", args: ["30"], timeout: 0.3))
        // Generous bound for a loaded CI box; the point is "not 30s".
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
