import Foundation

// Spotify Web API models. Fields are optional wherever Spotify may omit them
// (the February 2026 Web API changes removed several fields for Development Mode apps).

struct SpotifyImage: Codable, Hashable {
    let url: String
    let width: Int?
    let height: Int?
}

extension Array where Element == SpotifyImage {
    /// The largest image, for hero artwork.
    var largeURL: URL? {
        (self.max { ($0.width ?? 0) < ($1.width ?? 0) }).flatMap { URL(string: $0.url) }
    }

    /// The smallest image that is at least `minimum` pixels wide, for thumbnails.
    func url(atLeast minimum: Int) -> URL? {
        let sorted = self.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        let match = sorted.first { ($0.width ?? 0) >= minimum } ?? sorted.last
        return match.flatMap { URL(string: $0.url) }
    }
}

/// Decodes an element if possible and yields `nil` otherwise, so one malformed or
/// `null` entry doesn't fail a whole page.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct Paging<T: Decodable>: Decodable {
    let items: [T]
    let next: String?
    let total: Int?

    private enum CodingKeys: String, CodingKey { case items, next, total }

    init(items: [T], next: String?, total: Int?) {
        self.items = items
        self.next = next
        self.total = total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try container.decodeIfPresent([Lossy<T>].self, forKey: .items) ?? []).compactMap(\.value)
        next = try container.decodeIfPresent(String.self, forKey: .next)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
    }
}

struct SimpleArtist: Codable, Hashable {
    let id: String?
    let name: String
    let uri: String?
}

struct Album: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?
    let artists: [SimpleArtist]?
    let releaseDate: String?
    let totalTracks: Int?
    let albumType: String?
    let genres: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, images, artists, genres
        case releaseDate = "release_date"
        case totalTracks = "total_tracks"
        case albumType = "album_type"
    }

    var artistLine: String { (artists ?? []).map(\.name).joined(separator: ", ") }
    var year: String? { releaseDate.map { String($0.prefix(4)) } }
}

struct Artist: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?
    let genres: [String]?
}

struct Track: Codable, Hashable {
    let id: String?
    let name: String
    let uri: String?
    let durationMs: Int
    let artists: [SimpleArtist]
    var album: Album?
    let explicit: Bool?
    let trackNumber: Int?
    let isLocal: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, artists, album, explicit
        case durationMs = "duration_ms"
        case trackNumber = "track_number"
        case isLocal = "is_local"
    }

    init(id: String?, name: String, uri: String?, durationMs: Int, artists: [SimpleArtist], album: Album?,
         explicit: Bool? = nil, trackNumber: Int? = nil, isLocal: Bool? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
        self.durationMs = durationMs
        self.artists = artists
        self.album = album
        self.explicit = explicit
        self.trackNumber = trackNumber
        self.isLocal = isLocal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        uri = try c.decodeIfPresent(String.self, forKey: .uri)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        artists = (try? c.decodeIfPresent([SimpleArtist].self, forKey: .artists)) ?? []
        album = try? c.decodeIfPresent(Album.self, forKey: .album)
        explicit = try c.decodeIfPresent(Bool.self, forKey: .explicit)
        trackNumber = try c.decodeIfPresent(Int.self, forKey: .trackNumber)
        isLocal = try c.decodeIfPresent(Bool.self, forKey: .isLocal)
    }

    var artistLine: String { artists.map(\.name).joined(separator: ", ") }
    var isPlayable: Bool { uri != nil && isLocal != true }
}

struct SavedTrack: Decodable {
    let addedAt: String?
    let track: Track
    enum CodingKeys: String, CodingKey { case track; case addedAt = "added_at" }
}

struct SavedAlbum: Decodable {
    let addedAt: String?
    let album: Album
    enum CodingKeys: String, CodingKey { case album; case addedAt = "added_at" }
}

/// Playlist entries were renamed from `track` to `item` in the February 2026 API; accept both.
struct PlaylistEntry: Decodable {
    let addedAt: String?
    let track: Track?
    enum CodingKeys: String, CodingKey { case item, track; case addedAt = "added_at" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addedAt = try c.decodeIfPresent(String.self, forKey: .addedAt)
        track = (try? c.decodeIfPresent(Track.self, forKey: .item)) ?? (try? c.decodeIfPresent(Track.self, forKey: .track))
    }
}

struct PlayHistory: Decodable {
    let track: Track
    let playedAt: String?
    enum CodingKeys: String, CodingKey { case track; case playedAt = "played_at" }
}

