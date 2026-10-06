import CodeIslandCore
import Foundation
import NotchIntegrationCore

@main struct AgentCompletionTests {
    @MainActor static func main() throws {
        let suite = "Islet.AgentCompletionTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let monitor = AgentMonitor(preferences: preferences)
        monitor.start()
        defer { monitor.stop() }
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: .notchAgentNeedsAttention,
            object: nil, queue: nil) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        func event(_ source: NotchAgent, _ name: String, id: String = "test", extra: [String: Any] = [:]) throws {
            var payload: [String: Any] = ["_source": source.rawValue, "session_id": id, "hook_event_name": name]
            payload.merge(extra) { _, new in new }
            IntegrationServiceClient.shared.onEvent?(try JSONSerialization.data(withJSONObject: payload), UUID())
        }
        func transcript(_ payload: [String: Any]) throws {
            IntegrationServiceClient.shared.onTranscript?(try JSONSerialization.data(withJSONObject: payload))
        }

        for agent in NotchAgent.allCases {
            let before = notifications
            try event(agent, "SessionStart")
            precondition(notifications == before, "Session discovery must not expand")
            try event(agent, "UserPromptSubmit")
            try event(agent, "Stop", extra: ["last_assistant_message": "done"])
            precondition(notifications == before + 1 && monitor.selectedAgent == agent
                && monitor.selectedSessionID == "test" && BoringViewCoordinator.shared.currentView == .agents)
            try transcript(["sessionID": "test", "turnStatus": "idle", "hasActivity": true, "reply": "done"])
            precondition(notifications == before + 1, "Hook and transcript completion must expand only once")
            if agent != .antigravity {
                try event(agent, "Stop")
                precondition(notifications == before + 1, "Duplicate stop must not reopen")
            }
            try event(agent, "UserPromptSubmit")
            try event(agent, "Stop")
            precondition(notifications == before + 2, "A second turn must expand again")
        }
        let before = notifications
        try event(.codex, "SessionStart")
        try event(.codex, "UserPromptSubmit")
        try transcript(["sessionID": "test", "turnStatus": "idle", "hasActivity": false, "isReplay": true])
        precondition(notifications == before, "Initial transcript history must not expand")
        try transcript(["sessionID": "test", "turnStatus": "processing", "hasActivity": true])
        try transcript(["sessionID": "test", "turnStatus": "idle", "hasActivity": true, "reply": "finished"])
        precondition(notifications == before + 1, "A live transcript completion without Stop must expand")
        try event(.codex, "Stop")
        precondition(notifications == before + 1, "A late Stop after transcript completion must not expand again")
        try transcript(["sessionID": "test", "turnStatus": "processing", "hasActivity": false, "isReplay": true])
        try transcript(["sessionID": "test", "turnStatus": "idle", "hasActivity": false, "isReplay": true])
        try event(.codex, "Stop")
        precondition(notifications == before + 1, "Replaying old starts must not re-arm completion")
        try transcript(["sessionID": "test", "turnStatus": "processing", "hasActivity": true])
        try transcript(["sessionID": "test", "turnStatus": "idle", "hasActivity": true])
        precondition(notifications == before + 1, "Delayed transcript starts after a completed hook must not re-arm")
        try event(.codex, "UserPromptSubmit")
        try event(.codex, "Interrupt")
        try event(.codex, "Stop")
        precondition(notifications == before + 1, "User interruption must not be presented as completion")

        preferences.set(false, forKey: AgentMonitor.revealOnCompletionKey)
        try event(.pi, "SessionStart")
        try event(.pi, "UserPromptSubmit")
        try event(.pi, "Stop")
        precondition(notifications == before + 1, "Disabled completion expansion must remain disabled")
        preferences.set(true, forKey: AgentMonitor.revealOnCompletionKey)
        try event(.pi, "Stop")
        precondition(notifications == before + 1, "Enabling must not replay an already completed turn")
        try event(.pi, "UserPromptSubmit")
        try event(.pi, "Stop")
        precondition(notifications == before + 2)

        try event(.pi, "UserPromptSubmit")
        try event(.pi, "SubagentStart", extra: ["agent_id": "child"])
        try event(.pi, "Stop")
        precondition(notifications == before + 2, "A working subagent keeps the conversation active")
        try event(.pi, "Stop", extra: ["agent_id": "child"])
        precondition(notifications == before + 2, "A child completion must not select the parent prematurely")
        try event(.pi, "Stop")
        precondition(notifications == before + 3)

        try event(.antigravity, "SessionStart", id: "tool-free")
        try event(.antigravity, "Stop", id: "tool-free")
        try event(.antigravity, "Stop", id: "tool-free")
        precondition(notifications == before + 5, "Antigravity has no start hook; tool-free turns still expand")

