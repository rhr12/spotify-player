import SwiftUI

/// Full-window Now Playing: large artwork with soft shadow over a blurred, color-extracted
/// background that slowly drifts; optional time-synced lyrics on the right.
struct NowPlayingView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var theme: ArtworkTheme

    var body: some View {
        GeometryReader { geometry in
            let showLyrics = app.showLyrics
            let artSize = min(geometry.size.height * 0.5, geometry.size.width * (showLyrics ? 0.36 : 0.5), 560)

            ZStack {
                NowPlayingBackground(image: theme.image, palette: theme.palette, isPlaying: player.isPlaying)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 56)
                        BreathingArtwork(url: player.track?.album?.images?.largeURL, size: artSize, isPlaying: player.isPlaying)
                        Spacer(minLength: 28)
                        trackInfo
                            .frame(width: max(artSize, 380))
                        TransportView(player: player, clock: player.clock, style: .fullscreen)
                            .frame(width: max(artSize, 380))
                            .padding(.top, 18)
                        VolumeControl(tint: .white.opacity(0.75), track: .white.opacity(0.2), iconColor: .white.opacity(0.6))
                            .frame(width: min(max(artSize, 380) * 0.7, 320))
                            .padding(.top, 22)
                        Spacer(minLength: 36)
                    }
                    .frame(maxWidth: .infinity)

                    if showLyrics {
                        LyricsContentView(fontSize: 30)
                            .frame(width: geometry.size.width * 0.46)
                            .padding(.vertical, 50)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 40)

                topBar
            }
        }
        .environment(\.colorScheme, .dark)
        .background(
            Button("", action: app.toggleNowPlaying)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        )
    }

    private var trackInfo: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.track?.name ?? "Not Playing")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let track = player.track {
                    Button(action: { app.openArtist(of: track) }) {
                        Text(track.artistLine + (track.album.map { " — \($0.name)" } ?? ""))
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            NowPlayingBars(isPlaying: player.isPlaying, barCount: 4, color: .white.opacity(0.75), spacing: 2.5)
                .frame(width: 22, height: 18)
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 14) {
                circleButton("chevron.down", help: "Close (Esc)", action: app.toggleNowPlaying)
                Spacer()
                circleButton(app.showLyrics ? "quote.bubble.fill" : "quote.bubble", help: "Lyrics", action: app.toggleLyrics)
                DeviceButton(tint: .white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .padding(.horizontal, 22)
            .padding(.top, 34)
            Spacer()
        }
    }

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Artwork that gently "breathes" while playing and shrinks back when paused (as in Apple Music).
private struct BreathingArtwork: View {
    let url: URL?
    let size: CGFloat
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breath = isPlaying ? 1 + 0.012 * sin(t * 1.6) : 0.86
            ArtworkView(url: url, cornerRadius: 10)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.45), radius: 34, y: 22)
                .scaleEffect(breath)
                .animation(.spring(response: 0.55, dampingFraction: 0.72), value: isPlaying)
        }
    }
}

/// Blurred album art plus slowly drifting color blobs extracted from it.
private struct NowPlayingBackground: View {
    let image: NSImage?
    let palette: ArtworkPalette
    let isPlaying: Bool

    var body: some View {
        ZStack {
            palette.secondary
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.4)
                    .blur(radius: 90)
                    .saturation(1.3)
                    .opacity(0.75)
            }
            TimelineView(.animation(minimumInterval: 1 / 24, paused: !isPlaying)) { context in
                let t = context.date.timeIntervalSinceReferenceDate * 0.12
                Canvas { canvas, size in
                    let blobs: [(Color, Double, Double, Double)] = [
                        (palette.primary, 0.0, 0.55, 0.62),
                        (palette.tertiary, 2.1, 0.45, 0.5),
                        (palette.secondary, 4.2, 0.6, 0.7),
                    ]
                    for (color, phase, radiusFactor, alpha) in blobs {
                        let radius = max(size.width, size.height) * radiusFactor
                        let center = CGPoint(
                            x: size.width * (0.5 + 0.3 * cos(t + phase)),
                            y: size.height * (0.5 + 0.28 * sin(t * 1.3 + phase))
                        )
                        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        canvas.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(
                                Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                                center: center, startRadius: 0, endRadius: radius
                            )
                        )
                    }
                }
            }
            LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .clipped()
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
