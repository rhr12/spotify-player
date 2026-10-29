import AppKit
import Combine
import SwiftUI

enum SidebarItem: Hashable {
    case listenNow, browse, radio
    case recentlyAdded, artists, albums, songs
    case playlist(Playlist)
}

enum Route: Hashable {
    case album(Album)
    case artist(id: String, name: String)
    case playlist(Playlist)
    case genre(String)
}

/// Owns every long-lived service and the window's navigation state.
@MainActor
final class AppState: ObservableObject {
    let auth: SpotifyAuth
    let api: SpotifyClient
    let web: WebPlaybackHost
    let player: PlayerController
    let lyrics: LyricsStore
    let library: LibraryStore
    let theme: ArtworkTheme

    @Published var selection: SidebarItem? = .songs {
        didSet { if oldValue != selection { path = [] } }
    }
    @Published var path: [Route] = []
    @Published var searchText = ""
    @Published var showNowPlaying = false
    @Published var showLyrics = false
    @Published private(set) var toast: String?

    private var cancellables: Set<AnyCancellable> = []
    private var toastTask: Task<Void, Never>?
    private var keyMonitor: Any?

    init() {
        auth = SpotifyAuth()
        api = SpotifyClient(auth: auth)
        web = WebPlaybackHost()
        player = PlayerController(api: api, web: web)
        lyrics = LyricsStore()
        library = LibraryStore(api: api)
        theme = ArtworkTheme()

        web.tokenProvider = { [weak auth = self.auth] in
            guard let auth else { throw SpotifyAuth.AuthError.notSignedIn }
            return try await auth.validAccessToken()
        }

        auth.$isAuthorized
            .removeDuplicates()
            .sink { [weak self] authorized in
                DispatchQueue.main.async { self?.authorizationChanged(authorized) }
            }
            .store(in: &cancellables)

        player.$track
            .removeDuplicates { $0?.uri == $1?.uri }
            .sink { [weak self] track in
                self?.lyrics.load(for: track)
                self?.theme.update(for: track)
            }
            .store(in: &cancellables)

        player.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                DispatchQueue.main.async {
                    self?.showToast(message)
                    self?.player.errorMessage = nil
                }
            }
            .store(in: &cancellables)

        installKeyMonitor()
    }

    private func authorizationChanged(_ authorized: Bool) {
        if authorized {
            web.start()
            player.startPolling()
            Task { await library.loadInitial() }
        } else {
            web.stop()
            player.reset()
            library.reset()
            showNowPlaying = false
            showLyrics = false
            selection = .songs
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = nil }
    }

    func open(_ route: Route) {
        path.append(route)
    }

    func openArtist(of track: Track) {
        guard let artist = track.artists.first, let id = artist.id else { return }
        showNowPlaying = false
        open(.artist(id: id, name: artist.name))
    }

    func openAlbum(of track: Track) {
        guard let album = track.album, !album.id.isEmpty else { return }
        showNowPlaying = false
        open(.album(album))
    }

    func toggleLyrics() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showLyrics.toggle() }
    }

    func toggleNowPlaying() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { showNowPlaying.toggle() }
    }

    /// Space toggles playback unless a text field is being edited (matching Apple Music).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.auth.isAuthorized,
                  event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(event.window?.firstResponder is NSText),
                  event.window?.attachedSheet == nil
            else { return event }
            Task { await self.player.togglePlayPause() }
            return nil
        }
    }
}
