import Foundation
import NotchIntegrationCore

@MainActor
final class HelperAgentInstaller {
    static let shared = HelperAgentInstaller()
    var message = "选择工具，安装对应的连接。"
    var installed: Set<NotchAgent> = []
    var busy = false
    var claudeHome = HomePaths.userHome + "/.claude"
    var codexHome = HomePaths.userHome + "/.codex"
    func configureHomes(claude: String, codex: String) { claudeHome = claude; codexHome = codex }
    var bridgePath: String { HomePaths.userHome + "/.boringnotch/notch-agent-bridge" }
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
        installed = Set(NotchAgent.allCases.filter { agent in
            guard let text = try? String(contentsOfFile: path(for: agent), encoding: .utf8) else { return false }
            return agent == .pi ? text.contains("/tmp/boringnotch-") : text.contains(bridgePath)
        })
    }
    func setInstalled(_ agent: NotchAgent, enabled: Bool) {
        busy = true; defer { busy = false; refresh() }
        do {
            let fm = FileManager.default
            let resourceRoot = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/IntegrationResources")
            let target = URL(fileURLWithPath: path(for: agent)).resolvingSymlinksInPath()
            let original = fm.contents(atPath: target.path)
            if enabled {
                let source = resourceRoot.appendingPathComponent("notch-agent-bridge")
                try fm.createDirectory(atPath: (bridgePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try Data(contentsOf: source).write(to: URL(fileURLWithPath: bridgePath), options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bridgePath)
            }
            var result: Data?
            if agent == .pi {
                if enabled { result = try Data(contentsOf: resourceRoot.appendingPathComponent("boringnotch-pi.ts")) }
                else if let original, String(data: original, encoding: .utf8)?.contains("/tmp/boringnotch-") == true { result = nil }
                else { throw HookConfigurationError.incompatible("Pi 扩展") }
            } else {
                let text: String
                if let original {
                    guard let decoded = String(data: original, encoding: .utf8) else { throw HookConfigurationError.malformed }
                    text = decoded
                } else { text = "{}\n" }
                result = try HookConfiguration.update(text, agent: agent, bridge: bridgePath, install: enabled).data(using: .utf8)
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let original {
                let backup = target.path + ".boringnotch-backup-" + String(Int(Date().timeIntervalSince1970 * 1000))
                try original.write(to: URL(fileURLWithPath: backup), options: .withoutOverwriting)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup)
            }
            let mode = (try? fm.attributesOfItem(atPath: target.path)[.posixPermissions]) ?? 0o600
            if let result {
                try result.write(to: target, options: .atomic)
                try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
            } else if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            message = enabled ? "\(agent.name) 已连接。重启该工具后生效。" : "已移除 \(agent.name) 连接。"
            if enabled && agent == .codex { message += " 在 Codex 中运行 /hooks，审核并启用新 Hook。" }
        } catch { message = "\(agent.name)：\(error.localizedDescription)" }
    }
}
