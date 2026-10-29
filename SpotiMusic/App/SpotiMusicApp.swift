import SwiftUI

@main
struct SpotiMusicApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        // A single window: the built-in player's web view can only live in one place.
        Window("SpotiMusic", id: "main") {
            RootView()
                .environmentObject(app)
                .environmentObject(app.auth)
                .environmentObject(app.player)
                .environmentObject(app.library)
                .environmentObject(app.lyrics)
                .environmentObject(app.theme)
                .environmentObject(app.web)
                .tint(.accentColor)
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            PlayerCommands(app: app, player: app.player, auth: app.auth)
        }

        Settings {
            SettingsView()
                .environmentObject(app.auth)
                .environmentObject(app.web)
                .environmentObject(app.library)
        }
    }
}

/// The "Controls" menu, mirroring Apple Music's shortcuts.
struct PlayerCommands: Commands {
    @ObservedObject var app: AppState
    @ObservedObject var player: PlayerController
    @ObservedObject var auth: SpotifyAuth

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Controls") {
            Button(player.isPlaying ? "Pause" : "Play") { Task { await player.togglePlayPause() } }
                .disabled(!auth.isAuthorized)
            Button("Next") { Task { await player.nextTrack() } }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!auth.isAuthorized)
            Button("Previous") { Task { await player.previousTrack() } }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!auth.isAuthorized)
            Divider()
            Button("Increase Volume") { player.setVolume(player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!auth.isAuthorized)
            Button("Decrease Volume") { player.setVolume(player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!auth.isAuthorized)
            Divider()
            Button(player.shuffle ? "Turn Shuffle Off" : "Turn Shuffle On") { Task { await player.toggleShuffle() } }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!auth.isAuthorized)
            Button(repeatTitle) { Task { await player.cycleRepeat() } }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!auth.isAuthorized)
        }

        CommandGroup(after: .sidebar) {
            Button(app.showNowPlaying ? "Exit Full Screen Player" : "Full Screen Player") { app.toggleNowPlaying() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!auth.isAuthorized || player.track == nil)
            Button(app.showLyrics ? "Hide Lyrics" : "Show Lyrics") { app.toggleLyrics() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!auth.isAuthorized)
            Divider()
        }
    }

    private var repeatTitle: String {
        switch player.repeatMode {
        case .off: return "Repeat All"
        case .context: return "Repeat One"
        case .track: return "Repeat Off"
        }
    }
}