        try event(.claude, "SessionStart", id: "approval")
        try event(.claude, "PermissionRequest", id: "approval", extra: ["tool_name": "Bash"])
        let approvalNotices = notifications
        try event(.pi, "UserPromptSubmit")
        try event(.pi, "Stop")
        precondition(notifications == approvalNotices + 1 && monitor.selectedSessionID == "approval"
            && monitor.selectedAgent == .claude, "Completion must preserve an outstanding approval")
        try event(.claude, "SessionEnd", id: "approval")
        let endedNotices = notifications
        try event(.pi, "SessionEnd")
        precondition(notifications == endedNotices, "Closing a session must not reopen a removed conversation")
        try event(.codex, "SessionStart", id: "transcript")
        for expected in 1...2 {
            try transcript(["sessionID": "transcript", "turnStatus": "processing", "hasActivity": true])
            try transcript(["sessionID": "transcript", "turnStatus": "idle", "hasActivity": true])
            precondition(notifications == endedNotices + expected, "Transcript-only turns must also re-arm")
        }
        let desktop: [String: Any] = ["_term_bundle": "com.anthropic.claudefordesktop", "cwd": "/Users/test/demo"]
        let desktopBefore = notifications
        try event(.claude, "SessionStart", id: "desktop", extra: desktop)
        try event(.claude, "UserPromptSubmit", id: "desktop", extra: desktop.merging(["prompt": "hi"]) { $1 })
        precondition(monitor.sessions["desktop"]?.termBundleId == "com.anthropic.claudefordesktop"
            && monitor.sessions["desktop"]?.status == .processing, "Claude Desktop Code-tab hooks create a session")
        let touch: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": "touch /tmp/x"]]
        try event(.claude, "PermissionRequest", id: "desktop", extra: desktop.merging(touch) { $1 })
        precondition(monitor.requests.count == 1 && monitor.sessions["desktop"]?.status == .waitingApproval
            && notifications == desktopBefore + 1 && monitor.selectedSessionID == "desktop",
            "Claude Desktop Code-tab permissions are answered in the notch")
        try event(.claude, "PostToolUse", id: "desktop", extra: desktop.merging(["tool_name": "Read", "tool_input": ["file_path": "/tmp/y"]]) { $1 })
        precondition(monitor.requests.count == 1, "A parallel tool finishing keeps the request")
        try event(.claude, "PostToolUse", id: "desktop", extra: desktop.merging(touch) { $1 })
        precondition(monitor.requests.isEmpty && monitor.sessions["desktop"]?.status == .processing,
            "Approved in Claude Desktop's own card: the guarded tool finishing drops the stale request")
        try event(.claude, "PermissionRequest", id: "desktop", extra: desktop.merging(touch) { $1 })
        try event(.claude, "PostToolUseFailure", id: "desktop", extra: desktop.merging(touch) { $1 })
        precondition(monitor.requests.isEmpty, "A failed run of the guarded tool also drops the request")
        let desktopTurnBefore = notifications
        try event(.claude, "Stop", id: "desktop", extra: desktop)
        precondition(notifications == desktopTurnBefore + 1, "A Code-tab turn completion expands")
        try event(.claude, "PermissionRequest", id: "terminal", extra: ["tool_name": "Bash"])
        precondition(monitor.requests.count == 1, "Terminal sessions keep the island approval flow")
        try event(.claude, "SessionEnd", id: "terminal")
        try event(.claude, "SessionEnd", id: "desktop")
        precondition(monitor.requests.isEmpty)

        func cowork(_ update: CoworkSessionUpdate) throws {
            IntegrationServiceClient.shared.onCowork?(try JSONEncoder().encode(update))
        }
        let coworkBefore = notifications
        try cowork(CoworkSessionUpdate(sessionId: "local_cowork", title: "Tidy", phase: .processing, cliSessionId: "cowork-cli"))
        precondition(monitor.sessions["local_cowork"]?.status == .processing && notifications == coworkBefore,
            "A running Cowork task shows without expanding")
        try cowork(CoworkSessionUpdate(sessionId: "local_cowork", phase: .waitingApproval, currentTool: "Bash", cliSessionId: "cowork-cli"))
        precondition(monitor.sessions["local_cowork"]?.status == .waitingApproval && monitor.requests.isEmpty
            && notifications == coworkBefore + 1 && monitor.selectedSessionID == "local_cowork",
            "A Cowork approval is shown display-only, without a queued request")
        try cowork(CoworkSessionUpdate(sessionId: "local_cowork", phase: .idle, lastResultText: "Done.", cliSessionId: "cowork-cli",
                                       completedTurnCount: 1, turnEnded: true))
        precondition(notifications == coworkBefore + 2 && monitor.sessions["local_cowork"]?.status == .idle,
            "A finished Cowork turn expands")
        try cowork(CoworkSessionUpdate(sessionId: "local_cowork", phase: .idle, lastResultText: "Done.", cliSessionId: "cowork-cli",
                                       completedTurnCount: 1))
        precondition(notifications == coworkBefore + 2, "An unchanged Cowork turn must not expand again")
        try event(.claude, "SessionStart", id: "cowork-cli")
        try cowork(CoworkSessionUpdate(sessionId: "local_cowork", phase: .processing, cliSessionId: "cowork-cli"))
        precondition(monitor.sessions["local_cowork"] == nil && monitor.sessions["cowork-cli"] != nil,
            "A hook card for the same conversation replaces the Cowork card")
        try event(.claude, "SessionEnd", id: "cowork-cli")
        try cowork(CoworkSessionUpdate(sessionId: "local_gone", phase: .processing))
        try cowork(.removal(sessionId: "local_gone"))
        precondition(monitor.sessions["local_gone"] == nil, "An archived Cowork task loses its card")

        print("Passed Agent completion selection, five providers, successive turns, deduplication, transcript replay, interruption, setting, approval priority, Claude Desktop Code-tab and Cowork checks.")
    }
}
