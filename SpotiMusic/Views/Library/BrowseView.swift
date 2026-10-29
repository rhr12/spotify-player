import SwiftUI

/// Browse: genre tiles that open live Spotify search results for each genre.
struct BrowseView: View {
    @EnvironmentObject private var app: AppState

    static let genres: [(name: String, colors: [Color])] = [
        ("Pop", [Color(red: 0.98, green: 0.36, blue: 0.55), Color(red: 0.86, green: 0.18, blue: 0.40)]),
        ("Hip-Hop", [Color(red: 0.98, green: 0.62, blue: 0.20), Color(red: 0.90, green: 0.36, blue: 0.10)]),
        ("Rock", [Color(red: 0.45, green: 0.45, blue: 0.50), Color(red: 0.20, green: 0.20, blue: 0.24)]),
        ("Indie", [Color(red: 0.38, green: 0.75, blue: 0.62), Color(red: 0.12, green: 0.52, blue: 0.45)]),
        ("Electronic", [Color(red: 0.36, green: 0.52, blue: 0.98), Color(red: 0.20, green: 0.24, blue: 0.80)]),
        ("R&B", [Color(red: 0.70, green: 0.40, blue: 0.95), Color(red: 0.45, green: 0.18, blue: 0.75)]),
        ("Jazz", [Color(red: 0.25, green: 0.60, blue: 0.85), Color(red: 0.10, green: 0.35, blue: 0.60)]),
        ("Classical", [Color(red: 0.80, green: 0.66, blue: 0.45), Color(red: 0.58, green: 0.44, blue: 0.26)]),
        ("Country", [Color(red: 0.90, green: 0.55, blue: 0.35), Color(red: 0.68, green: 0.33, blue: 0.18)]),
        ("Latin", [Color(red: 0.99, green: 0.45, blue: 0.35), Color(red: 0.85, green: 0.20, blue: 0.25)]),
        ("Metal", [Color(red: 0.35, green: 0.30, blue: 0.32), Color(red: 0.10, green: 0.08, blue: 0.10)]),
        ("K-Pop", [Color(red: 0.98, green: 0.50, blue: 0.80), Color(red: 0.72, green: 0.30, blue: 0.90)]),
        ("Folk", [Color(red: 0.62, green: 0.70, blue: 0.40), Color(red: 0.40, green: 0.50, blue: 0.22)]),
        ("Soul", [Color(red: 0.90, green: 0.40, blue: 0.30), Color(red: 0.60, green: 0.20, blue: 0.20)]),
        ("Reggae", [Color(red: 0.30, green: 0.75, blue: 0.35), Color(red: 0.95, green: 0.75, blue: 0.20)]),
        ("Blues", [Color(red: 0.25, green: 0.40, blue: 0.80), Color(red: 0.10, green: 0.18, blue: 0.45)]),
        ("Dance", [Color(red: 0.20, green: 0.80, blue: 0.85), Color(red: 0.15, green: 0.45, blue: 0.85)]),
        ("Punk", [Color(red: 0.95, green: 0.25, blue: 0.30), Color(red: 0.30, green: 0.05, blue: 0.10)]),
        ("Ambient", [Color(red: 0.55, green: 0.70, blue: 0.85), Color(red: 0.30, green: 0.40, blue: 0.60)]),
        ("Lo-Fi", [Color(red: 0.75, green: 0.60, blue: 0.80), Color(red: 0.45, green: 0.38, blue: 0.62)]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(title: "Browse", subtitle: "Explore artists, songs and playlists by genre")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 18)], spacing: 18) {
                    ForEach(Self.genres, id: \.name) { genre in
                        GenreTile(name: genre.name, colors: genre.colors)
                            .onTapGesture { app.open(.genre(genre.name)) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Browse")
    }
}

private struct GenreTile: View {
    let name: String
    let colors: [Color]
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.quarternote.3")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white.opacity(0.14))
                .rotationEffect(.degrees(-12))
                .offset(x: 120, y: -28)
            Text(name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(14)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(hovering ? 0.25 : 0.12), radius: hovering ? 10 : 5, y: 3)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

/// Live Spotify search results for one genre.
struct GenreView: View {
    let genre: String

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @State private var tracks: [Track] = []
    @State private var artists: [Artist] = []
    @State private var playlists: [Playlist] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(title: genre)
                if !loaded {
                    LoadingView()
                } else if let error, tracks.isEmpty && artists.isEmpty && playlists.isEmpty {
                    ErrorView(message: error) { Task { await load() } }
                } else {
                    if !artists.isEmpty {
                        Shelf(title: "Artists") { ForEach(artists) { ArtistCircle(artist: $0) } }
                    }
                    if !playlists.isEmpty {
                        Shelf(title: "Playlists") { ForEach(playlists) { PlaylistCard(playlist: $0, width: 170) } }
                    }
                    if !tracks.isEmpty {
                        SectionTitle(title: "Songs")
                        TrackListView(tracks: tracks, source: .trackList)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle(genre)
        .task(id: genre) { if !loaded { await load() } }
    }

    private func load() async {
        let tag = "genre:\"\(genre.lowercased())\""
        async let genreResults: SearchResponse = app.api.get("search", query: ["q": tag, "type": "track,artist", "limit": "10"])
        async let moreTracks: SearchResponse = app.api.get("search", query: ["q": tag, "type": "track", "limit": "10", "offset": "10"])
        async let playlistResults: SearchResponse = app.api.get("search", query: ["q": genre, "type": "playlist", "limit": "10"])
        do {
            let first = try await genreResults
            artists = first.artists?.items ?? []
            tracks = first.tracks?.items ?? []
            if let more = try? await moreTracks { tracks += more.tracks?.items ?? [] }
            playlists = (try? await playlistResults)?.playlists?.items ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}
