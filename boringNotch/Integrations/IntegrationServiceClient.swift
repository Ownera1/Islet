import Foundation
import NotchIntegrationCore

@objc protocol NotchIntegrationCallbacks {
    func agentEvent(_ data: Data, requestID: String)
    func agentDisconnected(_ requestID: String)
    func agentTranscript(_ data: Data)
    func agentServiceStatus(_ message: String)
}

@MainActor
final class IntegrationServiceClient: NSObject, NotchIntegrationCallbacks {
    static let shared = IntegrationServiceClient()
    private var connection: NSXPCConnection?
    var onEvent: ((Data, UUID) -> Void)?
    var onDisconnect: ((UUID) -> Void)?
    var onTranscript: ((Data) -> Void)?
    var onStatus: ((String) -> Void)?
    func start() {
        guard connection == nil else { return }
        let connection = NSXPCConnection(serviceName: "com.ownera1.agentusagenotch.helper")
        connection.remoteObjectInterface = NSXPCInterface(with: BoringNotchXPCHelperProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: NotchIntegrationCallbacks.self)
        connection.exportedObject = self
        connection.interruptionHandler = { [weak self] in Task { @MainActor in self?.onStatus?("Agent 辅助进程连接中断，请重启应用。") } }
        connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
        connection.resume(); self.connection = connection
        proxy?.startAgentEvents()
    }
    func stop() { proxy?.stopAgentEvents(); connection?.invalidate(); connection = nil }
    var proxy: BoringNotchXPCHelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in Task { @MainActor in self?.onStatus?("无法连接 Agent 辅助进程。") } } as? BoringNotchXPCHelperProtocol
    }
    func respond(_ data: Data, id: UUID) { proxy?.replyToAgent(id.uuidString, data: data) }
    func fetchUsage(_ provider: SubscriptionProvider, claudeHome: String, codexHome: String) async -> (SubscriptionUsage?, String?) {
        guard let proxy else { return (nil, "辅助进程尚未连接。") }
        return await withCheckedContinuation { continuation in
            let gate = UsageReplyGate(continuation)
            proxy.subscriptionUsage(provider.rawValue, claudeHome: claudeHome, codexHome: codexHome) { data, error in
                Task { @MainActor in
                    let usage = data.flatMap { try? JSONDecoder().decode(SubscriptionUsage.self, from: $0) }
                    gate.finish((usage, error ?? (usage == nil ? "未返回可读取的用量。" : nil)))
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(45))
                gate.finish((nil, "用量读取超时，稍后自动重试。"))
            }
        }
    }
    nonisolated func agentEvent(_ data: Data, requestID: String) { Task { @MainActor in if let id = UUID(uuidString: requestID) { self.onEvent?(data, id) } } }
    nonisolated func agentDisconnected(_ requestID: String) { Task { @MainActor in if let id = UUID(uuidString: requestID) { self.onDisconnect?(id) } } }
    nonisolated func agentTranscript(_ data: Data) { Task { @MainActor in self.onTranscript?(data) } }
    nonisolated func agentServiceStatus(_ message: String) { Task { @MainActor in self.onStatus?(message) } }
}

@MainActor
private final class UsageReplyGate {
    private var continuation: CheckedContinuation<(SubscriptionUsage?, String?), Never>?
    init(_ continuation: CheckedContinuation<(SubscriptionUsage?, String?), Never>) { self.continuation = continuation }
    func finish(_ value: (SubscriptionUsage?, String?)) { let pending = continuation; continuation = nil; pending?.resume(returning: value) }
}
