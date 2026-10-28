import Foundation

/// A paragraph split around TeX math: `$$…$$` is display math, `$…$` is
/// inline. Split before the inline Markdown parser sees the text, which
/// would otherwise eat the `_`, `*` and `\` the TeX depends on.
public enum MarkdownMathSegment: Equatable, Sendable {
    case text(String)
    case inline(String)
    case display(String)
}

public enum MarkdownMath {
    /// Inline math follows Pandoc's rule so prices stay text ("$5 and $10"):
    /// the opening `$` is followed by a non-space, the closing one follows a
    /// non-space and isn't followed by a digit, and it stays on one line.
    /// Code spans and `\$` are left alone; an unclosed delimiter (a reply
    /// still streaming) stays text.
    public static func segments(_ text: String) -> [MarkdownMathSegment] {
        guard text.contains("$") else { return [.text(text)] }
        let chars = Array(text)
        var result: [MarkdownMathSegment] = []
        var buffer = ""
        var i = 0

        func flush() {
            if !buffer.isEmpty { result.append(.text(buffer)) }
            buffer = ""
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                buffer.append(c)
                buffer.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "`" {
                var run = 0
                while i + run < chars.count, chars[i + run] == "`" { run += 1 }
                let end = find(Array(repeating: "`", count: run), in: chars, from: i + run).map { $0 + run } ?? i + run
                buffer.append(contentsOf: chars[i..<end])
                i = end
                continue
            }
            if c == "$", i + 1 < chars.count, chars[i + 1] == "$" {
                if let close = find(["$", "$"], in: chars, from: i + 2) {
                    let body = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty {
                        flush()
                        result.append(.display(body))
                        i = close + 2
                        continue
                    }
                }
                buffer.append("$$")
                i += 2
                continue
            }
            if c == "$", let close = inlineClose(chars, from: i + 1) {
                flush()
                result.append(.inline(String(chars[(i + 1)..<close])))
                i = close + 1
                continue
            }
            buffer.append(c)
            i += 1
        }
        flush()
        return result
    }

    private static func inlineClose(_ chars: [Character], from start: Int) -> Int? {
        guard start < chars.count, !chars[start].isWhitespace, chars[start] != "$" else { return nil }
        var j = start
        while j < chars.count {
            let c = chars[j]
            if c.isNewline { return nil }
            if c == "\\" {
                j += 2
                continue
            }
            if c == "$", j > start, !chars[j - 1].isWhitespace,
               j + 1 == chars.count || !chars[j + 1].isNumber {
                return j
            }
            j += 1
        }
        return nil
    }

    private static func find(_ needle: [Character], in chars: [Character], from start: Int) -> Int? {
        guard needle.count <= chars.count else { return nil }
        var j = start
        while j + needle.count <= chars.count {
            if chars[j..<(j + needle.count)].elementsEqual(needle) { return j }
            j += 1
        }
        return nil
    }
}
