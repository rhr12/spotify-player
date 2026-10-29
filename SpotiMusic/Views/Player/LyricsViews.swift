import SwiftUI

/// Renders whatever `LyricsStore` currently holds; shared by the side panel and Now Playing.
struct LyricsContentView: View {
    var fontSize: CGFloat = 24
    var alignment: TextAlignment = .center

    @EnvironmentObject private var lyrics: LyricsStore
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        switch lyrics.content {
        case .idle:
            placeholder("Play a song to see its lyrics.")
        case .loading:
            ProgressView()
                .controlSize(.small)
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .synced(let lines):
            SyncedLyricsView(lines: lines, clock: player.clock, fontSize: fontSize, alignment: alignment) { ms in
                Task { await player.seek(to: ms) }
            }
        case .plain(let lines):
            ScrollView(showsIndicators: false) {
                VStack(spacing: fontSize * 0.55) {
                    Text("These lyrics aren't time-synced.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.bottom, 6)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: fontSize * 0.8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(alignment)
                            .frame(maxWidth: .infinity, alignment: frameAlignment)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 40)
            }
        case .instrumental:
            placeholder("♪  Instrumental")
        case .unavailable:
            placeholder("No lyrics available")
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("Try Again") { lyrics.retry(for: player.track) }
                    .buttonStyle(.bordered)
                    .environment(\.colorScheme, .dark)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var frameAlignment: Alignment { alignment == .center ? .center : .leading }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Time-synced lyrics: past lines grey and small, the current line large, bold and white,
/// upcoming lines dimmer; spring-animated scrolling keeps the current line centered.
struct SyncedLyricsView: View {
    let lines: [LyricLine]
    @ObservedObject var clock: PlaybackClock
    var fontSize: CGFloat
    var alignment: TextAlignment
    var onSeek: (Int) -> Void

    @State private var hoveredLine: Int?

    /// Lines switch slightly early so the highlight lands as the words are sung.
    private var currentIndex: Int? { LRCParser.index(at: clock.positionMs + 200, in: lines) }

    var body: some View {
        let current = currentIndex
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: fontSize * 0.75) {
                        Color.clear.frame(height: geometry.size.height * 0.42)
                        ForEach(lines) { line in
                            lineView(line, current: current)
                                .id(line.id)
                        }
                        Color.clear.frame(height: geometry.size.height * 0.5)
                    }
                    .padding(.horizontal, 26)
                }
                .onAppear { proxy.scrollTo(current ?? 0, anchor: .center) }
                .onChange(of: current) { index in
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                        proxy.scrollTo(index ?? 0, anchor: .center)
                    }
                }
                .onChange(of: lines) { _ in proxy.scrollTo(0, anchor: .center) }
            }
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.85),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }

    private func lineView(_ line: LyricLine, current: Int?) -> some View {
        let distance = current.map { line.id - $0 } ?? (line.id + 1)
        let isCurrent = distance == 0
        let isPast = distance < 0
        let opacity: Double = isCurrent ? 1 : (isPast ? 0.3 : max(0.22, 0.58 - Double(distance - 1) * 0.07))
        let scale: CGFloat = isCurrent ? 1 : (isPast ? 0.78 : 0.86)

        return Group {
            if line.isInterlude {
                InterludeDots(active: isCurrent)
                    .frame(height: fontSize)
            } else {
                Text(line.text)
                    .font(.system(size: fontSize, weight: .bold))
                    .multilineTextAlignment(alignment)
            }
        }
        .foregroundStyle(.white.opacity(hoveredLine == line.id && !isCurrent ? min(1, opacity + 0.3) : opacity))
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .scaleEffect(scale, anchor: alignment == .center ? .center : .leading)
        .blur(radius: abs(distance) > 3 ? 0.6 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isCurrent)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isPast)
        .contentShape(Rectangle())
        .onHover { inside in hoveredLine = inside ? line.id : (hoveredLine == line.id ? nil : hoveredLine) }
        .onTapGesture { onSeek(line.timeMs) }
        .help("Jump to this line")
    }
}

private struct InterludeDots: View {
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .frame(width: 9, height: 9)
                        .scaleEffect(active ? 0.8 + 0.35 * abs(sin(t * 2.2 + Double(index) * 0.7)) : 0.8)
                }
            }
        }
    }
}

/// The side panel that slides in from the right of the main window.
struct LyricsPanelView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var theme: ArtworkTheme
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [theme.palette.primary, theme.palette.secondary], startPoint: .top, endPoint: .bottom)
                .overlay(Color.black.opacity(0.18))
            LyricsContentView(fontSize: 22)
                .padding(.top, 36)
            HStack {
                if let track = player.track {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(track.artistLine).font(.system(size: 11)).opacity(0.7).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                Button(action: app.toggleLyrics) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Hide Lyrics")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
        .animation(.easeInOut(duration: 0.8), value: theme.palette)
    }
}
