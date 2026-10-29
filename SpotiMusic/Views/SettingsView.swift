import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @EnvironmentObject private var web: WebPlaybackHost
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("appearance") private var appearance = Appearance.light.rawValue

    var body: some View {
        TabView {
            Form {
                Picker("Appearance:", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                Text("SpotiMusic uses Light mode by default, like Apple Music.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                LabeledContent("Account:") {
                    Text(auth.isAuthorized ? (library.user?.displayName ?? library.user?.id ?? "Connected") : "Not connected")
                }
                LabeledContent("Client ID:") {
                    Text(auth.clientID.isEmpty ? "—" : auth.clientID)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Redirect URI:") {
                    Text(SpotifyAuth.redirectURI)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
                if auth.isAuthorized {
                    Button("Sign Out") { auth.signOut() }
                }
            }
            .padding(20)
            .tabItem { Label("Account", systemImage: "person.crop.circle") }

            Form {
                LabeledContent("Built-in player:") {
                    Text(web.status.description)
                        .foregroundStyle(web.status == .ready ? Color.green : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let id = web.deviceID {
                    LabeledContent("Device ID:") {
                        Text(id).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }
                }
                Button("Restart Built-in Player") { web.restart() }
                    .disabled(!auth.isAuthorized)
                Text("The built-in player streams through the Spotify Web Playback SDK. When it isn't available, SpotiMusic controls Spotify on your other devices instead.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .tabItem { Label("Playback", systemImage: "play.circle") }
        }
        .frame(width: 500, height: 260)
    }
}
