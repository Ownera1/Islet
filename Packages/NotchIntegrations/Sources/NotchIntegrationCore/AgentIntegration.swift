import Foundation
import CodeIslandCore

public enum NotchAgent: String, CaseIterable, Identifiable, Sendable {
    case pi, codex, claude, zcode
    case antigravity = "google-antigravity"
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .pi: return "Pi"
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .zcode: return "ZCode"
        case .antigravity: return "Antigravity"
        }
    }
    public var canApprove: Bool { self != .antigravity }
    public var events: [String] {
        switch self {
        case .pi: return []
        case .antigravity: return ["PreToolUse", "PostToolUse", "Stop"]
        case .zcode: return ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Stop"]
        case .claude:
            return ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "PreCompact", "SubagentStart", "SubagentStop", "Stop", "StopFailure", "Notification"]
        case .codex:
            return ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "PreCompact", "PostCompact", "SubagentStart", "SubagentStop", "Stop", "Interrupt"]
        }
    }
}

public enum HookConfigurationError: LocalizedError {
    case malformed, incompatible(String)
    public var errorDescription: String? {
        switch self {
        case .malformed: return "配置无法解析，原文件未修改。"
        case .incompatible(let key): return "配置中的 \(key) 格式不兼容，原文件未修改。"
        }
    }
}

/// Adds/removes only our exact bridge command; preserves other hooks and JSONC text.
public enum HookConfiguration {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    public static func command(bridge: String, agent: NotchAgent) -> String {
        shellQuote(bridge) + " --source " + agent.rawValue
    }
    public static func update(_ text: String, agent: NotchAgent, bridge: String, install: Bool) throws -> String {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}\n" : text
        guard let data = uncomment(original).data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookConfigurationError.malformed
        }
        if let hooks = root["hooks"], !(hooks is [String: Any]) { throw HookConfigurationError.incompatible("hooks") }
        var hookRoot = root["hooks"] as? [String: Any] ?? [:]
        if agent == .zcode, let events = hookRoot["events"], !(events is [String: Any]) {
            throw HookConfigurationError.incompatible("hooks.events")
        }
        var events = agent == .zcode ? (hookRoot["events"] as? [String: Any] ?? [:]) : hookRoot
        let cmd = command(bridge: bridge, agent: agent)
        for (name, value) in events {
            guard let entries = value as? [[String: Any]] else {
                if agent.events.contains(name) { throw HookConfigurationError.incompatible(name) }
                continue
            }
            let cleaned = entries.compactMap { entry -> [String: Any]? in
                if (entry["command"] as? String)?.hasPrefix(cmd) == true { return nil }
                guard let handlers = entry["hooks"] as? [[String: Any]] else { return entry }
                let kept = handlers.filter { !($0["command"] as? String ?? "").hasPrefix(cmd) }
                if kept.isEmpty { return nil }
                var copy = entry; copy["hooks"] = kept; return copy
            }
            if cleaned.isEmpty { events.removeValue(forKey: name) } else { events[name] = cleaned }
        }
        if install {
            for name in agent.events {
                let handler: [String: Any] = [
                    "type": "command", "command": cmd + (agent == .antigravity ? " --event \(name)" : ""),
                    "timeout": hookTimeout(agent: agent, event: name)
                ]
                let entry: [String: Any] = agent == .antigravity && name == "Stop"
                    ? handler : ["matcher": agent == .antigravity ? "*" : "", "hooks": [handler]]
                var entries = events[name] as? [[String: Any]] ?? []
                entries.append(entry); events[name] = entries
            }
        }
        if agent == .zcode {
            if install && hookRoot["enabled"] == nil { hookRoot["enabled"] = true }
            hookRoot["events"] = events
        } else { hookRoot = events }
        guard let result = JSONMinimalEditor.setTopLevelValue(in: original, key: "hooks", value: hookRoot) else {
            throw HookConfigurationError.malformed
        }
        return result
    }
    static func hookTimeout(agent: NotchAgent, event: String) -> Int {
        switch (agent, event) {
        case (_, "PermissionRequest"): return 86400
        case (.antigravity, "PreToolUse"): return 30
        // Codex caps these two hooks at 3 seconds.
        case (.codex, "SessionEnd"), (.codex, "Interrupt"): return 3
        default: return 5
        }
    }
    public static func uncomment(_ text: String) -> String {
        let chars = Array(text); var out = ""; var i = 0; var quoted = false; var escaped = false
        while i < chars.count {
            let c = chars[i]
            if quoted {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
                i += 1; continue
            }
            if c == "\"" { quoted = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                i += 2; while i < chars.count && chars[i] != "\n" { i += 1 }; continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") {
                    out.append(chars[i] == "\n" ? "\n" : " "); i += 1
                }
                i += 2; continue
            }
            out.append(c); i += 1
        }
        return out
    }
}

public enum AgentDecision {
    public static func response(allow: Bool, answers: [String: String]? = nil, originalInput: [String: Any] = [:]) -> Data {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if let answers {
            var input = originalInput
            input["questions"] = input["questions"] ?? []
            input["answers"] = answers
            decision["updatedInput"] = input
        }
        return (try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": [
            "hookEventName": "PermissionRequest", "decision": decision
        ]])) ?? Data("{}".utf8)
    }
}
