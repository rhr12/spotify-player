import AppKit
import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var monitor: NowPlayingMonitor
    @EnvironmentObject private var theme: ArtworkTheme

    var body: some View {
        ZStack {
            NowPlayingBackground(image: theme.image, palette: theme.palette, isPlaying: monitor.isPlaying)

            if let track = monitor.track {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        PlayerColumn(track: track, size: geometry.size, compact: app.showLyrics)
                            .frame(width: app.showLyrics ? max(340, geometry.size.width * 0.42) : geometry.size.width)
                        if app.showLyrics {
                            LyricsPane()
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            } else {
                EmptyStateView()
            }

            TopBar()
        }
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 780, minHeight: 540)
        .ignoresSafeArea()
    }
}

private struct TopBar: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var monitor: NowPlayingMonitor

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if monitor.track != nil {
                    Button(action: app.toggleLyrics) {
                        Image(systemName: app.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(app.showLyrics ? 0.95 : 0.7))
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(app.showLyrics ? 0.22 : 0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(app.showLyrics ? "Hide Lyrics (⇧⌘L)" : "Show Lyrics (⇧⌘L)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            Spacer()
        }
    }
}

/// Artwork, song info, scrubber, transport and volume — the left side of Now Playing.
private struct PlayerColumn: View {
    let track: NowPlayingTrack
    let size: CGSize
    let compact: Bool

    @EnvironmentObject private var monitor: NowPlayingMonitor

    private var artSize: CGFloat {
        let widthShare = compact ? max(340, size.width * 0.42) * 0.72 : size.width * 0.5
        return max(160, min(size.height * 0.44, widthShare, 520))
    }
    private var controlsWidth: CGFloat { max(min(artSize, 440), 300) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            BreathingArtwork(url: track.artworkURL, image: monitorImage, size: artSize, isPlaying: monitor.isPlaying)
            Spacer(minLength: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(track.title)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    NowPlayingBars(isPlaying: monitor.isPlaying, barCount: 4, color: .white.opacity(0.75), spacing: 2.5)
                        .frame(width: 20, height: 16)
                }
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: controlsWidth)

            Timeline(clock: monitor.clock)
                .frame(width: controlsWidth)
                .padding(.top, 16)

            Transport()
                .padding(.top, 14)

            if monitor.volume != nil {
                VolumeRow()
                    .frame(width: controlsWidth * 0.75)
                    .padding(.top, 20)
            }

            SourceChip(source: track.source)
                .padding(.top, 18)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    private var monitorImage: NSImage? {
        monitor.artworkData.flatMap(NSImage.init(data:))
    }
}

private struct Timeline: View {
    @ObservedObject var clock: PlaybackClock
    @EnvironmentObject private var monitor: NowPlayingMonitor
    @State private var scrub: Double?

    var body: some View {
        let duration = max(clock.durationMs, 1)
        let fraction = scrub ?? Double(clock.positionMs) / Double(duration)
        let elapsed = Int(fraction * Double(duration))
        VStack(spacing: 4) {
            ProgressSlider(
                value: fraction,
                tint: .white.opacity(0.8),
                trackColor: .white.opacity(0.2),
                height: 6,
                onScrub: { scrub = $0 },
                onCommit: { value in
                    scrub = nil
                    Task { await monitor.seek(to: Int(value * Double(duration))) }
                }
            )
            HStack {
                Text(TimeFormat.clock(elapsed))
                Spacer()
                Text("-" + TimeFormat.clock(clock.durationMs - elapsed))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct Transport: View {
    @EnvironmentObject private var monitor: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 48) {
            button("backward.fill", size: 28, help: "Previous") { await monitor.previous() }
            button(monitor.isPlaying ? "pause.fill" : "play.fill", size: 42, help: monitor.isPlaying ? "Pause" : "Play") {
                await monitor.playPause()
            }
            .frame(width: 48)
            button("forward.fill", size: 28, help: "Next") { await monitor.next() }
        }
    }

    private func button(_ symbol: String, size: CGFloat, help: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .frame(minWidth: size + 8, minHeight: size + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(help)
    }
}

private struct VolumeRow: View {
    @EnvironmentObject private var monitor: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").font(.system(size: 10))
            ProgressSlider(value: monitor.volume ?? 0, tint: .white.opacity(0.75), trackColor: .white.opacity(0.2), height: 4,
                           onScrub: { monitor.setVolume($0) }, onCommit: { monitor.setVolume($0) })
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}

/// "Playing in Spotify" — clicking brings that app forward.
private struct SourceChip: View {
    let source: NowPlayingTrack.Source
    @EnvironmentObject private var monitor: NowPlayingMonitor

    var body: some View {
        Button(action: monitor.activateSourceApp) {
            HStack(spacing: 6) {
                if let icon = source.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text("Playing in \(source.rawValue)")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Open \(source.rawValue)")
    }
}

/// Right side: am-lyrics plus a small status line.
private struct LyricsPane: View {
    @EnvironmentObject private var lyrics: LyricsController

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LyricsWebView(webView: lyrics.webView)
                .mask(
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.1),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                )
                .opacity(isHidden ? 0 : 1)

            if case .notFound(let reason) = lyrics.status {
                Text(reason)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            statusLine
                .padding(.trailing, 22)
                .padding(.bottom, 14)
        }
        .padding(.top, 50)
    }

    private var isHidden: Bool {
        if case .notFound = lyrics.status { return true }
        return false
    }

    @ViewBuilder
    private var statusLine: some View {
        switch lyrics.status {
        case .searching:
            label("Searching lyrics…", progress: true)
        case .searchingSpicy:
            label("Trying Spicy Lyrics…", progress: true)
        case .found(let source):
            label("Lyrics: \(source)", progress: false)
        case .idle, .notFound:
            EmptyView()
        }
    }

    private func label(_ text: String, progress: Bool) -> some View {
        HStack(spacing: 6) {
            if progress { ProgressView().controlSize(.mini) }
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.45))
    }
}

private struct LyricsWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Shown when nothing is playing in Spotify or Music.
private struct EmptyStateView: View {
    @EnvironmentObject private var monitor: NowPlayingMonitor

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text("Nothing Playing")
                .font(.system(size: 24, weight: .bold))
            if let denied = monitor.permissionDenied {
                Text("SpotiMusic isn't allowed to see what \(denied.rawValue) is playing. Turn on \(denied.rawValue) for SpotiMusic in System Settings ▸ Privacy & Security ▸ Automation.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .foregroundStyle(.white.opacity(0.7))
                Button("Open Automation Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            } else {
                Text("Start a song in Spotify or Music and SpotiMusic will follow along with synced lyrics.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .foregroundStyle(.white.opacity(0.65))
                HStack(spacing: 10) {
                    ForEach(NowPlayingTrack.Source.allCases.filter(\.isInstalled), id: \.self) { source in
                        Button {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if let icon = source.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                                Text("Open \(source.rawValue)")
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(40)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
