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
    @Published var filter: NotchAgent?
    private var cleanup: Timer?
    var sortedSessions: [(id: String, snapshot: SessionSnapshot)] {
        sessions.filter { filter == nil || $0.value.source == filter?.rawValue }
            .sorted { left, right in
                let leftWaiting = requests.contains { $0.sessionID == left.key }
                let rightWaiting = requests.contains { $0.sessionID == right.key }
                if leftWaiting != rightWaiting { return leftWaiting }
                return left.value.lastActivity > right.value.lastActivity
            }.map { (id: $0.key, snapshot: $0.value) }
    }

    var selected: (id: String, snapshot: SessionSnapshot)? {
        if let id = selectedSessionID, let snapshot = sessions[id], filter == nil || snapshot.source == filter?.rawValue { return (id, snapshot) }
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
        if ["SessionStart", "SessionEnd", "Stop", "Interrupt", "TaskRoundComplete"].contains(name) {
            for request in requests.filter({ $0.sessionID == sessionID }) { request.respond(Data("{}".utf8)) }
            requests.removeAll { $0.sessionID == sessionID }
        }
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 30)
        for effect in effects {
            if case .removeSession(let sid) = effect { dismiss(sid) }
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
            BoringViewCoordinator.shared.currentView = .agents
            NotificationCenter.default.post(name: .notchAgentNeedsAttention, object: nil)
        } else { respond(Data("{}".utf8)) }
    }
    private func apply(_ data: Data) {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = payload["sessionID"] as? String, var snapshot = sessions[id] else { return }
        if let reply = payload["reply"] as? String { snapshot.lastAssistantMessage = reply }
        if let prompt = payload["prompt"] as? String { snapshot.lastUserPrompt = prompt }
        if !requests.contains(where: { $0.sessionID == id }), !snapshot.interrupted {
            if let status = payload["turnStatus"] as? String { snapshot.status = status == "idle" ? .idle : .processing }
            if payload["hasActivity"] as? Bool == true { snapshot.lastActivity = Date() }
        }
        if let branch = payload["branch"] as? String { snapshot.gitBranch = branch; snapshot.gitIsWorktree = payload["isWorktree"] as? Bool ?? false }
        if let tasks = payload["tasks"], let taskData = try? JSONSerialization.data(withJSONObject: tasks),
           let list = try? JSONDecoder().decode(AgentTaskList.self, from: taskData) { snapshot.agentTasks = list }
        sessions[id] = snapshot
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
