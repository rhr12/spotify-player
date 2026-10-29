import SwiftUI

struct SettingsView: View {
    @AppStorage(NowPlayingTrack.Source.spotify.defaultsKey) private var followSpotify = true
    @AppStorage(NowPlayingTrack.Source.music.defaultsKey) private var followMusic = true
    @State private var spicyKey = SpicyLyricsClient.apiKey ?? ""
    @State private var saved = false

    var body: some View {
        TabView {
            Form {
                Section {
                    Toggle("Spotify", isOn: $followSpotify)
                    Toggle("Music", isOn: $followMusic)
                } header: {
                    Text("Follow what's playing in")
                }
                Text("macOS asks once per app for permission to read what's playing (Privacy & Security ▸ Automation).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Text("Lyrics come from am-lyrics first (lrc.red, BiniLyrics, Unison, LyricsPlus, LRCLIB and more). If none of them has the song, SpotiMusic asks Spicy Lyrics using your own API key.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("Spicy Lyrics API key", text: $spicyKey)
                    .onSubmit(save)
                HStack {
                    Button("Save", action: save)
                    if !spicyKey.isEmpty {
                        Button("Remove") {
                            spicyKey = ""
                            save()
                        }
                    }
                    if saved {
                        Text("Saved").foregroundStyle(.secondary)
                    }
                }
                Text("Optional. Stored in your Keychain. Spicy Lyrics is used only for songs playing in Spotify.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Link("spicylyrics.org", destination: URL(string: "https://spicylyrics.org")!)
                    .font(.system(size: 11))
            }
            .padding(20)
            .tabItem { Label("Lyrics", systemImage: "quote.bubble") }
        }
        .frame(width: 480, height: 280)
    }

    private func save() {
        SpicyLyricsClient.apiKey = spicyKey
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
    }
}
