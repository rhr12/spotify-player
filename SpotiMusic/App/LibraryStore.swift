import Foundation

/// The signed-in user and their playlists (shown in the sidebar).
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var user: UserProfile?
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var playlistsError: String?
    @Published private(set) var isLoadingPlaylists = false

    let api: SpotifyClient

    init(api: SpotifyClient) {
        self.api = api
    }

    func loadInitial() async {
        async let profile: Void = loadUser()
        async let lists: Void = loadPlaylists()
        _ = await (profile, lists)
    }

    func reset() {
        user = nil
        playlists = []
        playlistsError = nil
    }

    func loadUser() async {
        user = try? await api.get("me")
    }

    func loadPlaylists() async {
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        do {
            playlists = try await api.allPages("me/playlists", query: ["limit": "50"], maxItems: 1000)
            playlistsError = nil
        } catch {
            playlistsError = error.localizedDescription
        }
    }

    func createPlaylist(named name: String) async throws -> Playlist {
        let playlist: Playlist = try await api.post("me/playlists", json: ["name": name, "public": false])
        playlists.insert(playlist, at: 0)
        return playlist
    }
}

/// Loads a Spotify paging object one page at a time (infinite scrolling).
@MainActor
final class PagedLoader<T: Decodable>: ObservableObject {
    @Published private(set) var items: [T] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var total: Int?
    @Published private(set) var hasLoaded = false

    private let api: SpotifyClient
    private var path: String
    private let query: [String: String]
    private let fallbackPath: String?
    private var nextURL: URL?

    init(api: SpotifyClient, path: String, query: [String: String] = [:], fallbackPath: String? = nil) {
        self.api = api
        self.path = path
        self.query = query
        self.fallbackPath = fallbackPath
    }

    var hasMore: Bool { nextURL != nil }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page: Paging<T>
            do {
                page = try await api.get(path, query: query)
            } catch let apiError as SpotifyClient.APIError where [403, 404].contains(apiError.status) && fallbackPath != nil {
                path = fallbackPath!
                page = try await api.get(path, query: query)
            }
            items = page.items
            total = page.total
            nextURL = page.next.flatMap(URL.init(string:))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        hasLoaded = true
    }

    func loadMore() async {
        guard let nextURL, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page: Paging<T> = try await api.get(absolute: nextURL)
            items += page.items
            self.nextURL = page.next.flatMap(URL.init(string:))
        } catch {
            self.error = error.localizedDescription
            self.nextURL = nil
        }
    }
}
