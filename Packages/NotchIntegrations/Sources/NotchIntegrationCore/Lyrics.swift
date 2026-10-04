import Foundation

public struct LyricWord: Equatable, Sendable {
    public let time: Double
    public let duration: Double
    public let text: String

    public init(time: Double, duration: Double, text: String) {
        self.time = time
        self.duration = duration
        self.text = text
    }

    public func progress(at elapsed: Double) -> Double {
        guard duration > 0 else { return elapsed >= time ? 1 : 0 }
        return min(1, max(0, (elapsed - time) / duration))
    }
}

public struct LyricLine: Equatable, Sendable {
    public let time: Double
    public let text: String
    public let duration: Double?
    public let words: [LyricWord]

    public init(time: Double, text: String, duration: Double? = nil, words: [LyricWord] = []) {
        self.time = time
        self.text = text
        self.duration = duration
        self.words = words
    }
}

public enum LyricsAvailability: Equatable, Sendable {
    case loading, available, instrumental, unavailable

    public var canFocus: Bool { self == .available || self == .instrumental }
}

public struct LyricsDocument: Equatable, Sendable {
    public let plain: String
    public let lines: [LyricLine]
    public let instrumental: Bool

    public init(plain: String = "", lines: [LyricLine] = [], instrumental: Bool = false) {
        self.plain = plain
        self.lines = lines
        self.instrumental = instrumental
    }

    public var availability: LyricsAvailability {
        if instrumental { return .instrumental }
        return lines.contains { !$0.text.isEmpty } || !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .available : .unavailable
    }

    public static func netease(_ row: [String: Any]) -> LyricsDocument {
        let yrc = (row["yrc"] as? [String: Any])?["lyric"] as? String ?? ""
        let lrc = (row["lrc"] as? [String: Any])?["lyric"] as? String ?? ""
        let words = Lyrics.parseYRC(yrc)
        let lines = words.isEmpty ? Lyrics.parseEnhancedLRC(lrc) : words
        // Some public responses encode instrumental tracks as a single sentinel line.
        let instrumental = row["nolyric"] as? Bool == true || row["pureMusic"] as? Bool == true
            || lines.contains { $0.text.trimmingCharacters(in: .whitespaces) == "纯音乐，请欣赏" }
        return LyricsDocument(lines: lines, instrumental: instrumental)
    }

    public static func lrclib(_ row: [String: Any]) -> LyricsDocument {
        LyricsDocument(
            plain: row["plainLyrics"] as? String ?? "",
            lines: Lyrics.parseEnhancedLRC(row["syncedLyrics"] as? String ?? ""),
            instrumental: row["instrumental"] as? Bool == true
        )
    }
}