struct UserProfile: Decodable {
    let id: String
    let displayName: String?
    let images: [SpotifyImage]?
    enum CodingKeys: String, CodingKey { case id, images; case displayName = "display_name" }
}

struct Playlist: Decodable, Hashable, Identifiable {
    struct Owner: Decodable, Hashable {
        let id: String
        let displayName: String?
        enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
    }
    struct Count: Decodable, Hashable { let total: Int? }

    let id: String
    let name: String
    let uri: String
    let description: String?
    let images: [SpotifyImage]?
    let owner: Owner?
    let itemCount: Int?

    enum CodingKeys: String, CodingKey { case id, name, uri, description, images, owner, items, tracks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        uri = try c.decode(String.self, forKey: .uri)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        images = try? c.decodeIfPresent([SpotifyImage].self, forKey: .images)
        owner = try? c.decodeIfPresent(Owner.self, forKey: .owner)
        let count = (try? c.decodeIfPresent(Count.self, forKey: .items)) ?? (try? c.decodeIfPresent(Count.self, forKey: .tracks))
        itemCount = count?.total
    }

    /// Spotify descriptions may contain HTML entities and anchor tags.
    var plainDescription: String? {
        guard let description, !description.isEmpty else { return nil }
        var text = description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in ["&amp;": "&", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&#x2F;": "/"] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
    }
}

struct Device: Decodable, Hashable, Identifiable {
    let deviceID: String?
    let name: String
    let type: String
    let isActive: Bool
    let isRestricted: Bool?
    let volumePercent: Int?
    let supportsVolume: Bool?

    var id: String { deviceID ?? name }

    enum CodingKeys: String, CodingKey {
        case name, type
        case deviceID = "id"
        case isActive = "is_active"
        case isRestricted = "is_restricted"
        case volumePercent = "volume_percent"
        case supportsVolume = "supports_volume"
    }

    var symbolName: String {
        switch type.lowercased() {
        case "computer": return "laptopcomputer"
        case "smartphone": return "iphone"
        case "tablet": return "ipad"
        case "speaker": return "hifispeaker"
        case "tv": return "tv"
        case "avr", "stb": return "hifireceiver"
        case "automobile": return "car"
        case "game_console": return "gamecontroller"
        default: return "speaker.wave.2"
        }
    }
}

struct DevicesResponse: Decodable { let devices: [Device] }

struct PlaybackState: Decodable {
    struct Context: Decodable { let uri: String? }
    let device: Device?
    let shuffleState: Bool?
    let repeatState: String?
    let progressMs: Int?
    let isPlaying: Bool
    let item: Track?
    let context: Context?

    enum CodingKeys: String, CodingKey {
        case device, item, context
        case shuffleState = "shuffle_state"
        case repeatState = "repeat_state"
        case progressMs = "progress_ms"
        case isPlaying = "is_playing"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = try? c.decodeIfPresent(Device.self, forKey: .device)
        shuffleState = try c.decodeIfPresent(Bool.self, forKey: .shuffleState)
        repeatState = try c.decodeIfPresent(String.self, forKey: .repeatState)
        progressMs = try c.decodeIfPresent(Int.self, forKey: .progressMs)
        isPlaying = try c.decodeIfPresent(Bool.self, forKey: .isPlaying) ?? false
        item = try? c.decodeIfPresent(Track.self, forKey: .item)
        context = try? c.decodeIfPresent(Context.self, forKey: .context)
    }
}

struct SearchResponse: Decodable {
    let tracks: Paging<Track>?
    let albums: Paging<Album>?
    let artists: Paging<Artist>?
    let playlists: Paging<Playlist>?
}

struct FollowedArtistsResponse: Decodable {
    struct Page: Decodable {
        let items: [Artist]
        let next: String?
        let total: Int?

        private enum CodingKeys: String, CodingKey { case items, next, total }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            items = (try c.decodeIfPresent([Lossy<Artist>].self, forKey: .items) ?? []).compactMap(\.value)
            next = try c.decodeIfPresent(String.self, forKey: .next)
            total = try c.decodeIfPresent(Int.self, forKey: .total)
        }
    }
    let artists: Page
}

/// Playback modes as expressed by Spotify's `repeat_state`.
enum RepeatMode: String {
    case off, context, track

    var next: RepeatMode {
        switch self {
        case .off: return .context
        case .context: return .track
        case .track: return .off
        }
    }
}
