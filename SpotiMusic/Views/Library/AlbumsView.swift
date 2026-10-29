import SwiftUI

/// Library ▸ Albums: saved albums in a grid.
struct AlbumsView: View {
    @StateObject private var loader: PagedLoader<SavedAlbum>

    init(api: SpotifyClient) {
        _loader = StateObject(wrappedValue: PagedLoader(api: api, path: "me/albums", query: ["limit": "50"]))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PageTitle(title: "Albums", subtitle: loader.total.map { "\($0) albums" })
                if let error = loader.error, loader.items.isEmpty {
                    ErrorView(message: error) { Task { await loader.reload() } }
                } else if loader.items.isEmpty && (loader.isLoading || !loader.hasLoaded) {
                    LoadingView()
                } else if loader.items.isEmpty {
                    MessageView(symbol: "square.stack", title: "No Albums", message: "Albums you save on Spotify appear here.")
                } else {
                    AlbumGrid(items: loader.items.map(\.album), onReachEnd: { Task { await loader.loadMore() } }) { album in
                        AlbumCard(album: album)
                    }
                }
            }
        }
        .navigationTitle("Albums")
        .task { await loader.loadIfNeeded() }
    }
}

/// Library ▸ Recently Added: newest saved albums and liked songs.
struct RecentlyAddedView: View {
    @StateObject private var albums: PagedLoader<SavedAlbum>
    @StateObject private var songs: PagedLoader<SavedTrack>

    init(api: SpotifyClient) {
        _albums = StateObject(wrappedValue: PagedLoader(api: api, path: "me/albums", query: ["limit": "50"]))
        _songs = StateObject(wrappedValue: PagedLoader(api: api, path: "me/tracks", query: ["limit": "20"]))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(title: "Recently Added")
                if albums.items.isEmpty && songs.items.isEmpty {
                    if let error = albums.error ?? songs.error {
                        ErrorView(message: error) { Task { await reload() } }
                    } else if !albums.hasLoaded || !songs.hasLoaded {
                        LoadingView()
                    } else {
                        MessageView(symbol: "clock", title: "Nothing Added Yet", message: "Albums and songs you save on Spotify appear here.")
                    }
                } else {
                    if !albums.items.isEmpty {
                        SectionTitle(title: "Albums")
                        AlbumGrid(items: albums.items.map(\.album)) { album in AlbumCard(album: album) }
                    }
                    if !songs.items.isEmpty {
                        SectionTitle(title: "Songs")
                        TrackListView(tracks: songs.items.map(\.track), source: .trackList)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationTitle("Recently Added")
        .task { await reload(onlyIfNeeded: true) }
    }

    private func reload(onlyIfNeeded: Bool = false) async {
        if onlyIfNeeded {
            async let a: Void = albums.loadIfNeeded()
            async let s: Void = songs.loadIfNeeded()
            _ = await (a, s)
        } else {
            async let a: Void = albums.reload()
            async let s: Void = songs.reload()
            _ = await (a, s)
        }
    }
}
