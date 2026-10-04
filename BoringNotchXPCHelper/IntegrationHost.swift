import Foundation
import CodeIslandCore
import NotchIntegrationCore

@objc protocol NotchIntegrationCallbacks {
    func agentEvent(_ data: Data, requestID: String)
    func agentDisconnected(_ requestID: String)
    func agentTranscript(_ data: Data)
    func agentServiceStatus(_ message: String)
}

/// Fixed integration operations in boring.notch's existing helper; the UI retains App Sandbox.
@MainActor
final class IntegrationHost {
    let server = AgentHookServer()
    weak var connection: NSXPCConnection?
    private var replies: [UUID: (Data) -> Void] = [:]
    private var paths: [String: (path: String, token: UUID)] = [:]
    private var tasks: [String: AgentTaskList] = [:]
    private lazy var tailer = JSONLTailer { [weak self] delta in Task { @MainActor in self?.transcript(delta) } }
    private var client: NotchIntegrationCallbacks? { connection?.remoteObjectProxy as? NotchIntegrationCallbacks }
    func start(connection: NSXPCConnection) {
        self.connection = connection
        server.onStatus = { [weak self] in self?.client?.agentServiceStatus($0) }
        server.onDisconnect = { [weak self] id in self?.replies.removeValue(forKey: id); self?.client?.agentDisconnected(id.uuidString) }
        server.onEvent = { [weak self] data, respond, id in
            guard let self, let event = HookEvent(from: data), let source = event.rawJSON["_source"] as? String,
                  NotchAgent(rawValue: source) != nil, let sessionID = event.sessionId else { respond(Data("{}".utf8)); return }
            self.replies[id] = respond
            self.client?.agentEvent(data, requestID: id.uuidString)
            let name = EventNormalizer.normalize(event.eventName)
            if name == "SessionStart" {
                self.tailer.detach(sessionId: sessionID); self.paths.removeValue(forKey: sessionID); self.tasks.removeValue(forKey: sessionID)
            }
            var list = self.tasks[sessionID] ?? AgentTaskList()
            let events = AgentTaskHookParser.events(from: event, normalizedEventName: name)
            if event.agentId != nil { _ = list.applySharedUpdates(events, now: Date()) }
            else { _ = list.apply(events, now: Date()) }
            self.tasks[sessionID] = list
            if let path = event.rawJSON["transcript_path"] as? String, path.hasPrefix("/"), self.paths[sessionID]?.path != path {
                self.paths[sessionID] = (path, self.tailer.attach(sessionId: sessionID, filePath: path, initialOffset: 0))
            }
            if name == "SessionEnd" { self.tailer.detach(sessionId: sessionID); self.paths.removeValue(forKey: sessionID); self.tasks.removeValue(forKey: sessionID) }
            if let cwd = event.rawJSON["cwd"] as? String, name == "SessionStart" || name == "Stop" {
                Task.detached(priority: .utility) { [weak self] in
                    let info = GitBranchReader.read(cwd: cwd)
                    var payload: [String: Any] = ["sessionID": sessionID]
                    if let info { payload["branch"] = info.branch; payload["isWorktree"] = info.isWorktree }
                    let data = try? JSONSerialization.data(withJSONObject: payload)
                    if let data { await self?.publish(data) }
                }
            }
        }
        do { try server.start() } catch { client?.agentServiceStatus(error.localizedDescription) }
    }
    func stop() {
        for response in replies.values { response(Data("{}".utf8)) }
        replies.removeAll(); tailer.detachAll(); paths.removeAll(); tasks.removeAll(); server.stop()
    }
    func reply(_ id: UUID, data: Data) { replies.removeValue(forKey: id)?(data) }
    private func publish(_ data: Data) { client?.agentTranscript(data) }
    private func transcript(_ delta: ConversationTailDelta) {
        guard let attachment = paths[delta.sessionId], attachment.path == delta.filePath, attachment.token == delta.attachmentToken else { return }
        var list = tasks[delta.sessionId] ?? AgentTaskList(); _ = list.apply(delta.taskEvents, now: Date()); tasks[delta.sessionId] = list
        var payload: [String: Any] = ["sessionID": delta.sessionId]
        if let text = delta.lastAssistantMessage { payload["reply"] = text }
        if let text = delta.lastUserPrompt { payload["prompt"] = text }
        if let status = delta.turnStatus { payload["turnStatus"] = status == .idle ? "idle" : "processing" }
        payload["hasActivity"] = delta.hasActivity && !delta.replaysWholeFile
        if let taskData = try? JSONEncoder().encode(list), let rows = try? JSONSerialization.jsonObject(with: taskData) { payload["tasks"] = rows }
        if let data = try? JSONSerialization.data(withJSONObject: payload) { client?.agentTranscript(data) }
    }
}

extension BoringNotchXPCHelper {
    @objc func startAgentEvents() {
        guard let connection else { return }
        Task { @MainActor in integration.start(connection: connection) }
    }
    @objc func stopAgentEvents() { Task { @MainActor in integration.stop() } }
    @objc func replyToAgent(_ requestID: String, data: Data) {
        guard let id = UUID(uuidString: requestID), data.count <= 128 * 1024 else { return }
        Task { @MainActor in integration.reply(id, data: data) }
    }
    @objc func configureAgent(_ source: String, enabled: Bool, claudeHome: String, codexHome: String, with reply: @escaping (String) -> Void) {
        guard let agent = NotchAgent(rawValue: source), claudeHome.hasPrefix("/"), codexHome.hasPrefix("/") else { reply("无效的工具或配置目录。"); return }
        Task { @MainActor in
            let installer = HelperAgentInstaller.shared
            installer.configureHomes(claude: claudeHome, codex: codexHome)
            installer.setInstalled(agent, enabled: enabled)
            reply(installer.message)
        }
    }
    @objc func agentConnectionStatus(_ claudeHome: String, codexHome: String, with reply: @escaping ([String]) -> Void) {
        Task { @MainActor in
            let installer = HelperAgentInstaller.shared; installer.configureHomes(claude: claudeHome, codex: codexHome); installer.refresh()
            reply(installer.installed.map(\.rawValue))
        }
    }
    @objc func subscriptionUsage(_ source: String, claudeHome: String, codexHome: String, with reply: @escaping (Data?, String?) -> Void) {
        guard let provider = SubscriptionProvider(rawValue: source), claudeHome.hasPrefix("/"), codexHome.hasPrefix("/") else { reply(nil, "无效的用量来源。"); return }
        Task {
            do {
                let usage = try await SubscriptionClient.fetch(provider, claudeHome: claudeHome, codexHome: codexHome)
                reply(try JSONEncoder().encode(usage), nil)
            } catch {
                let message: String
                switch error {
                case ClaudeQuotaClientError.noCredential: message = "请先登录 Claude Code。"
                case ClaudeQuotaClientError.unauthorized: message = "Claude 登录已过期，请打开 Claude Code 更新登录。"
                case ClaudeQuotaClientError.rateLimited: message = "请求过于频繁，稍后自动重试。"
                default: message = error.localizedDescription
                }
                reply(nil, message)
            }
        }
    }
}
