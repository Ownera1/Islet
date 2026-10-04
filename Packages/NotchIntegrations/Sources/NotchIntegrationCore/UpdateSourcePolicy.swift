import Foundation

public enum UpdateSourcePolicy {
    public static func permits(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return false }
        let parts = url.pathComponents
        guard parts.count == 7,
              Array(parts.prefix(5)) == ["/", "Ownera1", "Islet", "releases", "download"],
              parts[5].hasPrefix("v"), parts[5].count > 1,
              !parts[6].isEmpty, !parts[6].contains("/"), ![".", ".."].contains(parts[6]) else { return false }
        return true
    }
}
