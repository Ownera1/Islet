import Foundation

public enum DisplaySelection {
    /// Keep the preferred display while connected; fallback does not overwrite the preference.
    public static func resolve(preferred: String?, available: [String], main: String?, automaticallySwitch: Bool) -> String? {
        if let preferred, available.contains(preferred) { return preferred }
        guard preferred == nil || automaticallySwitch else { return nil }
        if let main, available.contains(main) { return main }
        return available.first
    }
}
