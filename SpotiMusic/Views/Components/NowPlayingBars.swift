import SwiftUI

/// Animated equalizer bars shown next to the playing song (and as the waveform in Now Playing).
struct NowPlayingBars: View {
    var isPlaying: Bool
    var barCount = 3
    var color: Color = .accentColor
    var spacing: CGFloat = 1.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                let barWidth = (geometry.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let phase = Double(index) * 1.7
                        let level = isPlaying
                            ? 0.3 + 0.7 * abs(sin(time * (2.2 + Double(index % 3) * 0.6) + phase))
                            : 0.25
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(color)
                            .frame(width: barWidth, height: max(barWidth, geometry.size.height * level))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
            }
        }
    }
}
