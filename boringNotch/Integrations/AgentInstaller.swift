import Foundation
import Combine
import NotchIntegrationCore

@MainActor
final class AgentInstaller: ObservableObject {
    static let shared = AgentInstaller()
    @Published var message = "选择工具，安装对应的连接。"
    @Published var installed: Set<NotchAgent> = []
    @Published var busy = false
    var claudeHome: String { UserDefaults.standard.string(forKey: "integrationClaudeHome") ?? HomePaths.userHome + "/.claude" }
    var codexHome: String { UserDefaults.standard.string(forKey: "integrationCodexHome") ?? HomePaths.userHome + "/.codex" }
    func path(for agent: NotchAgent) -> String {
        switch agent {
        case .claude: return claudeHome + "/settings.json"
        case .codex: return codexHome + "/hooks.json"
        case .pi: return HomePaths.userHome + "/.pi/agent/extensions/boringnotch.ts"
        case .zcode: return HomePaths.userHome + "/.zcode/cli/config.json"
        case .antigravity: return HomePaths.userHome + "/.gemini/config/hooks.json"
        }
    }
    func refresh() {
        IntegrationServiceClient.shared.proxy?.agentConnectionStatus(claudeHome, codexHome: codexHome) { [weak self] sources in
            Task { @MainActor in self?.installed = Set(sources.compactMap(NotchAgent.init(rawValue:))) }
        }
    }
    func setInstalled(_ agent: NotchAgent, enabled: Bool) {
        guard let proxy = IntegrationServiceClient.shared.proxy else { message = "辅助进程尚未连接。"; return }
        busy = true
        proxy.configureAgent(agent.rawValue, enabled: enabled, claudeHome: claudeHome, codexHome: codexHome) { [weak self] message in
            Task { @MainActor in self?.busy = false; self?.message = message; self?.refresh() }
        }
    }
}
