import SwiftUI

/// Results for the sidebar search field (songs, artists, albums, playlists).
struct SearchResultsView: View {
    let query: String

    @EnvironmentObject private var app: AppState
    @State private var results: SearchResponse?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(title: "Results for “\(query)”")
                if isLoading && results == nil {
                    LoadingView()
                } else if let error, results == nil {
                    ErrorView(message: error) { Task { await search(debounce: false) } }
                } else if let results {
                    let tracks = results.tracks?.items ?? []
                    let artists = results.artists?.items ?? []
                    let albums = results.albums?.items ?? []
                    let playlists = results.playlists?.items ?? []
                    if tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty {
                        MessageView(symbol: "magnifyingglass", title: "No Results", message: "Try a different search.")
                    }
                    if !tracks.isEmpty {
                        SectionTitle(title: "Songs")
                        TrackListView(tracks: tracks, source: .trackList)
                    }
                    if !artists.isEmpty {
                        Shelf(title: "Artists") { ForEach(artists) { ArtistCircle(artist: $0) } }
                    }
                    if !albums.isEmpty {
                        Shelf(title: "Albums") { ForEach(albums) { AlbumCard(album: $0, width: 170) } }
                    }
                    if !playlists.isEmpty {
                        Shelf(title: "Playlists") { ForEach(playlists) { PlaylistCard(playlist: $0, width: 170) } }
                    }
                    Spacer(minLength: 24)
                }
            }
        }
        .navigationTitle("Search")
        .task(id: query) { await search(debounce: true) }
    }

    private func search(debounce: Bool) async {
        if debounce {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: SearchResponse = try await app.api.get("search", query: [
                "q": trimmed, "type": "track,artist,album,playlist", "limit": "10",
            ])
            guard !Task.isCancelled else { return }
            results = response
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
