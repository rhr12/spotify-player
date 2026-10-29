import AppKit
import SwiftUI

/// How double-clicking a row starts playback.
enum PlaybackSource {
    /// Play within an album/playlist context, starting at the clicked track.
    case context(String)
    /// Play the listed tracks themselves, starting at the clicked track.
    case trackList
}

/// The Apple Music song table: #, Title, Artist, Album, Time with alternating rows,
/// hover highlight, selection, double-click to play and a context menu.
struct TrackListView: View {
    enum Numbering { case index, trackNumber }

    let tracks: [Track]
    var source: PlaybackSource = .trackList
    var numbering: Numbering = .index
    var showArtwork = true
    var showArtist = true
    var showAlbum = true
    var onReachEnd: (() -> Void)?

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var app: AppState
    @State private var selection: Int?
    @State private var hovered: Int?

    var body: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    row(index: index, track: track)
                        .onAppear {
                            if index == tracks.count - 1 { onReachEnd?() }
                        }
                }
            } header: {
                header
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("#").frame(width: 30, alignment: .trailing)
                Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                if showArtist { Text("Artist").frame(maxWidth: .infinity, alignment: .leading) }
                if showAlbum { Text("Album").frame(maxWidth: .infinity, alignment: .leading) }
                Image(systemName: "clock").frame(width: 46, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 30)
            .frame(height: 26)
            Divider().padding(.horizontal, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
    }

    // MARK: Rows

    private func row(index: Int, track: Track) -> some View {
        let isCurrent = track.uri != nil && player.track?.uri == track.uri
        let isSelected = selection == index
        let primary: Color = isSelected ? .white : (isCurrent ? .accentColor : .primary)
        let secondary: Color = isSelected ? .white.opacity(0.85) : .secondary

        return HStack(spacing: 12) {
            ZStack(alignment: .trailing) {
                if isCurrent {
                    NowPlayingBars(isPlaying: player.isPlaying, color: isSelected ? .white : .accentColor)
                        .frame(width: 12, height: 11)
                } else if hovered == index && track.isPlayable {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(primary)
                } else {
                    Text(numberText(index: index, track: track))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(secondary)
                }
            }
            .frame(width: 30, alignment: .trailing)

            HStack(spacing: 10) {
                if showArtwork {
                    ArtworkView(url: track.album?.images?.url(atLeast: 64), cornerRadius: 3)
                        .frame(width: 28, height: 28)
                }
                Text(track.name)
                    .font(.system(size: 13, weight: isCurrent ? .medium : .regular))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                if track.explicit == true {
                    Image(systemName: "e.square.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showArtist {
                Text(track.artistLine)
                    .font(.system(size: 13))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showAlbum {
                Text(track.album?.name ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(TimeFormat.clock(track.durationMs))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(secondary)
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: showArtwork ? 40 : 30)
        .background(rowBackground(index: index, selected: isSelected))
        .padding(.horizontal, 20)
        .opacity(track.isPlayable ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = index } else if hovered == index { hovered = nil }
        }
        .onTapGesture(count: 2) { play(index) }
        .simultaneousGesture(TapGesture().onEnded { selection = index })
        .contextMenu { contextMenu(index: index, track: track) }
    }

    private func numberText(index: Int, track: Track) -> String {
        switch numbering {
        case .index: return "\(index + 1)"
        case .trackNumber: return "\(track.trackNumber ?? index + 1)"
        }
    }

    @ViewBuilder
    private func rowBackground(index: Int, selected: Bool) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor)
        } else if hovered == index {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.07))
        } else if index % 2 == 1 {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.035))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func contextMenu(index: Int, track: Track) -> some View {
        Button("Play") { play(index) }
            .disabled(!track.isPlayable)
        Button("Play Later") { Task { await player.addToQueue(track) } }
            .disabled(!track.isPlayable)
        Divider()
        if let artist = track.artists.first, artist.id != nil {
            Button("Go to Artist") { app.openArtist(of: track) }
        }
        if let album = track.album, !album.id.isEmpty {
            Button("Go to Album") { app.openAlbum(of: track) }
        }
        if let id = track.id, track.isLocal != true {
            Divider()
            Button("Copy Song Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("https://open.spotify.com/track/\(id)", forType: .string)
            }
        }
    }

    // MARK: Playback

    private func play(_ index: Int) {
        let track = tracks[index]
        guard track.isPlayable else { return }
        selection = index
        Task {
            switch source {
            case .context(let uri):
                await player.play(contextURI: uri, offsetURI: track.uri)
            case .trackList:
                let uris = tracks[index...].filter(\.isPlayable).prefix(100).compactMap(\.uri)
                await player.play(uris: Array(uris))
            }
        }
    }
}

extension PlayerController {
    /// Plays a list of tracks in random order (used by "Shuffle" buttons on track lists).
    func shuffle(_ tracks: [Track]) async {
        let uris = tracks.filter(\.isPlayable).compactMap(\.uri).shuffled().prefix(100)
        guard !uris.isEmpty else { return }
        await play(uris: Array(uris), shuffle: true)
    }

    func playInOrder(_ tracks: [Track]) async {
        let uris = tracks.filter(\.isPlayable).compactMap(\.uri).prefix(100)
        guard !uris.isEmpty else { return }
        await play(uris: Array(uris), shuffle: false)
    }
}
