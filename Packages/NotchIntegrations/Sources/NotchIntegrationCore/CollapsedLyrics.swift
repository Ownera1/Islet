import Foundation

public enum CollapsedLyricsMode: String, CaseIterable, Sendable {
    case off, externalDisplays, allDisplays

    public var name: String {
        switch self {
        case .off: return "关闭"
        case .externalDisplays: return "仅外接显示器"
        case .allDisplays: return "所有显示器"
        }
    }
}

public enum CollapsedLyricsPlacement: Equatable, Sendable {
    case hidden, inline, belowNotch
}

/// Uses the window's screen rather than the system's primary display.
public func collapsedLyricsPlacement(mode: CollapsedLyricsMode, hasHardwareNotch: Bool) -> CollapsedLyricsPlacement {
    switch mode {
    case .off: return .hidden
    case .externalDisplays: return hasHardwareNotch ? .hidden : .inline
    case .allDisplays: return hasHardwareNotch ? .belowNotch : .inline
    }
}

/// Keeps the lower strip out of a hardware notch while lines are sung, bridging the short
/// gaps between them, and steps it aside while the pointer is near so the app beneath stays reachable.
public struct CollapsedLyricStrip: Equatable, Sendable {
    /// Gaps shorter than this keep the strip down; longer ones are interludes.
    public static let gapGrace: Double = 2
    /// How long the pointer must stay away before the strip comes back.
    public static let returnDelay: Double = 0.6
    private var lastSung = -Double.infinity
    private var lastNear = -Double.infinity

    public init() {}

    /// `now` is in seconds on any steady clock. Returns whether the strip should show.
    public mutating func update(_ frame: CollapsedLyricFrame, pointerNear: Bool, now: Double) -> Bool {
        if frame.line != nil { lastSung = now }
        if pointerNear { lastNear = now }
        return now - lastSung < Self.gapGrace && now - lastNear >= Self.returnDelay
    }
}

/// Presentation derived from the existing parsed document and playback clock.
/// Plain lyrics have no clock, so they cannot identify a current sung line.
public struct CollapsedLyricFrame: Equatable, Sendable {
    public let line: LyricLine?
    public let index: Int?
    public let start: Double
    public let end: Double
    public let revealProgress: Double
    public let scrollProgress: Double

    public static func hasContent(document: LyricsDocument, availability: LyricsAvailability) -> Bool {
        availability == .instrumental
            || (availability == .available && document.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    public init(document: LyricsDocument, elapsed: Double, duration: Double) {
        guard !document.instrumental,
              let index = Lyrics.index(at: elapsed, in: document.lines) else {
            self.line = nil
            self.index = nil
            start = 0
            end = 0
            revealProgress = 0
            scrollProgress = 0
            return
        }
        let line = document.lines[index]
        let next = index + 1 < document.lines.count ? document.lines[index + 1].time : (duration > line.time ? duration : line.time + 8)
        let vocalEnd = line.duration.map { line.time + $0 }
            ?? line.words.last.map { $0.time + $0.duration }
            ?? next
        start = line.time
        end = max(line.time + 0.001, min(next, vocalEnd))
        self.index = index
        // Blank LRC lines and explicit YRC/word endings identify interludes.
        self.line = elapsed < end && !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? line : nil
        revealProgress = Lyrics.progress(at: elapsed, index: index, in: document.lines, duration: duration)
        let progress = min(1, max(0, (elapsed - start) / (end - start)))
        scrollProgress = min(1, max(0, (progress - 0.1) / 0.8))
    }
}
