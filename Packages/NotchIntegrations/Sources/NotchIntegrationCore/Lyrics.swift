import Foundation

public struct LyricLine: Equatable, Sendable {
    public let time: Double
    public let text: String
    public init(time: Double, text: String) { self.time = time; self.text = text }
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
    public static func line(at elapsed: Double, in lines: [LyricLine]) -> String {
        var low = 0; var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? "" : lines[low - 1].text
    }
}
