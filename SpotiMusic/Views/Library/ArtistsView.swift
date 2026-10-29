import SwiftUI

/// Loads followed artists, which use cursor-based paging.
@MainActor
final class FollowedArtistsLoader: ObservableObject {
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    private let api: SpotifyClient
    private var next: URL?

    init(api: SpotifyClient) { self.api = api }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            let response: FollowedArtistsResponse = try await api.get("me/following", query: ["type": "artist", "limit": "50"])
            artists = response.artists.items
            next = response.artists.next.flatMap(URL.init(string:))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let next, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: FollowedArtistsResponse = try await api.get(absolute: next)
            artists += response.artists.items
            self.next = response.artists.next.flatMap(URL.init(string:))
        } catch {
            self.next = nil
        }
    }
}

/// Library ▸ Artists: Apple Music's two-pane layout (artist list + selected artist).
struct ArtistsView: View {
    @StateObject private var loader: FollowedArtistsLoader
    @State private var selectedID: String?
    private let api: SpotifyClient

    init(api: SpotifyClient) {
        self.api = api
        _loader = StateObject(wrappedValue: FollowedArtistsLoader(api: api))
    }

    var body: some View {
        Group {
            if let error = loader.error, loader.artists.isEmpty {
                ErrorView(message: error) { Task { await loader.reload() } }
            } else if !loader.hasLoaded {
                LoadingView()
            } else if loader.artists.isEmpty {
                MessageView(symbol: "music.mic", title: "No Artists", message: "Artists you follow on Spotify appear here.")
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedID) {
                        ForEach(loader.artists) { artist in
                            HStack(spacing: 10) {
                                ArtworkView(url: artist.images?.url(atLeast: 64), circular: true, placeholderSymbol: "music.mic")
                                    .frame(width: 32, height: 32)
                                Text(artist.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                            .tag(artist.id)
                            .onAppear {
                                if artist.id == loader.artists.last?.id { Task { await loader.loadMore() } }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(width: 250)
                    Divider()
                    if let selectedID, let artist = loader.artists.first(where: { $0.id == selectedID }) {
                        ArtistDetailView(artistID: artist.id, name: artist.name, api: api)
                            .id(artist.id)
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .navigationTitle("Artists")
        .task {
            await loader.loadIfNeeded()
            if selectedID == nil { selectedID = loader.artists.first?.id }
        }
    }
}
