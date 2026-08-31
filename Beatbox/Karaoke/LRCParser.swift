import Foundation

nonisolated enum LRCParser {
    static func parse(_ contents: String) -> [LyricCue] {
        var offset: TimeInterval = 0
        var cues: [LyricCue] = []

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsedOffset = parseOffset(line) {
                offset = parsedOffset
                continue
            }

            let matches = timestampExpression.matches(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            )
            guard !matches.isEmpty else { continue }

            let lyricStart = matches.reduce(0) { partialResult, match in
                max(partialResult, match.range.location + match.range.length)
            }
            let lyricIndex = String.Index(utf16Offset: lyricStart, in: line)
            let text = String(line[lyricIndex...]).trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard match.numberOfRanges == 3,
                      let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minuteRange]),
                      let seconds = Double(line[secondRange])
                else { continue }
                cues.append(LyricCue(
                    time: max(0, minutes * 60 + seconds + offset),
                    text: text
                ))
            }
        }

        return cues.sorted { left, right in
            if left.time == right.time { return left.text < right.text }
            return left.time < right.time
        }
    }

    static func parseFile(at url: URL) throws -> [LyricCue] {
        let data = try Data(contentsOf: url)
        guard let contents = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
        else {
            throw LRCParserError.unsupportedEncoding
        }
        return parse(contents)
    }

    private static func parseOffset(_ line: String) -> TimeInterval? {
        let prefix = "[offset:"
        guard line.lowercased().hasPrefix(prefix), line.hasSuffix("]") else { return nil }
        let valueStart = line.index(line.startIndex, offsetBy: prefix.count)
        let valueEnd = line.index(before: line.endIndex)
        guard let milliseconds = Double(line[valueStart..<valueEnd]) else { return nil }
        return milliseconds / 1_000
    }

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"\[(\d+):(\d{1,2}(?:\.\d{1,3})?)\]"#
    )
}

nonisolated enum LRCParserError: LocalizedError {
    case unsupportedEncoding

    var errorDescription: String? {
        "歌词文件不是 Beatbox 支持的 UTF-8 或 UTF-16 编码。"
    }
}
