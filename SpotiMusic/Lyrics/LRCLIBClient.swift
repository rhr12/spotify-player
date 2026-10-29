import Foundation

/// Client for https://lrclib.net — a free lyrics database that needs no API key.
struct LRCLIBClient {
    struct Record: Decodable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": "SpotiMusic/1.0 (https://github.com/rhr12/spotify-player)"]
        return URLSession(configuration: configuration)
    }()

    /// Exact signature match first (`/api/get`), then a fuzzy `/api/search` fallback.
    func lyrics(title: String, artist: String, album: String?, durationSeconds: Int) async throws -> Record? {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            .init(name: "track_name", value: title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: album ?? ""),
            .init(name: "duration", value: String(durationSeconds)),
        ]
        let (data, response) = try await session.data(from: get.url!)
        if (response as? HTTPURLResponse)?.statusCode == 200,
           let record = try? JSONDecoder().decode(Record.self, from: data),
           record.syncedLyrics != nil || record.plainLyrics != nil || record.instrumental == true {
            return record
        }

        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            .init(name: "track_name", value: Self.cleanTitle(title)),
            .init(name: "artist_name", value: artist),
        ]
        let (searchData, searchResponse) = try await session.data(from: search.url!)
        guard (searchResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let results = (try? JSONDecoder().decode([Record].self, from: searchData)) ?? []
        let close = results.filter { abs(($0.duration ?? Double(durationSeconds)) - Double(durationSeconds)) <= 4 }
        return close.first { $0.syncedLyrics != nil } ?? close.first { $0.plainLyrics != nil } ?? close.first
    }

    /// Strips suffixes such as " - Remastered 2011" or " (feat. X)" that rarely appear in LRCLIB titles.
    static func cleanTitle(_ title: String) -> String {
        var cleaned = title
        if let dash = cleaned.range(of: " - ") { cleaned = String(cleaned[..<dash.lowerBound]) }
        cleaned = cleaned.replacingOccurrences(of: #"\s*[\(\[](feat|ft|with)\.?[^\)\]]*[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}
