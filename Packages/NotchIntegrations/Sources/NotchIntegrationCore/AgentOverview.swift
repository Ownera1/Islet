import Foundation
import CodeIslandCore

public enum AgentOverviewStyle: String, CaseIterable, Sendable {
    case singleLine, twoLine
}

public enum AgentConnectionState: Int, Sendable {
    case running, idle, offline
    public var label: String {
        switch self { case .running: return "运行中"; case .idle: return "已连接"; case .offline: return "未连接" }
    }
}

public struct AgentOverviewEntry: Identifiable {
    public let agent: NotchAgent
    public let state: AgentConnectionState
    public let sessionCount: Int
    public let snapshot: SessionSnapshot?
    public var id: String { agent.rawValue }
    public var subtitle: String {
        guard let snapshot else { return "未连接" }
        switch snapshot.status {
        case .waitingApproval: return "等待审批"
        case .waitingQuestion: return "等待回答"
        case .idle: return "等待下一条任务"
        case .processing, .running:
            return snapshot.agentTasks.current?.progressLabel ?? snapshot.toolDescription ?? snapshot.currentTool ?? "思考中…"
        }
    }

    public static func entries(sessions: [String: SessionSnapshot]) -> [Self] {
        NotchAgent.allCases.map { agent in
            let matches = sessions.filter { $0.value.source == agent.rawValue }.sorted {
                let left = priority($0.value.status), right = priority($1.value.status)
                if left != right { return left < right }
                if $0.value.lastActivity != $1.value.lastActivity { return $0.value.lastActivity > $1.value.lastActivity }
                return $0.key < $1.key
            }.map(\.value)
            let snapshot = matches.first
            return Self(agent: agent, state: snapshot == nil ? .offline : snapshot?.status == .idle ? .idle : .running,
                        sessionCount: matches.count, snapshot: snapshot)
        }.sorted {
            if $0.state != $1.state { return $0.state.rawValue < $1.state.rawValue }
            return NotchAgent.allCases.firstIndex(of: $0.agent)! < NotchAgent.allCases.firstIndex(of: $1.agent)!
        }
    }

    private static func priority(_ status: AgentStatus) -> Int {
        switch status { case .waitingApproval, .waitingQuestion: return 0; case .processing, .running: return 1; case .idle: return 2 }
    }
}
