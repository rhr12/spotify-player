import AppKit
import SwiftUI

/// First-launch screen: requirements, Client ID entry and "Connect Spotify".
struct OnboardingView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @State private var copied = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                VStack(spacing: 6) {
                    Text("Welcome to SpotiMusic")
                        .font(.system(size: 28, weight: .bold))
                    Text("Connect your Spotify account to stream your library with an Apple Music–style player.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    requirement("1", "Spotify **Premium** is required for playback.")
                    requirement("2", "Create a free app at **developer.spotify.com/dashboard** and copy its **Client ID**.")
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        badge("3")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("In the app's settings, add this **Redirect URI** and enable **Web API** and **Web Playback SDK**:")
                                .font(.system(size: 13))
                            HStack(spacing: 6) {
                                Text(SpotifyAuth.redirectURI)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                                Button(copied ? "Copied" : "Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                                    copied = true
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(width: 460, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(spacing: 12) {
                    TextField("Spotify Client ID", text: $auth.clientID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 360)
                        .disabled(auth.isAuthorizing)
                        .onSubmit(connect)

                    if auth.isAuthorizing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for you to approve access in your browser…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button("Cancel") { auth.cancelAuthorization() }
                                .controlSize(.small)
                        }
                    } else {
                        Button(action: connect) {
                            Text("Connect Spotify")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 220, height: 34)
                                .foregroundStyle(.white)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                        .disabled(auth.clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(width: 420)
                    }

                    Link("Open Spotify Developer Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                        .font(.system(size: 12))
                }
            }
            .padding(40)
        }
    }

    private func connect() {
        Task { await auth.authorize() }
    }

    private func badge(_ number: String) -> some View {
        Text(number)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.accentColor, in: Circle())
    }

    private func requirement(_ number: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            badge(number)
            Text(text).font(.system(size: 13))
        }
    }
}
