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
        print("Passed Agent completion selection, five providers, successive turns, deduplication, transcript replay, interruption, setting and approval priority checks.")
    }
}
