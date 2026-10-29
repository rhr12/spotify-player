import SwiftUI

struct ArtistDetailView: View {
    let artistID: String
    let name: String

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @StateObject private var albums: PagedLoader<Album>
    @State private var artist: Artist?

    init(artistID: String, name: String, api: SpotifyClient) {
        self.artistID = artistID
        self.name = name
        _albums = StateObject(wrappedValue: PagedLoader(
            api: api, path: "artists/\(artistID)/albums", query: ["include_groups": "album,single,compilation"]
        ))
    }

    private var uri: String { artist?.uri ?? "spotify:artist:\(artistID)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let error = albums.error, albums.items.isEmpty {
                    ErrorView(message: error) { Task { await albums.reload() } }
                } else if albums.items.isEmpty && !albums.hasLoaded {
                    LoadingView()
                } else {
                    ForEach(groups, id: \.title) { group in
                        SectionTitle(title: group.title)
                        AlbumGrid(items: group.albums, onReachEnd: { Task { await albums.loadMore() } }) { album in
                            AlbumCard(album: album)
                        }
                    }
                }
            }
        }
        .navigationTitle(artist?.name ?? name)
        .task(id: artistID) {
            artist = try? await app.api.get("artists/\(artistID)")
            await albums.loadIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            ArtworkView(url: artist?.images?.largeURL, circular: true, placeholderSymbol: "music.mic")
                .frame(width: 180, height: 180)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(artist?.name ?? name)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(2)
                if let genres = artist?.genres, !genres.isEmpty {
                    Text(genres.prefix(3).map(\.capitalized).joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await player.play(contextURI: uri) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 92, height: 28)
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await player.play(contextURI: uri, shuffle: true) }
                    } label: {
                        Label("Station", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 100, height: 28)
                            .foregroundStyle(Color.accentColor)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    private struct AlbumGroup {
        let title: String
        let albums: [Album]
    }

    private var groups: [AlbumGroup] {
        let all = albums.items
        let definitions: [(String, (Album) -> Bool)] = [
            ("Albums", { $0.albumType == "album" }),
            ("Singles & EPs", { $0.albumType == "single" }),
            ("Compilations", { $0.albumType == "compilation" }),
            ("More", { !["album", "single", "compilation"].contains($0.albumType ?? "") }),
        ]
        return definitions.compactMap { title, predicate in
            let matching = all.filter(predicate)
            return matching.isEmpty ? nil : AlbumGroup(title: title, albums: matching)
        }
    }
}
