import AppKit
import CodeIslandCore
import NotchIntegrationCore

@MainActor
enum AgentTerminal {
    static func open(_ session: SessionSnapshot, id: String) {
        if let url = ClaudeDesktop.deepLink(id: id, snapshot: session) { NSWorkspace.shared.open(url); return }
        if session.source == "codex", session.termBundleId == "com.openai.codex" {
            let thread = session.providerSessionId ?? id.replacingOccurrences(of: "codexapp:", with: "")
            if let url = URL(string: "codex://threads/" + thread.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) { NSWorkspace.shared.open(url) }
            return
        }
        if session.source == "zcode", session.termApp == nil { launch(bundle: "ai.z.zcode", fallbackName: "ZCode"); return }
        if session.source == "google-antigravity", session.termApp == nil { launch(bundle: "com.google.antigravity", fallbackName: "Antigravity"); return }
        if let tty = session.ttyPath, session.terminalName == "Terminal" {
            runScript("""
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is \(quote(tty)) then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
                activate
            end tell
            """); return
        }
        if let sessionID = session.itermSessionId, session.terminalName == "iTerm2" {
            let normalized = sessionID.components(separatedBy: ":").last ?? sessionID
            runScript("""
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if unique ID of s is \(quote(normalized)) then
                                select w
                                select t
                                select s
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
                activate
            end tell
            """); return
        }
        let names = ["Ghostty": "com.mitchellh.ghostty", "iTerm2": "com.googlecode.iterm2", "Terminal": "com.apple.Terminal", "Warp": "dev.warp.Warp-Stable"]
        launch(bundle: session.termBundleId ?? names[session.terminalName ?? ""] ?? "com.apple.Terminal", fallbackName: session.terminalName ?? "Terminal")
    }
    private static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    private static func runScript(_ script: String) {
        Task { @MainActor in _ = try? await AppleScriptHelper.execute(script) }
    }
    private static func launch(bundle: String, fallbackName: String) {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            ?? ["/Applications/", NSHomeDirectory() + "/Applications/"].map { URL(fileURLWithPath: $0 + fallbackName + ".app") }.first { FileManager.default.fileExists(atPath: $0.path) }
        if let url { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }
}
