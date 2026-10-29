import SwiftUI

/// Full-width bottom player bar: now playing (left), transport + scrubber (center),
/// lyrics / AirPlay / volume (right).
struct PlayerBarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        HStack(spacing: 0) {
            nowPlaying
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            TransportView(player: player, clock: player.clock, style: .bar)
                .frame(width: 460)
            trailing
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 68)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Button(action: { if player.track != nil { app.toggleNowPlaying() } }) {
                ArtworkView(url: player.track?.album?.images?.url(atLeast: 64), cornerRadius: 4)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .help("Open Now Playing (⇧⌘F)")

            if let track = player.track {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Button(action: { app.openArtist(of: track) }) {
                        Text(track.artistLine)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    if let device = player.device, !player.isLocalDeviceActive {
                        Label(device.name, systemImage: device.symbolName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("Not Playing")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 14) {
            Button(action: app.toggleLyrics) {
                Image(systemName: app.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 15))
                    .foregroundStyle(app.showLyrics ? Color.accentColor : Color.primary.opacity(0.7))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Lyrics")

            DeviceButton(tint: Color.primary.opacity(0.7))

            VolumeControl(tint: Color.primary.opacity(0.55), track: Color.primary.opacity(0.14), iconColor: .secondary)
                .frame(width: 130)
        }
    }
}

/// Shuffle, previous, play/pause, next, repeat and the scrubber with elapsed/remaining time.
struct TransportView: View {
    enum Style { case bar, fullscreen }

    @ObservedObject var player: PlayerController
    @ObservedObject var clock: PlaybackClock
    var style: Style

    @State private var scrubFraction: Double?

    private var isFull: Bool { style == .fullscreen }
    private var foreground: Color { isFull ? .white : .primary }

    var body: some View {
        VStack(spacing: isFull ? 18 : 3) {
            if isFull {
                timeline
                buttons
            } else {
                buttons
                timeline
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: isFull ? 46 : 26) {
            control("shuffle", size: isFull ? 17 : 13, active: player.shuffle) {
                await player.toggleShuffle()
            }
            .help("Shuffle")
            control("backward.fill", size: isFull ? 30 : 17) { await player.previousTrack() }
                .help("Previous")
            control(player.isPlaying ? "pause.fill" : "play.fill", size: isFull ? 44 : 24) {
                await player.togglePlayPause()
            }
            .frame(width: isFull ? 50 : 28)
            .help(player.isPlaying ? "Pause" : "Play")
            control("forward.fill", size: isFull ? 30 : 17) { await player.nextTrack() }
                .help("Next")
            control(player.repeatMode == .track ? "repeat.1" : "repeat", size: isFull ? 17 : 13,
                    active: player.repeatMode != .off) {
                await player.cycleRepeat()
            }
            .help("Repeat")
        }
        .disabled(player.track == nil && player.device == nil && player.localDeviceID == nil)
    }

    private func control(_ symbol: String, size: CGFloat, active: Bool? = nil, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(symbolColor(active: active))
                .frame(minWidth: size + 6, minHeight: size + 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func symbolColor(active: Bool?) -> Color {
        guard let active else { return foreground.opacity(isFull ? 0.95 : 0.85) }
        if active { return isFull ? .white : .accentColor }
        return foreground.opacity(isFull ? 0.5 : 0.5)
    }

    private var timeline: some View {
        let duration = max(clock.durationMs, 1)
        let fraction = scrubFraction ?? Double(clock.positionMs) / Double(duration)
        let elapsed = Int(fraction * Double(duration))
        return HStack(spacing: 8) {
            Text(TimeFormat.clock(elapsed))
                .frame(width: 40, alignment: .trailing)
            ProgressSlider(
                value: fraction,
                tint: isFull ? .white.opacity(0.75) : Color.primary.opacity(0.5),
                trackColor: isFull ? .white.opacity(0.2) : Color.primary.opacity(0.13),
                height: isFull ? 6 : 4,
                onScrub: { scrubFraction = $0 },
                onCommit: { value in
                    scrubFraction = nil
                    Task { await player.seek(to: Int(value * Double(duration))) }
                }
            )
            .disabled(clock.durationMs == 0)
            Text("-" + TimeFormat.clock(clock.durationMs - elapsed))
                .frame(width: 44, alignment: .leading)
        }
        .font(.system(size: isFull ? 11 : 10, weight: .medium).monospacedDigit())
        .foregroundStyle(isFull ? Color.white.opacity(0.6) : Color.secondary)
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

struct VolumeControl: View {
    var tint: Color
    var track: Color
    var iconColor: Color

    @EnvironmentObject private var player: PlayerController

    var body: some View {
        HStack(spacing: 6) {
            Button { player.setVolume(0) } label: {
                Image(systemName: "speaker.fill").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Mute")
            ProgressSlider(value: player.volume, tint: tint, trackColor: track, height: 4,
                           onScrub: { player.setVolume($0) }, onCommit: { player.setVolume($0) })
            Button { player.setVolume(1) } label: {
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Maximum Volume")
        }
        .foregroundStyle(iconColor)
    }
}
