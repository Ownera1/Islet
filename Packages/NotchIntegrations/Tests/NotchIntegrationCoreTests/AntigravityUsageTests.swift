import XCTest
@testable import NotchIntegrationCore

final class AntigravityUsageTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notch-agy-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func executable(_ url: URL, script: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(("#!/bin/sh\n" + script).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func testDetectsUserInstallAndAbsolutePATHWithoutLaunchingCLI() throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appendingPathComponent("custom/agy")
        try executable(custom, script: "exit 99\n")
        XCTAssertEqual(AntigravityUsageClient.cliBinary(home: home.path, environment: ["PATH": custom.deletingLastPathComponent().path]), custom.path)
        let local = home.appendingPathComponent(".local/bin/agy")
        try executable(local, script: "exit 99\n")
        XCTAssertEqual(AntigravityUsageClient.cliBinary(home: home.path, environment: ["PATH": custom.deletingLastPathComponent().path]), local.path)
        try FileManager.default.removeItem(at: local)
        let bundled = home.appendingPathComponent(".gemini/antigravity-cli/bin/agy")
        try executable(bundled, script: "exit 99\n")
        XCTAssertEqual(AntigravityUsageClient.cliBinary(home: home.path, environment: [:]), bundled.path)
    }

    func testUsageVersionGateRejectsOldMalformedAndPrereleaseVersions() {
        for version in ["1.1.11", "1.2.16", "2.0.0", "v1.2.16", "agy 1.2.16", "1.2.16+build.1"] {
            XCTAssertTrue(AntigravityUsageClient.supportsUsage(version: version), version)
        }
        for version in ["1.1.10", "1.0.99", "0.9.99", "1.1", "1.2.16-beta", "1.2.x.16", "unknown", ""] {
            XCTAssertFalse(AntigravityUsageClient.supportsUsage(version: version), version)
        }
    }

    func testBackgroundCommandBlocksOpenAndInheritedAppLaunch() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent("FakeLogin.app/Contents/MacOS/login")
        let marker = home.appendingPathComponent("launched")
        try executable(app, script: #"touch "$1""# + "\n")
        let probe = home.appendingPathComponent("probe")
        try executable(probe, script: #"""
        [ "$CI" = 1 ] && [ "$TERM" = dumb ] && [ "$BROWSER" = /usr/bin/false ] || exit 1
        if /usr/bin/open --help >/dev/null 2>&1; then exit 2; fi
        if "$1" "$2" >/dev/null 2>&1; then exit 3; fi
        printf 'blocked\n'
        """#)
        let result = try await AntigravityCommand.run(probe.path, arguments: [app.path, marker.path], directory: home, home: home.path, timeout: 3, limit: 100)
        XCTAssertEqual(String(decoding: result, as: UTF8.self), "blocked\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testCLIFetchReadsSharedQuotaAndReportsCLISource() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = home.appendingPathComponent(".local/bin/agy")
        try executable(cli, script: #"""
        if [ "$1" = --version ]; then printf '1.2.16\n'; exit 0; fi
        [ "$1" = -p ] && [ "$2" = /usage ] && [ "$3" = --output-format ] && [ "$4" = json ] || exit 1
        printf '%s\n' '{"status":"SUCCESS","command":{"name":"usage","data":{"planName":"Pro","groups":[{"name":"Gemini","buckets":[{"id":"weekly","window":"weekly","remainingFraction":0.75}]}]}}}'
        """#)
        let usage = try await AntigravityUsageClient.fetchCLI(home: home.path)
        XCTAssertEqual(usage.provider, .antigravity)
        XCTAssertEqual(usage.source, .antigravityCLI)
        XCTAssertEqual(usage.plan, "Pro")
        XCTAssertEqual(usage.windows.first?.remainingPercent, 75)
        XCTAssertEqual(try JSONDecoder().decode(SubscriptionUsage.self, from: JSONEncoder().encode(usage)), usage)
    }

    func testCLIFetchReturnsManualLoginStateWithoutOpeningBrowser() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        try executable(home.appendingPathComponent(".local/bin/agy"), script: #"""
        if [ "$1" = --version ]; then printf '1.2.16\n'; exit 0; fi
        if /usr/bin/open --help >/dev/null 2>&1; then printf 'unsafe\n'; exit 0; fi
        printf 'authentication required\n' >&2
        exit 1
        """#)
        do {
            _ = try await AntigravityUsageClient.fetchCLI(home: home.path)
            XCTFail("Unauthenticated CLI must return a manual login state")
        } catch AntigravityUsageError.authenticationRequired {
            // Expected. The fixture could not launch open, and no OAuth URL was submitted.
        }
    }

    func testOldCLINeverReceivesUsageCommand() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        try executable(home.appendingPathComponent(".local/bin/agy"), script: #"""
        if [ "$1" = --version ]; then printf '1.1.10\n'; exit 0; fi
        touch "$HOME/usage-invoked"
        exit 1
        """#)
        do {
            _ = try await AntigravityUsageClient.fetchCLI(home: home.path)
            XCTFail("Old CLI must be rejected before /usage")
        } catch AntigravityUsageError.unsupportedCLI {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("usage-invoked").path))
    }

    func testInteractiveOAuthInPrivateLogStopsBeforeTimeout() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let diagnostics = home.appendingPathComponent("usage.log")
        let probe = home.appendingPathComponent("probe")
        try executable(probe, script: #"""
        printf 'Print mode: triggering interactive OAuth\n' > "$1"
        exec /bin/sleep 10
        """#)
        let start = Date()
        do {
            _ = try await AntigravityCommand.run(probe.path, arguments: [diagnostics.path], directory: home, home: home.path, timeout: 5, limit: 100, diagnosticsFile: diagnostics)
            XCTFail("Interactive OAuth must stop without waiting for user input")
        } catch AntigravityUsageError.authenticationRequired {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testSilentAuthStartupMessageDoesNotMisclassifyNetworkTimeout() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let diagnostics = home.appendingPathComponent("usage.log")
        let probe = home.appendingPathComponent("probe")
        try executable(probe, script: #"""
        printf 'Print mode: not authenticated, trying silent auth\nChainedAuth: authenticated via keyring\n' > "$1"
        exec /bin/sleep 10
        """#)
        do {
            _ = try await AntigravityCommand.run(probe.path, arguments: [diagnostics.path], directory: home, home: home.path, timeout: 0.5, limit: 100, diagnosticsFile: diagnostics)
            XCTFail("A stalled quota request must time out")
        } catch AntigravityUsageError.timedOut {}
    }

    func testKeychainAccessFailureIsNotReportedAsLoggedOut() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let diagnostics = home.appendingPathComponent("usage.log")
        let probe = home.appendingPathComponent("probe")
        try executable(probe, script: #"""
        printf 'Failed to load stored token from keyring, falling back to file: exit status 36\nPrint mode: silent auth failed\nStarting OAuth authentication flow\n' > "$1"
        exec /bin/sleep 10
        """#)
        let start = Date()
        do {
            _ = try await AntigravityCommand.run(probe.path, arguments: [diagnostics.path], directory: home, home: home.path, timeout: 5, limit: 100, diagnosticsFile: diagnostics)
            XCTFail("Keychain access failure must stop before interactive OAuth")
        } catch AntigravityUsageError.credentialAccessDenied {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testSuccessfulCredentialFallbackStillReturnsQuotaAfterKeychainFailure() async throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let diagnostics = home.appendingPathComponent("usage.log")
        let probe = home.appendingPathComponent("probe")
        try executable(probe, script: #"""
        printf 'Failed to load stored token from keyring, falling back to file: exit status 36\nPrint mode: silent auth succeeded\n' > "$1"
        printf 'quota-report\n'
        """#)
        let report = try await AntigravityCommand.run(probe.path, arguments: [diagnostics.path], directory: home, home: home.path, timeout: 3, limit: 100, diagnosticsFile: diagnostics)
        XCTAssertEqual(String(decoding: report, as: UTF8.self), "quota-report\n")
    }

    func testKeychainFailureReminderRecommendsRestartInsteadOfLoggingInAgain() async throws {
        do {
            _ = try await AntigravityUsageClient.fetch(cli: {
                throw AntigravityUsageError.credentialAccessDenied
            }, application: {
                throw UsageError.login(.antigravity)
            })
            XCTFail("Unavailable credentials must return a specific reminder")
        } catch let error as AntigravitySharedUsageError {
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("无法访问已保存的登录凭据（钥匙串）"))
            XCTAssertTrue(text.contains("请重启 Islet 后重试"))
            XCTAssertFalse(text.contains("未登录或登录已失效"))
            XCTAssertFalse(text.contains("请手动运行 agy 登录"))
            XCTAssertFalse(text.contains("https://"))
        }
    }

    func testSharedQuotaUsesCLIWithoutReadingOrAddingApplicationQuota() async throws {
        let calls = SourceCalls()
        let cli = snapshot(usedPercent: 20)
        let app = snapshot(usedPercent: 75)
        let usage = try await AntigravityUsageClient.fetch(cli: {
            await calls.record("cli")
            return cli
        }, application: {
            await calls.record("app")
            return app
        })
        let recorded = await calls.values
        XCTAssertEqual(recorded, ["cli"])
        XCTAssertEqual(usage.provider, .antigravity)
        XCTAssertEqual(usage.source, .antigravityCLI)
        XCTAssertEqual(usage.windows, cli.windows)
        XCTAssertEqual(usage.fetchedAt, cli.fetchedAt)
        XCTAssertEqual(usage.plan, cli.plan)
    }

    func testSharedQuotaTriesApplicationAfterEachCLIFailure() async throws {
        let failures: [Error] = [
            AntigravityUsageError.cliNotInstalled,
            AntigravityUsageError.unsupportedCLI,
            AntigravityUsageError.authenticationRequired,
            AntigravityUsageError.credentialAccessDenied,
            AntigravityUsageError.timedOut,
            AntigravityUsageError.backgroundUnavailable,
            UsageError.invalid
        ]
        let app = snapshot(usedPercent: 35)
        for failure in failures {
            let calls = SourceCalls()
            let usage = try await AntigravityUsageClient.fetch(cli: {
                await calls.record("cli")
                throw failure
            }, application: {
                await calls.record("app")
                return app
            })
            let recorded = await calls.values
            XCTAssertEqual(recorded, ["cli", "app"])
            XCTAssertEqual(usage.source, .antigravityApp)
            XCTAssertEqual(usage.windows, app.windows)
            XCTAssertEqual(usage.fetchedAt, app.fetchedAt)
        }
    }

    func testEmptyCLIQuotaFallsBackWithoutInventingZeroUsage() async throws {
        let app = snapshot(usedPercent: 80)
        let usage = try await AntigravityUsageClient.fetch(cli: {
            SubscriptionUsage(provider: .antigravity, plan: nil, windows: [])
        }, application: { app })
        XCTAssertEqual(usage.source, .antigravityApp)
        XCTAssertEqual(usage.windows, app.windows)
    }

    func testBothSourcesFailWithOnlySanitizedManualLoginReminder() async throws {
        let calls = SourceCalls()
        do {
            _ = try await AntigravityUsageClient.fetch(cli: {
                await calls.record("cli")
                throw AntigravityUsageError.authenticationRequired
            }, application: {
                await calls.record("app")
                throw UsageError.login(.antigravity)
            })
            XCTFail("No source means no quota snapshot")
        } catch let error as AntigravitySharedUsageError {
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("agy CLI：未登录或登录已失效"))
            XCTAssertTrue(text.contains("Antigravity：应用未运行或未登录"))
            XCTAssertTrue(text.contains("请手动运行 agy 登录"))
            XCTAssertFalse(text.contains("https://"))
        }
        let recorded = await calls.values
        XCTAssertEqual(recorded, ["cli", "app"])
    }

    func testCancelledCLIDoesNotStartApplicationFallback() async throws {
        let calls = SourceCalls()
        let app = snapshot(usedPercent: 10)
        do {
            _ = try await AntigravityUsageClient.fetch(cli: {
                await calls.record("cli")
                throw CancellationError()
            }, application: {
                await calls.record("app")
                return app
            })
            XCTFail("Cancellation must remain cancellation")
        } catch is CancellationError {}
        let recorded = await calls.values
        XCTAssertEqual(recorded, ["cli"])
    }

    func testXPCDecodesOlderQuotaWithoutSourceMetadata() throws {
        let old = Data(#"{"provider":"antigravity","plan":null,"windows":[{"id":"weekly","label":"每周","usedPercent":12,"resetsAt":null}],"fetchedAt":0}"#.utf8)
        let usage = try JSONDecoder().decode(SubscriptionUsage.self, from: old)
        XCTAssertEqual(usage.provider, .antigravity)
        XCTAssertNil(usage.source)
        XCTAssertEqual(usage.windows.first?.usedPercent, 12)
    }

    private func snapshot(usedPercent: Double) -> SubscriptionUsage {
        SubscriptionUsage(
            provider: .antigravity, plan: "Pro",
            windows: [UsageWindow(id: "weekly", label: "Gemini · 每周", usedPercent: usedPercent)],
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private actor SourceCalls {
    private(set) var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
