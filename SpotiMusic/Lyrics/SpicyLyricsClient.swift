import Foundation

/// Optional fallback provider: https://spicylyrics.org, authenticated with the user's own API key.
/// Results are converted to TTML so am-lyrics renders them like every other source.
struct SpicyLyricsClient {
    enum SpicyError: LocalizedError {
        case unauthorized
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Spicy Lyrics rejected the API key."
            case .http(let status): return "Spicy Lyrics returned HTTP \(status)."
            }
        }
    }

    static let keychainAccount = "spicylyrics.apikey"

    static var apiKey: String? {
        get {
            Keychain.get(account: keychainAccount).flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                Keychain.delete(account: keychainAccount)
            } else {
                Keychain.set(Data(trimmed.utf8), account: keychainAccount)
            }
        }
    }

    /// Returns lyrics for a Spotify track as TTML, or nil when Spicy Lyrics has none.
    func ttml(spotifyTrackID: String, apiKey: String) async throws -> String? {
        var request = URLRequest(url: URL(string: "https://api.spicylyrics.org/v1/lyrics/\(spotifyTrackID)")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return Self.ttml(fromSpicyJSON: data)
        case 404: return nil
        case 401, 403: throw SpicyError.unauthorized
        default: throw SpicyError.http(status)
        }
    }

    // MARK: Spicy JSON → TTML

    /// Spicy Lyrics bodies are `Syllable` (word-synced), `Line` (line-synced) or `Static` (unsynced);
    /// all times are in seconds.
    static func ttml(fromSpicyJSON data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["Body"] as? [String: Any],
              let type = body["Type"] as? String else { return nil }

        var paragraphs: [String] = []
        switch type {
        case "Syllable":
            for entry in body["Content"] as? [[String: Any]] ?? [] where entry["Type"] as? String == "Vocal" {
                guard let lead = entry["Lead"] as? [String: Any] else { continue }
                let main = spans(lead["Syllables"])
                guard !main.isEmpty else { continue }
                var content = main
                for background in entry["Background"] as? [[String: Any]] ?? [] {
                    let inner = spans(background["Syllables"])
                    if !inner.isEmpty { content += " <span ttm:role=\"x-bg\">\(inner)</span>" }
                }
                paragraphs.append(paragraph(content, lead["StartTime"], lead["EndTime"], opposite: entry["OppositeAligned"] as? Bool ?? false))
            }
        case "Line":
            for entry in body["Content"] as? [[String: Any]] ?? [] where entry["Type"] as? String == "Vocal" {
                guard let text = entry["Text"] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                paragraphs.append(paragraph(escape(text), entry["StartTime"], entry["EndTime"], opposite: entry["OppositeAligned"] as? Bool ?? false))
            }
        case "Static":
            for entry in body["Lines"] as? [[String: Any]] ?? [] {
                guard let text = entry["Text"] as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                paragraphs.append("<p>\(escape(text))</p>")
            }
        default:
            return nil
        }
        guard !paragraphs.isEmpty else { return nil }

        let timing = type == "Syllable" ? "Word" : (type == "Line" ? "Line" : "None")
        return """
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" \
        xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="\(timing)">\
        <head><metadata><ttm:agent type="person" xml:id="v1"/><ttm:agent type="person" xml:id="v2"/></metadata></head>\
        <body><div>\(paragraphs.joined())</div></body></tt>
        """
    }

    private static func spans(_ value: Any?) -> String {
        let syllables = (value as? [[String: Any]] ?? []).filter { ($0["Text"] as? String)?.isEmpty == false }
        var result = ""
        for (index, syllable) in syllables.enumerated() {
            let text = escape(syllable["Text"] as? String ?? "")
            result += "<span begin=\"\(time(syllable["StartTime"]))\" end=\"\(time(syllable["EndTime"]))\">\(text)</span>"
            let partOfWord = syllable["IsPartOfWord"] as? Bool ?? false
            if !partOfWord && index < syllables.count - 1 { result += " " }
        }
        return result
    }

    private static func paragraph(_ content: String, _ start: Any?, _ end: Any?, opposite: Bool) -> String {
        "<p begin=\"\(time(start))\" end=\"\(time(end))\" ttm:agent=\"\(opposite ? "v2" : "v1")\">\(content)</p>"
    }

    private static func time(_ value: Any?) -> String {
        let seconds = (value as? NSNumber)?.doubleValue ?? 0
        return String(format: "%.3fs", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
