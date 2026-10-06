import Foundation

public enum DisplaySelection {
    /// With automatic switching on, the display under the pointer (`active`) wins, then the
    /// preferred display; with it off, only the preferred display is used. The fallback
    /// never overwrites the stored preference.
    public static func resolve(preferred: String?, available: [String], main: String?, automaticallySwitch: Bool, active: String? = nil) -> String? {
        if automaticallySwitch, let active, available.contains(active) { return active }
        if let preferred, available.contains(preferred) { return preferred }
        guard preferred == nil || automaticallySwitch else { return nil }
        if let main, available.contains(main) { return main }
        return available.first
    }
}

/// Debounces the display under the pointer so crossing a screen edge on the way
/// somewhere else does not drag the notch along.
public struct ActiveDisplayTracker {
    public private(set) var active: String?
    private var candidate: String?
    private var candidateSince: Date?
    public let dwell: TimeInterval

    public init(active: String? = nil, dwell: TimeInterval = 0.3) {
        self.active = active
        self.dwell = dwell
    }

    /// Feeds one pointer sample; returns the new active display once the pointer has
    /// stayed on it for `dwell`. While `canSwitch` is false (notch open, hovered or a
    /// drop in progress) the active display is held.
    public mutating func observe(_ display: String?, at now: Date, canSwitch: Bool) -> String? {
        guard let display, display != active, canSwitch else {
            candidate = nil
            candidateSince = nil
            return nil
        }
        if candidate != display {
            candidate = display
            candidateSince = now
        }
        guard let since = candidateSince, now.timeIntervalSince(since) >= dwell else { return nil }
        active = display
        candidate = nil
        candidateSince = nil
        return display
    }

    public mutating func reset(to display: String?) {
        active = display
        candidate = nil
        candidateSince = nil
    }
}
