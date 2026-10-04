import Foundation
import CodeIslandCore

/// Gemini CLI's public OAuth client configuration; refreshed tokens stay in memory.
enum GeminiToken {
    static func resolve(_ credentials: [String: Any], home: String) async throws -> String {
        guard let token = credentials["access_token"] as? String, !token.isEmpty else { throw UsageError.login(.gemini) }
        guard let expiry = UsageParser.number(credentials["expiry_date"]), expiry / 1000 <= Date().timeIntervalSince1970 + 60 else { return token }
        guard let refresh = credentials["refresh_token"] as? String, !refresh.isEmpty else { throw UsageError.expired(.gemini) }
        let client: (String, String)? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: clientConfiguration(home: home)) }
        }
        guard let (id, secret) = client else { throw UsageError.expired(.gemini) }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "+&=%?#")
        request.httpBody = ["client_id": id, "client_secret": secret, "refresh_token": refresh, "grant_type": "refresh_token"]
            .sorted { $0.key < $1.key }.map { $0.key + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await ClaudeQuotaClient.session.data(for: request, delegate: GeminiNoRedirect.shared)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let root = try? UsageParser.object(data),
              let fresh = root["access_token"] as? String, !fresh.isEmpty else { throw UsageError.expired(.gemini) }
        return fresh
    }
    private static func clientConfiguration(home: String) -> (String, String)? {
        let env = ProcessInfo.processInfo.environment
        if let id = env["GEMINI_OAUTH_CLIENT_ID"], let secret = env["GEMINI_OAUTH_CLIENT_SECRET"], !id.isEmpty, !secret.isEmpty { return (id, secret) }
        var candidates = [env["GEMINI_OAUTH2_JS_PATH"]].compactMap { $0 }
        let roots = ["/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules", "/opt/homebrew/opt/gemini-cli/libexec/lib/node_modules", "/usr/local/opt/gemini-cli/libexec/lib/node_modules", home + "/.npm-global/lib/node_modules", home + "/.local/share/pnpm/global/5/node_modules"]
        for root in roots {
            candidates.append(root + "/@google/gemini-cli-core/dist/src/code_assist/oauth2.js")
            candidates.append(root + "/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js")
        }
        for path in candidates {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            func value(_ name: String) -> String? {
                let regex = try? NSRegularExpression(pattern: name + #"\s*=\s*['"]([^'"]+)['"]"#)
                let ns = content as NSString
                return regex?.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
            }
            if let id = value("OAUTH_CLIENT_ID"), let secret = value("OAUTH_CLIENT_SECRET") { return (id, secret) }
        }
        return nil
    }
    private final class GeminiNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        static let shared = GeminiNoRedirect()
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
