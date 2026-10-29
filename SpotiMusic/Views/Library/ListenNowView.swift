import SwiftUI

/// Listen Now: recently played, top songs, top artists and the user's playlists.
struct ListenNowView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController

    @State private var recent: [Track] = []
    @State private var topTracks: [Track] = []
    @State private var topArtists: [Artist] = []
    @State private var errors: [String] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(title: "Listen Now", subtitle: greeting)
                if !loaded {
                    LoadingView()
                } else if recent.isEmpty && topTracks.isEmpty && topArtists.isEmpty && library.playlists.isEmpty {
                    if let error = errors.first {
                        ErrorView(message: error) { Task { await load() } }
                    } else {
                        MessageView(symbol: "play.circle", title: "Start Listening",
                                    message: "Play something on Spotify and your recent and top music will show up here.")
                    }
                } else {
                    if !recent.isEmpty {
                        Shelf(title: "Recently Played") {
                            ForEach(Array(recent.enumerated()), id: \.offset) { index, track in
                                TrackCard(track: track) { play(recent, from: index) }
                            }
                        }
                    }
                    if !topTracks.isEmpty {
                        Shelf(title: "Your Top Songs This Month") {
                            ForEach(Array(topTracks.enumerated()), id: \.offset) { index, track in
                                TrackCard(track: track) { play(topTracks, from: index) }
                            }
                        }
                    }
                    if !topArtists.isEmpty {
                        Shelf(title: "Your Top Artists") {
                            ForEach(topArtists) { ArtistCircle(artist: $0, size: 150) }
                        }
                    }
                    if !library.playlists.isEmpty {
                        Shelf(title: "Your Playlists") {
                            ForEach(library.playlists.prefix(20)) { PlaylistCard(playlist: $0, width: 160) }
                        }
                    }
                    Spacer(minLength: 24)
                }
            }
        }
        .navigationTitle("Listen Now")
        .task { if !loaded { await load() } }
    }

    private var greeting: String? {
        guard let name = library.user?.displayName, !name.isEmpty else { return nil }
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : (hour < 18 ? "afternoon" : "evening")
        return "Good \(part), \(name)"
    }

    private func play(_ tracks: [Track], from index: Int) {
        let uris = tracks[index...].compactMap(\.uri)
        Task { await player.play(uris: Array(uris)) }
    }

    private func load() async {
        errors = []
        async let recentResult: Paging<PlayHistory> = app.api.get("me/player/recently-played", query: ["limit": "50"])
        async let tracksResult: Paging<Track> = app.api.get("me/top/tracks", query: ["limit": "20", "time_range": "short_term"])
        async let artistsResult: Paging<Artist> = app.api.get("me/top/artists", query: ["limit": "20", "time_range": "medium_term"])

        do {
            var seen = Set<String>()
            recent = try await recentResult.items.map(\.track).filter { seen.insert($0.uri ?? $0.name).inserted }
        } catch { errors.append(error.localizedDescription) }
        do { topTracks = try await tracksResult.items } catch { errors.append(error.localizedDescription) }
        do { topArtists = try await artistsResult.items } catch { errors.append(error.localizedDescription) }
        loaded = true
    }
}
