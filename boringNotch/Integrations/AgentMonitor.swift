import AppKit
import Combine
import CodeIslandCore
import NotchIntegrationCore

struct AgentQuestion: Identifiable {
    let id = UUID()
    let key: String
    let text: String
    let options: [String]
    let multiple: Bool
}
struct PendingAgentRequest: Identifiable {
    let id: UUID
    let sessionID: String
    let tool: String
    let detail: String
    let questions: [AgentQuestion]
    let originalInput: [String: Any]
    let respond: (Data) -> Void
}

@MainActor
final class AgentMonitor: ObservableObject {
    static let shared = AgentMonitor()
    @Published private(set) var sessions: [String: SessionSnapshot] = [:]
    @Published private(set) var requests: [PendingAgentRequest] = []
    @Published private(set) var serviceStatus = "Agent 服务尚未启动"
    @Published var selectedSessionID: String?
    @Published var selectedAgent: NotchAgent? {
        didSet { preferences.set(selectedAgent?.rawValue ?? "all", forKey: "selectedAgentFramework") }
    }
    private let preferences: UserDefaults
    private var completedSessions: Set<String> = []
    private var promptHookSessions: Set<String> = []
    static let revealOnCompletionKey = "agentRevealOnCompletion"

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        selectedAgent = NotchAgent(rawValue: preferences.string(forKey: "selectedAgentFramework") ?? "")
    }
    var isServiceReady: Bool { serviceStatus == "Agent 服务已就绪" }
    private var cleanup: Timer?
    var overview: [AgentOverviewEntry] { AgentOverviewEntry.entries(sessions: sessions) }
    var connectedAgents: [AgentOverviewEntry] { overview.filter { $0.state != .offline } }
    func sessions(for agent: NotchAgent) -> [(id: String, snapshot: SessionSnapshot)] {
        sessions.filter { $0.value.source == agent.rawValue }
            .sorted { left, right in
                let leftWaiting = requests.contains { $0.sessionID == left.key }
                let rightWaiting = requests.contains { $0.sessionID == right.key }
                if leftWaiting != rightWaiting { return leftWaiting }
                let leftActive = left.value.status != .idle, rightActive = right.value.status != .idle
                if leftActive != rightActive { return leftActive }
                if left.value.lastActivity != right.value.lastActivity { return left.value.lastActivity > right.value.lastActivity }
                return left.key < right.key
            }.map { (id: $0.key, snapshot: $0.value) }
    }
    var sortedSessions: [(id: String, snapshot: SessionSnapshot)] {
        guard let selectedAgent else { return [] }
        return sessions(for: selectedAgent)
    }
    var selected: (id: String, snapshot: SessionSnapshot)? {
        guard let selectedAgent else { return nil }
        if let id = selectedSessionID, let snapshot = sessions[id], snapshot.source == selectedAgent.rawValue { return (id, snapshot) }
        return sortedSessions.first
    }
    func start() {
        let client = IntegrationServiceClient.shared
        client.onStatus = { [weak self] in self?.serviceStatus = $0 }
        client.onEvent = { [weak self] data, id in
            self?.handle(data, respond: { response in client.respond(response, id: id) }, id: id)
        }
        client.onDisconnect = { [weak self] id in
            guard let self else { return }
            if let request = self.requests.first(where: { $0.id == id }) { self.sessions[request.sessionID]?.status = .idle }
            self.requests.removeAll { $0.id == id }
        }
        client.onTranscript = { [weak self] in self?.apply($0) }
        client.onCowork = { [weak self] in self?.applyCowork($0) }
        client.start()
        cleanup = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.removeEndedSessions() }
        }
    }
    func stop() {
        for request in requests { request.respond(Data("{}".utf8)) }
        requests.removeAll(); cleanup?.invalidate(); IntegrationServiceClient.shared.stop()
    }
    func dismiss(_ id: String) {
        for request in requests.filter({ $0.sessionID == id }) { request.respond(Data("{}".utf8)) }
        requests.removeAll { $0.sessionID == id }; sessions.removeValue(forKey: id)
        if selectedSessionID == id { selectedSessionID = nil }
        completedSessions.remove(id)
        promptHookSessions.remove(id)
    }
    func decide(_ request: PendingAgentRequest, allow: Bool, answers: [String: String]? = nil) {
        requests.removeAll { $0.id == request.id }
        request.respond(AgentDecision.response(allow: allow, answers: answers, originalInput: request.originalInput))
        if !requests.contains(where: { $0.sessionID == request.sessionID }) { sessions[request.sessionID]?.status = allow ? .processing : .idle }
    }
    private func handle(_ data: Data, respond: @escaping (Data) -> Void, id: UUID) {
        guard let event = HookEvent(from: data), let source = event.rawJSON["_source"] as? String,
              let agent = NotchAgent(rawValue: source), let sessionID = event.sessionId else {
            respond(Data("{}".utf8)); return
        }
        let name = EventNormalizer.normalize(event.eventName)
        if event.agentId == nil {
            if name == "SessionStart" { promptHookSessions.remove(sessionID) }
            if name == "UserPromptSubmit" { promptHookSessions.insert(sessionID) }
            if name == "SessionStart" || name == "UserPromptSubmit" {
                completedSessions.remove(sessionID)
            }
            // Antigravity has no turn-start hook. Each Stop is its only turn boundary.
            if agent == .antigravity && name == "Stop" { completedSessions.remove(sessionID) }
        }
        if ["SessionStart", "SessionEnd", "Stop", "Interrupt", "TaskRoundComplete"].contains(name) {
            for request in requests.filter({ $0.sessionID == sessionID }) { request.respond(Data("{}".utf8)) }
            requests.removeAll { $0.sessionID == sessionID }
        }
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 30)
        for effect in effects {
            if case .removeSession(let sid) = effect { dismiss(sid) }
            if case .enqueueCompletion(let sid) = effect, event.agentId == nil {
                revealCompletedSession(sid)
            }
        }
        if agent.canApprove && name == "PermissionRequest" {
            let rawQuestions = event.toolInput?["questions"] as? [[String: Any]] ?? []
            var used = Set<String>()
            let questions = rawQuestions.map { raw -> AgentQuestion in
                let text = raw["question"] as? String ?? "请选择"
                var key = text; var suffix = 2
                while used.contains(key) { key = "\(text)_\(suffix)"; suffix += 1 }
                used.insert(key)
                let options = (raw["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
                return AgentQuestion(key: key, text: text, options: options, multiple: raw["multiSelect"] as? Bool ?? false)
            }
            let request = PendingAgentRequest(id: id, sessionID: sessionID, tool: event.toolName ?? "工具调用", detail: event.toolDescription ?? "", questions: questions, originalInput: event.toolInput ?? [:], respond: respond)
            requests.append(request); sessions[sessionID]?.status = questions.isEmpty ? .waitingApproval : .waitingQuestion
            selectedSessionID = sessionID
            selectedAgent = agent
            BoringViewCoordinator.shared.currentView = .agents
            NotificationCenter.default.post(name: .notchAgentNeedsAttention, object: nil)
        } else { respond(Data("{}".utf8)) }
    }
    private func apply(_ data: Data) {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = payload["sessionID"] as? String, var snapshot = sessions[id] else { return }
        let wasActive = snapshot.status == .processing || snapshot.status == .running
        let isReplay = payload["isReplay"] as? Bool == true
        var didFinish = false
        if let reply = payload["reply"] as? String { snapshot.lastAssistantMessage = reply }
        if let prompt = payload["prompt"] as? String { snapshot.lastUserPrompt = prompt }
        if !requests.contains(where: { $0.sessionID == id }), !snapshot.interrupted {
            if let status = payload["turnStatus"] as? String {
                // When prompt hooks exist, only they start a new turn. A delayed
                // transcript start from the finished turn must not re-arm the popup.
                if status == "processing", !isReplay, !wasActive, !promptHookSessions.contains(id) {
                    completedSessions.remove(id)
                }
                let hasActiveSubagents = snapshot.subagents.values.contains { $0.status != .idle }
                snapshot.status = status == "idle" ? (hasActiveSubagents ? .running : .idle) : .processing
                didFinish = status == "idle" && wasActive && !isReplay && payload["hasActivity"] as? Bool == true
            }
            if payload["hasActivity"] as? Bool == true { snapshot.lastActivity = Date() }
        }
        if let branch = payload["branch"] as? String { snapshot.gitBranch = branch; snapshot.gitIsWorktree = payload["isWorktree"] as? Bool ?? false }
        if let tasks = payload["tasks"], let taskData = try? JSONSerialization.data(withJSONObject: tasks),
           let list = try? JSONDecoder().decode(AgentTaskList.self, from: taskData) { snapshot.agentTasks = list }
        sessions[id] = snapshot
        if didFinish { revealCompletedSession(id) }
    }
    /// Claude Desktop Cowork task, read by the helper from Claude Desktop's
    /// own session store. Its permission cards can only be answered there, so
    /// a wait is shown without a request (display-only).
    private func applyCowork(_ data: Data) {
        guard let update = try? JSONDecoder().decode(CoworkSessionUpdate.self, from: data) else { return }
        let id = update.sessionId
        let wasWaiting = sessions[id].map { $0.status == .waitingApproval || $0.status == .waitingQuestion } ?? false
        switch ClaudeDesktop.apply(update, to: &sessions) {
        case .removed, .shadowed:
            completedSessions.remove(id)
            if selectedSessionID == id { selectedSessionID = nil }
        case .updated(let turnEnded):
            if update.phase != .idle || turnEnded { completedSessions.remove(id) }
            if turnEnded { revealCompletedSession(id) }
            let isWaiting = update.phase == .waitingApproval || update.phase == .waitingQuestion
            if isWaiting, !wasWaiting, requests.isEmpty {
                selectedSessionID = id
                selectedAgent = .claude
                BoringViewCoordinator.shared.currentView = .agents
                NotificationCenter.default.post(name: .notchAgentNeedsAttention, object: nil)
            }
        case .ignored:
            break
        }
    }
    private func revealCompletedSession(_ id: String) {
        guard let snapshot = sessions[id], snapshot.status == .idle, !snapshot.interrupted,
              !snapshot.subagents.values.contains(where: { $0.status != .idle }),
              completedSessions.insert(id).inserted else { return }
        guard preferences.object(forKey: Self.revealOnCompletionKey) as? Bool ?? true else { return }
        // Keep an outstanding approval/question selected when another conversation finishes.
        if requests.isEmpty, let agent = NotchAgent(rawValue: snapshot.source) {
            selectedSessionID = id
            selectedAgent = agent
        }
        BoringViewCoordinator.shared.currentView = .agents
        NotificationCenter.default.post(name: .notchAgentNeedsAttention, object: nil)
    }
    private func removeEndedSessions() {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        for (id, snapshot) in sessions {
            if snapshot.lastActivity < cutoff, !requests.contains(where: { $0.sessionID == id }) { dismiss(id) }
            else if let pid = snapshot.cliPid, pid > 1, kill(pid, 0) != 0, errno == ESRCH,
                    Date().timeIntervalSince(snapshot.lastActivity) > 30, !requests.contains(where: { $0.sessionID == id }) {
                sessions[id]?.status = .idle
            }
        }
    }
}
extension Notification.Name { static let notchAgentNeedsAttention = Notification.Name("notchAgentNeedsAttention") }
