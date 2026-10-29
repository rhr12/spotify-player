import Foundation

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let timeMs: Int
    let text: String

    /// Lines with no words mark instrumental breaks.
    var isInterlude: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Parses LRC formatted lyrics: `[mm:ss.xx] Line text`. Supports multiple timestamps per
/// line (`[00:12.00][01:30.50] Chorus`) and skips ID tags such as `[ar:Artist]`.
enum LRCParser {
    private static let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
    private static let offsetTag = try! NSRegularExpression(pattern: #"^\[offset:\s*([+-]?\d+)\]"#, options: [.caseInsensitive, .anchorsMatchLines])

    static func parse(_ lrc: String) -> [LyricLine] {
        var offset = 0
        let whole = NSRange(lrc.startIndex..., in: lrc)
        if let match = offsetTag.firstMatch(in: lrc, range: whole), let range = Range(match.range(at: 1), in: lrc) {
            offset = Int(lrc[range]) ?? 0
        }

        var entries: [(Int, String)] = []
        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            let matches = timestamp.matches(in: rawLine, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let text = line.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: match.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                let ms = Int(((minutes * 60) + seconds) * 1000) - offset
                entries.append((max(0, ms), text))
            }
        }
        return entries
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, timeMs: $0.element.0, text: $0.element.1) }
    }

    /// Index of the line being sung at `positionMs`, or nil before the first line.
    static func index(at positionMs: Int, in lines: [LyricLine]) -> Int? {
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].timeMs <= positionMs {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
