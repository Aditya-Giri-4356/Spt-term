import Foundation

/// Pure parser for LRC (Lyric) format strings.
public struct STLRCParser {
    public struct Line: Equatable, Hashable {
        public let time: Double
        public let text: String

        public init(time: Double, text: String) {
            self.time = time
            self.text = text
        }
    }

    /// Parses an LRC string and returns sorted timestamped lines.
    /// Handles:
    /// - [mm:ss.xx] (centiseconds)
    /// - [mm:ss.xxx] (milliseconds)
    /// - Multiple timestamps per line (e.g. [00:10.00][00:20.00]Chorus)
    /// - Metadata tags like [ar:], [ti:], [al:], [offset:]
    /// - Empty lines and whitespace
    /// - Unsorted input lines (output is always sorted ascending by time)
    public static func parse(_ lrc: String) -> [Line] {
        guard !lrc.isEmpty else { return [] }

        var result: [Line] = []
        let rawLines = lrc.components(separatedBy: .newlines)

        // Pattern matching: [mm:ss.xx] or [mm:ss.xxx] or [m:s.x]
        // Group 1: minutes, Group 2: seconds, Group 3: fractional part
        let timestampPattern = #"(?:\[(\d{1,3}):(\d{1,2})(?:\.(\d{1,3}))?\])"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else {
            return []
        }

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsString = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))
            guard !matches.isEmpty else {
                // If there are no timestamps (e.g. metadata tags like [ar:Beatles], [ti:Title], or plain text), skip
                continue
            }

            // Extract lyric text after stripping all timestamp tags
            var text = regex.stringByReplacingMatches(
                in: line,
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: ""
            )
            text = text.trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let minStr = nsString.substring(with: match.range(at: 1))
                let secStr = nsString.substring(with: match.range(at: 2))

                let minutes = Double(minStr) ?? 0.0
                let seconds = Double(secStr) ?? 0.0

                var fraction = 0.0
                if match.numberOfRanges >= 4 && match.range(at: 3).location != NSNotFound {
                    let fracStr = nsString.substring(with: match.range(at: 3))
                    if !fracStr.isEmpty {
                        fraction = Double("0." + fracStr) ?? 0.0
                    }
                }

                let totalSeconds = minutes * 60.0 + seconds + fraction
                result.append(Line(time: totalSeconds, text: text))
            }
        }

        return result.sorted { $0.time < $1.time }
    }

    /// Convenience converter to Track's internal LyricsLine model.
    static func parseToLyricsLines(_ lrc: String) -> [LyricsLine] {
        return parse(lrc).map { LyricsLine(time: $0.time, text: $0.text) }
    }
}
