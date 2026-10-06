import Foundation

/// The hook bridge's optional diagnostics log.
///
/// Off unless `BORINGNOTCH_DEBUG` is set, and even then it only records
/// routing facts (event name, session id, which fields arrived) — never the
/// hook payload itself, which carries prompts, tool input and file contents.
public enum BridgeDebugLog {
    public static let environmentKey = "BORINGNOTCH_DEBUG"
    /// Tests that run the bridge binary point this at a temp file.
    public static let pathEnvironmentKey = "BORINGNOTCH_BRIDGE_LOG"
    public static let defaultPath = "/tmp/notch-agent-bridge.log"

    /// `BORINGNOTCH_DEBUG=1` (any value but empty, `0`, `false`, `no`, `off`).
    public static func isEnabled(environment: [String: String]) -> Bool {
        guard let raw = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return false }
        return !["0", "false", "no", "off"].contains(raw)
    }

    public static func path(environment: [String: String]) -> String {
        let custom = environment[pathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? defaultPath : custom
    }
}
