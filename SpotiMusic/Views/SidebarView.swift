import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @State private var showingNewPlaylist = false

    var body: some View {
        List(selection: $app.selection) {
            Section("Spotify") {
                row("Listen Now", "play.circle", .listenNow)
                row("Browse", "square.grid.2x2", .browse)
                row("Radio", "dot.radiowaves.left.and.right", .radio)
            }
            Section("Library") {
                row("Recently Added", "clock", .recentlyAdded)
                row("Artists", "music.mic", .artists)
                row("Albums", "square.stack", .albums)
                row("Songs", "music.note", .songs)
            }
            Section {
                if let error = library.playlistsError, library.playlists.isEmpty {
                    Button("Couldn't load playlists — Retry") { Task { await library.loadPlaylists() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .help(error)
                }
                ForEach(library.playlists) { playlist in
                    row(playlist.name, "music.note.list", .playlist(playlist))
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button { showingNewPlaylist = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("New Playlist")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { account }
        .sheet(isPresented: $showingNewPlaylist) {
            NewPlaylistSheet()
                .environmentObject(app)
                .environmentObject(library)
        }
    }

    private func row(_ title: String, _ symbol: String, _ item: SidebarItem) -> some View {
        Label {
            Text(title).lineLimit(1)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }
        .font(.system(size: 13))
        .tag(item)
    }

    private var account: some View {
        HStack(spacing: 8) {
            ArtworkView(url: library.user?.images?.url(atLeast: 64), circular: true, placeholderSymbol: "person.fill")
                .frame(width: 24, height: 24)
            Text(library.user?.displayName ?? library.user?.id ?? "Spotify")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer()
            Menu {
                Button("Reload Library") { Task { await library.loadInitial() } }
                Divider()
                Button("Sign Out") { app.auth.signOut() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct NewPlaylistSheet: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Playlist").font(.system(size: 15, weight: .semibold))
            TextField("Playlist Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(create)
            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).frame(width: 300, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || creating)
            }
        }
        .padding(20)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !creating else { return }
        creating = true
        Task {
            do {
                let playlist = try await library.createPlaylist(named: trimmed)
                app.selection = .playlist(playlist)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            creating = false
        }
    }
}
