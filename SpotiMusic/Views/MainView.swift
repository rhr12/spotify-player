import SwiftUI
import WebKit

struct RootView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @AppStorage("appearance") private var appearance = Appearance.light.rawValue

    var body: some View {
        Group {
            if auth.isAuthorized {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .onAppear { Appearance.apply(appearance) }
        .onChange(of: appearance) { Appearance.apply($0) }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static func apply(_ raw: String) {
        switch Appearance(rawValue: raw) ?? .light {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            // The Web Playback SDK needs a live, in-window web view; it is 1pt and fully transparent.
            WebPlayerView(webView: app.web.webView)
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
                } detail: {
                    DetailContainer()
                }
                .searchable(text: $app.searchText, placement: .sidebar, prompt: "Search")
                .toolbar(app.showNowPlaying ? .hidden : .visible, for: .windowToolbar)

                PlayerBarView()
            }

            if app.showNowPlaying {
                NowPlayingView()
                    .ignoresSafeArea()
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }

            if let toast = app.toast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.accentColor)
                        Text(toast).font(.system(size: 12)).lineLimit(3)
                        Button { app.dismissToast() } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .frame(maxWidth: 520)
                    .padding(.bottom, 84)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }
        }
    }
}

private struct DetailContainer: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            NavigationStack(path: $app.path) {
                root
                    .navigationDestination(for: Route.self) { route in
                        destination(route)
                    }
            }
            .frame(maxWidth: .infinity)

            if app.showLyrics && !app.showNowPlaying {
                LyricsPanelView()
                    .frame(width: 340)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    @ViewBuilder
    private var root: some View {
        if !app.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResultsView(query: app.searchText)
        } else {
            switch app.selection ?? .songs {
            case .listenNow: ListenNowView()
            case .browse: BrowseView()
            case .radio: RadioView()
            case .recentlyAdded: RecentlyAddedView(api: app.api)
            case .artists: ArtistsView(api: app.api)
            case .albums: AlbumsView(api: app.api)
            case .songs: SongsView(api: app.api)
            case .playlist(let playlist): PlaylistDetailView(playlist: playlist, api: app.api).id(playlist.id)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .album(let album): AlbumDetailView(album: album)
        case .artist(let id, let name): ArtistDetailView(artistID: id, name: name, api: app.api)
        case .playlist(let playlist): PlaylistDetailView(playlist: playlist, api: app.api)
        case .genre(let name): GenreView(genre: name)
        }
    }
}

private struct WebPlayerView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
