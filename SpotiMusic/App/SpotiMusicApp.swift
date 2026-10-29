import SwiftUI

@main
struct SpotiMusicApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        Window("SpotiMusic", id: "main") {
            ContentView()
                .environmentObject(app)
                .environmentObject(app.monitor)
                .environmentObject(app.lyrics)
                .environmentObject(app.theme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 700)
        .commands {
            ControlsCommands(app: app, monitor: app.monitor)
        }

        Settings {
            SettingsView()
        }
    }
}

struct ControlsCommands: Commands {
    @ObservedObject var app: AppState
    @ObservedObject var monitor: NowPlayingMonitor

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Controls") {
            Button(monitor.isPlaying ? "Pause" : "Play") { Task { await monitor.playPause() } }
                .disabled(monitor.track == nil)
            Button("Next") { Task { await monitor.next() } }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(monitor.track == nil)
            Button("Previous") { Task { await monitor.previous() } }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(monitor.track == nil)
            Divider()
            Button("Increase Volume") { monitor.setVolume((monitor.volume ?? 0.5) + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(monitor.volume == nil)
            Button("Decrease Volume") { monitor.setVolume((monitor.volume ?? 0.5) - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(monitor.volume == nil)
        }

        CommandGroup(after: .sidebar) {
            Button(app.showLyrics ? "Hide Lyrics" : "Show Lyrics") { app.toggleLyrics() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
        }
    }
}
