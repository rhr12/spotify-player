import SwiftUI

/// Library ▸ Songs: the user's Liked Songs as an Apple Music song table.
struct SongsView: View {
    @StateObject private var loader: PagedLoader<SavedTrack>
    @EnvironmentObject private var player: PlayerController

    init(api: SpotifyClient) {
        _loader = StateObject(wrappedValue: PagedLoader(api: api, path: "me/tracks", query: ["limit": "50"]))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .bottom) {
                    PageTitle(title: "Songs", subtitle: loader.total.map { "\($0) songs" })
                    if !loader.items.isEmpty {
                        PlayShuffleButtons(
                            onPlay: { Task { await player.playInOrder(tracks) } },
                            onShuffle: { Task { await player.shuffle(tracks) } }
                        )
                        .padding(.trailing, 24)
                        .padding(.bottom, 14)
                    }
                }
                content
            }
        }
        .navigationTitle("Songs")
        .task { await loader.loadIfNeeded() }
    }

    private var tracks: [Track] { loader.items.map(\.track) }

    @ViewBuilder
    private var content: some View {
        if let error = loader.error, loader.items.isEmpty {
            ErrorView(message: error) { Task { await loader.reload() } }
        } else if loader.items.isEmpty && (loader.isLoading || !loader.hasLoaded) {
            LoadingView()
        } else if loader.items.isEmpty {
            MessageView(symbol: "music.note", title: "No Songs", message: "Songs you like on Spotify appear here.")
        } else {
            TrackListView(tracks: tracks, source: .trackList, onReachEnd: { Task { await loader.loadMore() } })
            if loader.isLoading { LoadingView().frame(minHeight: 60) }
        }
    }
}
