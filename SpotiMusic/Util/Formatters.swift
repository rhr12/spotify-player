import Foundation

enum TimeFormat {
    /// `3:07`, or `1:02:45` for long tracks.
    static func clock(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// `1 hour, 4 minutes` style summary used under album and playlist track lists.
    static func summary(_ milliseconds: Int) -> String {
        let minutes = milliseconds / 60_000
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        let hours = minutes / 60
        let rest = minutes % 60
        return "\(hours) hour\(hours == 1 ? "" : "s"), \(rest) minute\(rest == 1 ? "" : "s")"
    }

    /// `October 29, 2026` from Spotify's `YYYY`, `YYYY-MM` or `YYYY-MM-DD` release dates.
    static func releaseDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        let output = DateFormatter()
        switch value.count {
        case 10:
            parser.dateFormat = "yyyy-MM-dd"
            output.dateStyle = .long
        case 7:
            parser.dateFormat = "yyyy-MM"
            output.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        default:
            return value
        }
        return parser.date(from: value).map(output.string(from:)) ?? value
    }
}