public enum Lyrics {
    public static func parse(_ lrc: String) -> [LyricLine] {
        let pattern = #"\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let offsetPattern = #"\[offset:([+-]?\d+)\]"#
        let offsetRegex = try? NSRegularExpression(pattern: offsetPattern, options: .caseInsensitive)
        let ns = lrc as NSString
        let offset: Double = offsetRegex?.firstMatch(in: lrc, range: NSRange(location: 0, length: ns.length)).map {
            (Double(ns.substring(with: $0.range(at: 1))) ?? 0) / 1000
        } ?? 0
        return lrc.components(separatedBy: .newlines).flatMap { line -> [LyricLine] in
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard let last = matches.last else { return [] }
            let text = nsLine.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            return matches.map { match in
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                let fraction = match.range(at: 3).location == NSNotFound ? 0 : Double("0." + nsLine.substring(with: match.range(at: 3))) ?? 0
                return LyricLine(time: max(0, minutes * 60 + seconds + fraction + offset), text: text)
            }
        }.sorted { $0.time < $1.time }
    }
    public static func index(at elapsed: Double, in lines: [LyricLine]) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    /// LRC has no vocal timing. Finish an estimate at 90% of the interval, capped at 8s.
    public static func progress(at elapsed: Double, index: Int, in lines: [LyricLine], duration: Double) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        let line = lines[index]
        if !line.words.isEmpty {
            let weight = line.words.reduce(0) { $0 + max(1, $1.text.count) }
            return line.words.reduce(0) { $0 + $1.progress(at: elapsed) * Double(max(1, $1.text.count)) } / Double(weight)
        }
        let end = index + 1 < lines.count ? lines[index + 1].time : (duration > line.time ? duration : line.time + 8)
        let interval = max(0.001, min(8, line.duration ?? (end - line.time)))
        return min(1, max(0, (elapsed - line.time) / (interval * 0.9)))
    }

    public static func parseYRC(_ yrc: String) -> [LyricLine] {
        guard let header = try? NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#),
              let token = try? NSRegularExpression(pattern: #"\((\d+),(\d+),[^)]*\)"#) else { return [] }
        return yrc.components(separatedBy: .newlines).compactMap { raw in
            let ns = raw as NSString
            guard let line = header.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let matches = token.matches(in: raw, range: NSRange(location: NSMaxRange(line.range), length: ns.length - NSMaxRange(line.range)))
            let words = matches.enumerated().compactMap { i, match -> LyricWord? in
                let start = NSMaxRange(match.range)
                let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
                guard end > start else { return nil }
                return LyricWord(time: (Double(ns.substring(with: match.range(at: 1))) ?? 0) / 1000,
                                 duration: (Double(ns.substring(with: match.range(at: 2))) ?? 0) / 1000,
                                 text: ns.substring(with: NSRange(location: start, length: end - start)))
            }
            guard !words.isEmpty else { return nil }
            return LyricLine(time: (Double(ns.substring(with: line.range(at: 1))) ?? 0) / 1000,
                             text: words.map(\.text).joined(),
                             duration: (Double(ns.substring(with: line.range(at: 2))) ?? 0) / 1000,
                             words: words)
        }.sorted { $0.time < $1.time }
    }

    public static func parseEnhancedLRC(_ lrc: String) -> [LyricLine] {
        guard let tags = try? NSRegularExpression(pattern: #"<(\d+):(\d{2})(?:\.(\d{1,3}))?>"#) else { return parse(lrc) }
        let offsetRegex = try? NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let source = lrc as NSString
        let offset = offsetRegex?.firstMatch(in: lrc, range: NSRange(location: 0, length: source.length)).map {
            (Double(source.substring(with: $0.range(at: 1))) ?? 0) / 1000
        } ?? 0
        return lrc.components(separatedBy: .newlines).flatMap { raw -> [LyricLine] in
            let ns = raw as NSString
            let matches = tags.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let first = matches.first else { return parse(raw).map { LyricLine(time: max(0, $0.time + offset), text: $0.text) } }
            // Preserve the file-level offset in both the line and word clocks.
            let starts = matches.map { m -> Double in
                let fraction = m.range(at: 3).location == NSNotFound ? 0 : Double("0." + ns.substring(with: m.range(at: 3))) ?? 0
                return max(0, (Double(ns.substring(with: m.range(at: 1))) ?? 0) * 60 + (Double(ns.substring(with: m.range(at: 2))) ?? 0) + fraction + offset)
            }
            let words = matches.enumerated().compactMap { i, m -> LyricWord? in
                let start = NSMaxRange(m.range)
                let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
                guard end > start else { return nil } // Last tag can mark the previous word's end.
                return LyricWord(time: starts[i], duration: i + 1 < starts.count ? max(0, starts[i + 1] - starts[i]) : 0.5,
                                 text: ns.substring(with: NSRange(location: start, length: end - start)))
            }
            let headers = parse(ns.substring(to: first.range.location))
            return headers.map { LyricLine(time: max(0, $0.time + offset), text: words.map(\.text).joined(), words: words) }
        }.sorted { $0.time < $1.time }
    }

    public static func line(at elapsed: Double, in lines: [LyricLine]) -> String {
        var low = 0; var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? "" : lines[low - 1].text
    }
}
