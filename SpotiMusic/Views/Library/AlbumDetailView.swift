import SwiftUI

/// Album page: large artwork header, Play/Shuffle, numbered track list and release footer.
struct AlbumDetailView: View {
    let album: Album

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @State private var full: Album?
    @State private var tracks: [Track] = []
    @State private var error: String?
    @State private var isLoading = true

    private var shown: Album { full ?? album }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CollectionHeader(
                    artworkURL: shown.images?.largeURL,
                    title: shown.name,
                    subtitle: shown.artistLine,
                    onSubtitle: openArtist,
                    meta: [shown.albumType?.capitalized, shown.genres?.first?.capitalized, shown.year]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").uppercased(),
                    description: nil,
                    onPlay: { Task { await player.play(contextURI: shown.uri) } },
                    onShuffle: { Task { await player.play(contextURI: shown.uri, shuffle: true) } }
                )
                if isLoading {
                    LoadingView()
                } else if let error {
                    ErrorView(message: error) { Task { await load() } }
                } else {
                    TrackListView(tracks: tracks, source: .context(shown.uri), numbering: .trackNumber,
                                  showArtwork: false, showAlbum: false)
                    footer
                }
            }
        }
        .navigationTitle(shown.name)
        .task(id: album.id) { await load() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let date = TimeFormat.releaseDate(shown.releaseDate) { Text(date) }
            Text("\(tracks.count) song\(tracks.count == 1 ? "" : "s"), \(TimeFormat.summary(tracks.reduce(0) { $0 + $1.durationMs }))")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
    }

    private func openArtist() {
        guard let artist = shown.artists?.first, let id = artist.id else { return }
        app.open(.artist(id: id, name: artist.name))
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        struct TrackPage: Decodable { let tracks: Paging<Track>? }
        do {
            let data = try await app.api.send("GET", "albums/\(album.id)")
            let fullAlbum = try JSONDecoder().decode(Album.self, from: data)
            var page = try JSONDecoder().decode(TrackPage.self, from: data).tracks
            var all = page?.items ?? []
            while let next = page?.next, let url = URL(string: next) {
                let nextPage: Paging<Track> = try await app.api.get(absolute: url)
                all += nextPage.items
                page = nextPage
            }
            full = fullAlbum
            tracks = all.map { track in
                var copy = track
                copy.album = fullAlbum
                return copy
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Shared header for album and playlist pages, sized like Apple Music (270pt artwork, 26pt titles).
struct CollectionHeader: View {
    let artworkURL: URL?
    let title: String
    let subtitle: String
    var onSubtitle: (() -> Void)?
    var meta: String
    var description: String?
    var placeholderSymbol = "music.note"
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            ArtworkView(url: artworkURL, cornerRadius: 8, placeholderSymbol: placeholderSymbol)
                .frame(width: 270, height: 270)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Button(action: { onSubtitle?() }) {
                    Text(subtitle)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(onSubtitle == nil)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 6)
                        .frame(maxWidth: 520, alignment: .leading)
                }
                PlayShuffleButtons(onPlay: onPlay, onShuffle: onShuffle)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }
}
