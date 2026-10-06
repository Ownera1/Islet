import XCTest
@testable import CodeIslandCore
@testable import NotchIntegrationCore

/// A fake Claude Desktop Cowork store in a temp directory. Records follow the
/// shapes documented in CoworkAuditLog.swift; no identity data.
final class CoworkStoreScannerTests: XCTestCase {
    private var root: String!
    private var org: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "cowork-\(UUID().uuidString)/local-agent-mode-sessions"
        org = root + "/acct/org"
        try FileManager.default.createDirectory(atPath: org, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: root + "/skills-plugin/x", withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: (root as NSString).deletingLastPathComponent)
    }

    // MARK: Fixtures

    private static let prompt = #"{"type":"user","message":{"role":"user","content":"Tidy the folder"}}"#
    private static let toolUse = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]},"parent_tool_use_id":null}"#
    private static let permission = #"{"type":"system","subtype":"permission_request","uuid":"p1","tool_name":"Bash","tool_input":{"command":"rm old.txt"}}"#
    private static let permissionDone = #"{"type":"system","subtype":"permission_response","uuid":"p1","decision":"allow","granted":true}"#
    private static let result = #"{"type":"result","subtype":"success","is_error":false,"result":"Done."}"#

    private func writeMetadata(_ id: String, created: Date, lastActivity: Date? = nil, archived: Bool = false,
                               sessionType: String? = nil, cliSessionId: String = "cli-1") throws {
        var json: [String: Any] = [
            "sessionId": id, "cliSessionId": cliSessionId, "title": "Tidy",
            "createdAt": created.timeIntervalSince1970 * 1000, "isArchived": archived,
            "cwd": "/sessions/vm-1", "userSelectedFolders": ["/Users/test/Projects/demo"],
        ]
        if let lastActivity { json["lastActivityAt"] = lastActivity.timeIntervalSince1970 * 1000 }
        if let sessionType { json["sessionType"] = sessionType }
        try JSONSerialization.data(withJSONObject: json).write(to: URL(fileURLWithPath: "\(org!)/\(id).json"))
    }

    private func auditPath(_ id: String) -> String { "\(org!)/\(id)/audit.jsonl" }

    private func writeAudit(_ id: String, _ text: String) throws {
        try FileManager.default.createDirectory(atPath: "\(org!)/\(id)", withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: auditPath(id)))
    }

    private func appendAudit(_ id: String, _ text: String) throws {
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: auditPath(id)))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func age(_ path: String, to date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    // MARK: Tests

    func testReadsTheAuditLogIncrementallyAndKeepsPartialLines() throws {
        let now = Date()
        try writeMetadata("local_a", created: now.addingTimeInterval(-120))
        try writeAudit("local_a", Self.prompt + "\n")
        let scanner = CoworkStoreScanner(root: root)

        let first = try XCTUnwrap(scanner.scan(now: now).first)
        XCTAssertEqual(first.sessionId, "local_a")
        XCTAssertEqual(first.phase, .processing)
        XCTAssertEqual(first.cwd, "/Users/test/Projects/demo")
        XCTAssertEqual(first.cliSessionId, "cli-1")
        XCTAssertEqual(first.lastPrompt, "Tidy the folder")
        XCTAssertFalse(first.turnEnded)
        XCTAssertTrue(scanner.scan(now: now).isEmpty, "unchanged store sends nothing")

        // Half a line: nothing is parsed until its newline arrives.
        let split = Self.permission.index(Self.permission.startIndex, offsetBy: 30)
        try appendAudit("local_a", String(Self.permission[..<split]))
        XCTAssertNotEqual(scanner.scan(now: now).first?.phase, .waitingApproval)
        try appendAudit("local_a", String(Self.permission[split...]) + "\n")
        let waiting = try XCTUnwrap(scanner.scan(now: now).first)
        XCTAssertEqual(waiting.phase, .waitingApproval)
        XCTAssertEqual(waiting.currentTool, "Bash")
        XCTAssertEqual(waiting.toolDetail, "rm old.txt")

        try appendAudit("local_a", [Self.permissionDone, Self.toolUse, Self.result].joined(separator: "\n") + "\n")
        let done = try XCTUnwrap(scanner.scan(now: now).first)
        XCTAssertEqual(done.phase, .idle)
        XCTAssertEqual(done.lastResultText, "Done.")
        XCTAssertTrue(done.turnEnded, "a live turn end is announced")
        XCTAssertEqual(done.completedTurnCount, 1)
    }

    func testHistoryOnFirstSightIsNotAnnouncedAsACompletion() throws {
        let now = Date()
        try writeMetadata("local_h", created: now.addingTimeInterval(-300))
        try writeAudit("local_h", [Self.prompt, Self.result].joined(separator: "\n") + "\n")
        let update = try XCTUnwrap(CoworkStoreScanner(root: root).scan(now: now).first)
        XCTAssertEqual(update.phase, .idle)
        XCTAssertFalse(update.turnEnded)
    }

    func testASessionCreatedAfterLaunchAnnouncesItsFirstTurn() throws {
        let scanner = CoworkStoreScanner(root: root)
        let launch = Date()
        XCTAssertTrue(scanner.scan(now: launch).isEmpty)
        try writeMetadata("local_n", created: launch.addingTimeInterval(1))
        try writeAudit("local_n", [Self.prompt, Self.result].joined(separator: "\n") + "\n")
        XCTAssertEqual(scanner.scan(now: launch.addingTimeInterval(2)).first?.turnEnded, true)
    }

    func testTruncatedOrReplacedLogIsReadAgainFromTheStart() throws {
        let now = Date()
        try writeMetadata("local_t", created: now.addingTimeInterval(-60))
        try writeAudit("local_t", [Self.prompt, Self.toolUse].joined(separator: "\n") + "\n")
        let scanner = CoworkStoreScanner(root: root)
        XCTAssertEqual(scanner.scan(now: now).first?.currentTool, "Bash")

        // Truncated in place to something shorter.
        let handle = try XCTUnwrap(FileHandle(forWritingAtPath: auditPath("local_t")))
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data((Self.prompt + "\n").utf8))
        try handle.close()
        let truncated = try XCTUnwrap(scanner.scan(now: now).first)
        XCTAssertEqual(truncated.phase, .processing)
        XCTAssertNil(truncated.currentTool, "state was rebuilt, not appended to")

        // Replaced by a new file (new inode) that is longer than the old offset.
        try FileManager.default.removeItem(atPath: auditPath("local_t"))
        try writeAudit("local_t", [Self.prompt, Self.toolUse, Self.toolUse, Self.result].joined(separator: "\n") + "\n")
        let replaced = try XCTUnwrap(scanner.scan(now: now).first)
        XCTAssertEqual(replaced.phase, .idle)
        XCTAssertEqual(replaced.completedTurnCount, 1)
        XCTAssertFalse(replaced.turnEnded, "a re-read file is history, not news")
    }

    func testHiddenArchivedAndStaleSessionsAreFiltered() throws {
        let now = Date()
        try writeMetadata("local_hidden", created: now, sessionType: "agent")
        try writeAudit("local_hidden", Self.prompt + "\n")
        try writeMetadata("local_archived", created: now, archived: true)
        try writeAudit("local_archived", Self.prompt + "\n")
        try writeMetadata("local_empty", created: now)
        try writeAudit("local_empty", "")
        let old = now.addingTimeInterval(-3600)
        try writeMetadata("local_stale", created: old, lastActivity: old)
        try writeAudit("local_stale", Self.prompt + "\n")
        try age(auditPath("local_stale"), to: old)
        let scanner = CoworkStoreScanner(root: root)
        XCTAssertTrue(scanner.scan(now: now).isEmpty)
        XCTAssertTrue(scanner.trackedSessionIds.isEmpty)

        // A stale session that becomes active again is picked up.
        try appendAudit("local_stale", Self.toolUse + "\n")
        XCTAssertEqual(scanner.scan(now: Date()).map(\.sessionId), ["local_stale"])
    }

    func testArchivingOrDeletingATrackedSessionRemovesItsCard() throws {
        let now = Date()
        try writeMetadata("local_r", created: now)
        try writeAudit("local_r", Self.prompt + "\n")
        try writeMetadata("local_d", created: now)
        try writeAudit("local_d", Self.prompt + "\n")
        let scanner = CoworkStoreScanner(root: root)
        XCTAssertEqual(Set(scanner.scan(now: now).map(\.sessionId)), ["local_r", "local_d"])

        try writeMetadata("local_r", created: now, archived: true)
        try age("\(org!)/local_r.json", to: now.addingTimeInterval(5))
        try FileManager.default.removeItem(atPath: "\(org!)/local_d.json")
        let updates = scanner.scan(now: now)
        XCTAssertEqual(Set(updates.filter(\.removed).map(\.sessionId)), ["local_r", "local_d"])
        XCTAssertTrue(scanner.trackedSessionIds.isEmpty)
    }

    // MARK: Mapping into the island

    func testUpdatesMapToDisplayOnlySessions() throws {
        var sessions: [String: SessionSnapshot] = [:]
        var update = CoworkSessionUpdate(sessionId: "local_m", title: "Tidy", cwd: "/Users/test/demo",
                                         phase: .waitingApproval, currentTool: "Bash", toolDetail: "rm old.txt",
                                         cliSessionId: "cli-9")
        XCTAssertEqual(ClaudeDesktop.apply(update, to: &sessions), .updated(turnEnded: false))
        let card = try XCTUnwrap(sessions["local_m"])
        XCTAssertEqual(card.source, "claude")
        XCTAssertEqual(card.status, .waitingApproval)
        XCTAssertEqual(card.termBundleId, ClaudeDesktop.bundleId)
        XCTAssertEqual(ClaudeDesktop.hostLabel(id: "local_m", snapshot: card), "Claude 桌面版 · Cowork")
        XCTAssertEqual(ClaudeDesktop.deepLink(id: "local_m", snapshot: card)?.absoluteString, "claude://claude.ai/cowork/local_m")
        XCTAssertEqual(DisplayOnlyWait.kind(status: card.status, islandHoldsRequest: false), .approval)

        update.phase = .idle
        update.lastResultText = "Done."
        update.turnEnded = true
        XCTAssertEqual(ClaudeDesktop.apply(update, to: &sessions), .updated(turnEnded: true))
        XCTAssertNil(sessions["local_m"]?.currentTool)
        XCTAssertEqual(sessions["local_m"]?.lastAssistantMessage, "Done.")

        update.lastTurnInterrupted = true
        XCTAssertEqual(ClaudeDesktop.apply(update, to: &sessions), .updated(turnEnded: false), "a stopped turn is not a completion")
        XCTAssertEqual(ClaudeDesktop.apply(.removal(sessionId: "local_m"), to: &sessions), .removed)
        XCTAssertNil(sessions["local_m"])
    }

    func testHookSessionForTheSameConversationWins() {
        var sessions: [String: SessionSnapshot] = ["cli-9": SessionSnapshot()]
        let update = CoworkSessionUpdate(sessionId: "local_s", phase: .processing, cliSessionId: "cli-9")
        XCTAssertEqual(ClaudeDesktop.apply(update, to: &sessions), .shadowed)
        XCTAssertNil(sessions["local_s"])
        XCTAssertEqual(ClaudeDesktop.apply(CoworkSessionUpdate(sessionId: "not-cowork"), to: &sessions), .ignored)
    }

    func testUpdatesRoundTripAsJSON() throws {
        let update = CoworkSessionUpdate(sessionId: "local_j", title: "T", phase: .waitingQuestion,
                                         lastActivity: Date(timeIntervalSince1970: 1_800_000_000), turnEnded: true)
        let decoded = try JSONDecoder().decode(CoworkSessionUpdate.self, from: JSONEncoder().encode(update))
        XCTAssertEqual(decoded, update)
    }
}
