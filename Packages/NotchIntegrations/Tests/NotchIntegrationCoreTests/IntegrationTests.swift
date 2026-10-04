import XCTest
import CodeIslandCore
@testable import NotchIntegrationCore

final class IntegrationTests: XCTestCase {
    private let bridge = "/Users/test/.boringnotch/notch-agent-bridge"
    func testAllFiveSourcesAndCapabilities() {
        XCTAssertEqual(Set(NotchAgent.allCases.map(\.rawValue)), ["pi", "codex", "claude", "zcode", "google-antigravity"])
        XCTAssertFalse(NotchAgent.antigravity.canApprove)
        XCTAssertEqual(NotchAgent.allCases.filter(\.canApprove).count, 4)
    }
    func testConfigurationPreservesCommentsAndMixedUserHooks() throws {
        let text = """
        {
          // account settings
          "model": "test-model",
          "url": "https://example.com//path",
          "hooks": {"PreToolUse": [{"matcher":"Bash", "hooks":[{"type":"command", "command":"my-own-hook"}]}]}
        }
        """
        for agent in [NotchAgent.claude, .codex, .zcode, .antigravity] {
            let result = try HookConfiguration.update(text, agent: agent, bridge: bridge, install: true)
            XCTAssertTrue(result.contains("// account settings"))
            XCTAssertTrue(result.contains("my-own-hook"))
            XCTAssertTrue(result.contains("https://example.com//path"))
            let twice = try HookConfiguration.update(result, agent: agent, bridge: bridge, install: true)
            XCTAssertEqual(result, twice, "installation must be idempotent")
            let removed = try HookConfiguration.update(result, agent: agent, bridge: bridge, install: false)
            XCTAssertFalse(removed.contains(bridge))
            XCTAssertTrue(removed.contains("my-own-hook"))
        }
    }
    func testMalformedConfigurationIsRejected() {
        XCTAssertThrowsError(try HookConfiguration.update("{ broken", agent: .claude, bridge: bridge, install: true))
        XCTAssertThrowsError(try HookConfiguration.update("{\"hooks\":[]}", agent: .codex, bridge: bridge, install: true))
    }
    func testZcodeStrictWhitelistAndDisabledMasterSwitch() throws {
        let text = try HookConfiguration.update("{\"hooks\":{\"enabled\":false,\"events\":{}}}", agent: .zcode, bridge: bridge, install: true)
        let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertEqual(hooks["enabled"] as? Bool, false)
        let events = hooks["events"] as! [String: Any]
        XCTAssertEqual(Set(events.keys), Set(NotchAgent.zcode.events))
        XCTAssertNil(events["SessionEnd"])
    }
    func testAntigravityNamedHookShapes() throws {
        let text = try HookConfiguration.update("{}", agent: .antigravity, bridge: bridge, install: true)
        let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let hooks = root["hooks"] as! [String: [[String: Any]]]
        XCTAssertNotNil(hooks["Stop"]?.first?["command"])
        XCTAssertNil(hooks["Stop"]?.first?["hooks"])
        XCTAssertNotNil(hooks["PreToolUse"]?.first?["hooks"])
        XCTAssertEqual(AntigravityHookContract.hookStdout(source: "google-antigravity", eventName: "PreToolUse"), #"{"decision":"ask"}"#)
    }
    func testLifecycleAndTaskProgressAcrossProviders() throws {
        for agent in NotchAgent.allCases {
            var sessions: [String: SessionSnapshot] = [:]
            for (event, expected) in [("SessionStart", AgentStatus.idle), ("UserPromptSubmit", .processing), ("PreToolUse", .running), ("Stop", .idle)] {
                let data = try JSONSerialization.data(withJSONObject: ["_source": agent.rawValue, "session_id": "test", "hook_event_name": event, "tool_name": "Read", "cwd": "/test"])
                let hook = HookEvent(from: data)!
                _ = reduceEvent(sessions: &sessions, event: hook, maxHistory: 20)
                XCTAssertEqual(sessions["test"]?.status, expected, "\(agent.name): \(event)")
                XCTAssertEqual(sessions["test"]?.source, agent.rawValue)
            }
        }
    }
    func testPermissionResponseAndAnswers() throws {
        let data = AgentDecision.response(allow: true, answers: ["Which?": "A"], originalInput: ["questions": [["question": "Which?", "options": [["label": "A"]]]]])
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let output = root["hookSpecificOutput"] as! [String: Any]
        let decision = output["decision"] as! [String: Any]
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertNil(decision["updatedPermissions"])
        XCTAssertNil(decision["permissionUpdates"])
        XCTAssertNotNil((decision["updatedInput"] as? [String: Any])?["questions"])
        XCTAssertEqual(((decision["updatedInput"] as? [String: Any])?["answers"] as? [String: String])?["Which?"], "A")
    }
    func testLyricsFractionsRepeatedTimestampsOffsetAndLeadIn() {
        let lines = Lyrics.parse("[offset:-100]\n[00:01.5][00:03.123]first\n[00:02.05]second\n[00:05.00]\n[ar:Artist]")
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].time, 1.4, accuracy: 0.0001)
        XCTAssertEqual(lines[1].time, 1.95, accuracy: 0.0001)
        XCTAssertEqual(lines[2].time, 3.023, accuracy: 0.0001)
        XCTAssertEqual(Lyrics.line(at: 0, in: lines), "")
        XCTAssertEqual(Lyrics.line(at: 1.5, in: lines), "first")
        XCTAssertEqual(Lyrics.line(at: 2, in: lines), "second")
        XCTAssertEqual(Lyrics.line(at: 5, in: lines), "")
    }
    func testOpenAIWindowsResetAndMissingData() throws {
        let data = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":38,"limit_window_seconds":18000,"reset_at":1800000000},"secondary_window":{"used_percent":72,"limit_window_seconds":604800}}}"#.utf8)
        let usage = try UsageParser.openai(data)
        XCTAssertEqual(usage.windows.map(\.usedPercent), [38, 72])
        XCTAssertEqual(usage.windows.map(\.label), ["5 小时", "每周"])
        XCTAssertEqual(usage.plan, "plus")
        XCTAssertNotNil(usage.windows[0].resetsAt)
        XCTAssertThrowsError(try UsageParser.openai(Data("{}".utf8)))
    }
    func testGeminiUsesTightestBucketAndNeverFakesZero() throws {
        let data = Data(#"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.8},{"modelId":"gemini-pro","remainingFraction":0.3,"resetTime":"2026-10-04T16:00:00Z"},{"modelId":"gemini-flash","remainingFraction":"0.5"},{"modelId":"unknown"}]}"#.utf8)
        let usage = try UsageParser.gemini(data)
        XCTAssertEqual(usage.windows.count, 2)
        XCTAssertEqual(usage.windows.first { $0.id == "gemini-pro" }!.usedPercent, 70, accuracy: 0.001)
        XCTAssertThrowsError(try UsageParser.gemini(Data(#"{"buckets":[]}"#.utf8)))
    }
    func testCodexRPCUsesPerModelLimits() throws {
        let data = Data(#"{"rateLimits":{"planType":"plus","primary":{"usedPercent":10}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080}}}}"#.utf8)
        let usage = try UsageParser.openaiRPC(data)
        XCTAssertEqual(usage.windows.map(\.usedPercent), [20, 40])
        XCTAssertEqual(usage.windows.map(\.label), ["5 小时", "每周"])
        XCTAssertThrowsError(try UsageParser.openaiRPC(Data("{}".utf8)))
    }
    func testUsageDTOCanCrossXPC() throws {
        let value = try UsageParser.openai(Data(#"{"rate_limit":{"primary_window":{"used_percent":12}}}"#.utf8))
        let decoded = try JSONDecoder().decode(SubscriptionUsage.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(value, decoded)
    }
    func testProvidersHaveIndependentPersistedVisibilityAndRemainingPercent() {
        let name = "notch-visibility-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SubscriptionProvider.allCases.count, 4)
        XCTAssertTrue(SubscriptionProvider.allCases.allSatisfy { $0.isVisible(in: defaults) })
        defaults.set(false, forKey: SubscriptionProvider.gemini.visibilityKey)
        XCTAssertFalse(SubscriptionProvider.gemini.isVisible(in: UserDefaults(suiteName: name)!))
        XCTAssertTrue(SubscriptionProvider.antigravity.isVisible(in: defaults))
        XCTAssertEqual(UsageWindow(id: "quota", label: "quota", usedPercent: 37).remainingPercent, 63)
    }
    func testAntigravityBucketsKeepGroupsWindowsAndMissingDataDistinct() throws {
        let data = Data(#"{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"g-5h","window":"5h","remaining_fraction":0.8,"reset_time":"2026-10-04T16:00:00Z"},{"id":"g-week","window":"weekly","remaining_fraction":0.6},{"id":"unknown"}]},{"name":"Claude and GPT models","buckets":[{"id":"third-week","window":"weekly","remaining_fraction":0.4},{"id":"disabled","disabled":true,"remaining_fraction":0}]}]}}}"#.utf8)
        let usage = try AntigravityUsageParser.summary(data, cli: true)
        XCTAssertEqual(usage.provider, .antigravity)
        XCTAssertEqual(usage.windows.map(\.label), ["Gemini · 5 小时", "Gemini · 每周", "Claude / GPT · 每周"])
        XCTAssertEqual(usage.windows[0].remainingPercent, 80, accuracy: 0.001)
        XCTAssertEqual(usage.windows[2].remainingPercent, 40, accuracy: 0.001)
        XCTAssertNotNil(usage.windows[0].resetsAt)
        XCTAssertThrowsError(try AntigravityUsageParser.summary(Data(#"{"status":"SUCCESS","command":{"name":"models","data":{"groups":[]}}}"#.utf8), cli: true))
        XCTAssertThrowsError(try AntigravityUsageParser.summary(Data(#"{"groups":[{"buckets":[{"id":"missing"}]}]}"#.utf8)))
    }
    func testAntigravityLocalSchemasSupportOneofAndLegacyModels() throws {
        let summary = try AntigravityUsageParser.summary(Data(#"{"code":0,"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"weekly","window":"weekly","remaining":{"case":"remainingFraction","value":0.55}}]}]}}"#.utf8))
        XCTAssertEqual(summary.windows.count, 1)
        XCTAssertEqual(summary.windows[0].remainingPercent, 55, accuracy: 0.001)
        let legacy = try AntigravityUsageParser.models(Data(#"{"userStatus":{"userTier":{"name":"Pro"},"cascadeModelConfigData":{"clientModelConfigs":[{"label":"Gemini Pro","modelOrAlias":{"model":"gemini-pro"},"quotaInfo":{"remainingFraction":0.9}},{"label":"unknown","modelOrAlias":{"model":"unknown"}}]}}}"#.utf8))
        XCTAssertEqual(legacy.windows.count, 1)
        XCTAssertEqual(legacy.plan, "Pro")
        XCTAssertEqual(legacy.windows[0].remainingPercent, 90, accuracy: 0.001)
        XCTAssertThrowsError(try AntigravityUsageParser.models(Data(#"{"code":401}"#.utf8)))
    }
    func testAntigravityCommandBoundsAndCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory
        let data = try await AntigravityCommand.run("/bin/echo", arguments: ["fixture"], directory: directory, home: HomePaths.userHome, timeout: 2, limit: 100)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "fixture\n")
        do {
            _ = try await AntigravityCommand.run("/bin/echo", arguments: [String(repeating: "x", count: 1000)], directory: directory, home: HomePaths.userHome, timeout: 2, limit: 10)
            XCTFail("oversized output must be rejected")
        } catch { XCTAssertTrue(error is AntigravityUsageError) }
        let task = Task { try await AntigravityCommand.run("/bin/sleep", arguments: ["5"], directory: directory, home: HomePaths.userHome, timeout: 10, limit: 10) }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancellation must stop the command") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
