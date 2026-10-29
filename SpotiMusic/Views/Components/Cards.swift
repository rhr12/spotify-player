import SwiftUI

/// Album tile used in grids and shelves; hovering reveals a play button over the artwork.
struct AlbumCard: View {
    let album: Album
    var width: CGFloat?

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: album.images?.url(atLeast: 300), cornerRadius: 6)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .overlay(alignment: .bottomLeading) {
                    if hovering {
                        Button {
                            Task { await player.play(contextURI: album.uri) }
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.accentColor, in: Circle())
                                .shadow(radius: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .transition(.opacity)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(album.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .onTapGesture { app.open(.album(album)) }
    }

    private var subtitle: String {
        album.artistLine.isEmpty ? (album.year ?? "") : album.artistLine
    }
}

struct PlaylistCard: View {
    let playlist: Playlist
    var width: CGFloat?

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: playlist.images?.url(atLeast: 300), cornerRadius: 6, placeholderSymbol: "music.note.list")
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .overlay(alignment: .bottomLeading) {
                    if hovering {
                        Button {
                            Task { await player.play(contextURI: playlist.uri) }
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.accentColor, in: Circle())
                                .shadow(radius: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(playlist.owner?.displayName ?? "Playlist")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .onTapGesture { app.open(.playlist(playlist)) }
    }
}

struct ArtistCircle: View {
    let artist: Artist
    var size: CGFloat = 140

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 8) {
            ArtworkView(url: artist.images?.url(atLeast: 300), circular: true, placeholderSymbol: "music.mic")
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
            Text(artist.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(width: size)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.open(.artist(id: artist.id, name: artist.name)) }
    }
}

/// A horizontally scrolling row of cards, as used throughout Listen Now and Search.
struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 6)
            }
        }
    }
}

/// Square track card used in Listen Now shelves.
struct TrackCard: View {
    let track: Track
    let onPlay: () -> Void
    var width: CGFloat = 160

    @EnvironmentObject private var player: PlayerController
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: track.album?.images?.url(atLeast: 300), cornerRadius: 6)
                .frame(width: width, height: width)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .overlay {
                    if hovering || player.track?.uri == track.uri {
                        ZStack {
                            Color.black.opacity(0.25)
                            if player.track?.uri == track.uri && !hovering {
                                NowPlayingBars(isPlaying: player.isPlaying, color: .white)
                                    .frame(width: 22, height: 20)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            Text(track.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text(track.artistLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onPlay() }
    }
}

/// Grid layout matching Apple Music's album grid spacing.
struct AlbumGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    var onReachEnd: (() -> Void)?
    @ViewBuilder var cell: (Item) -> Cell

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 22, alignment: .top)], spacing: 26) {
            ForEach(items) { item in
                cell(item)
                    .onAppear {
                        if item.id == items.last?.id { onReachEnd?() }
                    }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}
