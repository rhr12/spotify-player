import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject private var player: PlayerController
    @StateObject private var loader: PagedLoader<PlaylistEntry>

    init(playlist: Playlist, api: SpotifyClient) {
        self.playlist = playlist
        // `/items` replaced `/tracks` in the February 2026 Web API; fall back for older apps.
        _loader = StateObject(wrappedValue: PagedLoader(
            api: api,
            path: "playlists/\(playlist.id)/items",
            query: ["limit": "50", "additional_types": "track"],
            fallbackPath: "playlists/\(playlist.id)/tracks"
        ))
    }

    private var tracks: [Track] { loader.items.compactMap(\.track) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CollectionHeader(
                    artworkURL: playlist.images?.largeURL,
                    title: playlist.name,
                    subtitle: playlist.owner?.displayName ?? "Playlist",
                    meta: (loader.total ?? playlist.itemCount).map { "\($0) SONGS" } ?? "",
                    description: playlist.plainDescription,
                    placeholderSymbol: "music.note.list",
                    onPlay: { Task { await player.play(contextURI: playlist.uri) } },
                    onShuffle: { Task { await player.play(contextURI: playlist.uri, shuffle: true) } }
                )
                if let error = loader.error, loader.items.isEmpty {
                    ErrorView(message: error) { Task { await loader.reload() } }
                } else if loader.items.isEmpty && (loader.isLoading || !loader.hasLoaded) {
                    LoadingView()
                } else if tracks.isEmpty {
                    MessageView(symbol: "music.note.list", title: "This Playlist Is Empty", message: "Add songs to it in Spotify.")
                } else {
                    TrackListView(tracks: tracks, source: .context(playlist.uri),
                                  onReachEnd: { Task { await loader.loadMore() } })
                    if loader.isLoading { LoadingView().frame(minHeight: 60) }
                    Text("\(loader.total ?? tracks.count) songs, \(TimeFormat.summary(tracks.reduce(0) { $0 + $1.durationMs }))\(loader.hasMore ? "+" : "")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 18)
                }
            }
        }
        .navigationTitle(playlist.name)
        .task(id: playlist.id) { await loader.loadIfNeeded() }
    }
}
