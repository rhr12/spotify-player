import SwiftUI

/// Radio: artist stations (Spotify artist contexts played on shuffle) built from the
/// user's top and followed artists.
struct RadioView: View {
    @EnvironmentObject private var app: AppState
    @State private var topArtists: [Artist] = []
    @State private var followed: [Artist] = []
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(title: "Radio", subtitle: "Endless stations from the artists you love")
                if !loaded {
                    LoadingView()
                } else if topArtists.isEmpty && followed.isEmpty {
                    if let error {
                        ErrorView(message: error) { Task { await load() } }
                    } else {
                        MessageView(symbol: "dot.radiowaves.left.and.right", title: "No Stations Yet",
                                    message: "Listen to or follow some artists on Spotify to get stations here.")
                    }
                } else {
                    if !topArtists.isEmpty {
                        SectionTitle(title: "Stations for You")
                        stationGrid(topArtists)
                    }
                    let extra = followed.filter { artist in !topArtists.contains { $0.id == artist.id } }
                    if !extra.isEmpty {
                        SectionTitle(title: "From Artists You Follow")
                        stationGrid(extra)
                    }
                }
            }
        }
        .navigationTitle("Radio")
        .task { if !loaded { await load() } }
    }

    private func stationGrid(_ artists: [Artist]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18)], spacing: 18) {
            ForEach(artists) { StationCard(artist: $0) }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func load() async {
        async let top: Paging<Artist> = app.api.get("me/top/artists", query: ["limit": "20"])
        async let following: FollowedArtistsResponse = app.api.get("me/following", query: ["type": "artist", "limit": "50"])
        do { topArtists = try await top.items } catch { self.error = error.localizedDescription }
        do { followed = try await following.artists.items } catch { if self.error == nil { self.error = error.localizedDescription } }
        loaded = true
    }
}

private struct StationCard: View {
    let artist: Artist
    @EnvironmentObject private var player: PlayerController
    @State private var hovering = false

    private var isPlayingStation: Bool { player.isPlaying && player.track?.artists.contains { $0.uri == artist.uri } == true }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(url: artist.images?.url(atLeast: 300), cornerRadius: 0, placeholderSymbol: "music.mic")
                .aspectRatio(16 / 10, contentMode: .fill)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("STATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(artist.name) Radio")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(12)
            if hovering || isPlayingStation {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor, in: Circle())
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            Task { await player.play(contextURI: artist.uri, shuffle: true) }
        }
    }
}
