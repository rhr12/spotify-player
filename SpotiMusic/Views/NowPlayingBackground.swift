import SwiftUI

/// Artwork that gently "breathes" while playing and shrinks back when paused (as in Apple Music).
struct BreathingArtwork: View {
    let url: URL?
    var image: NSImage?
    let size: CGFloat
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breath = isPlaying ? 1 + 0.012 * sin(t * 1.6) : 0.86
            ArtworkView(url: url, image: image, cornerRadius: 10)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.45), radius: 34, y: 22)
                .scaleEffect(breath)
                .animation(.spring(response: 0.55, dampingFraction: 0.72), value: isPlaying)
        }
    }
}

/// Blurred album art plus slowly drifting color blobs extracted from it.
struct NowPlayingBackground: View {
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
                    let blobs: [(Color, Double, CGFloat, Double)] = [
                        (palette.primary, 0.0, 0.55, 0.62),
                        (palette.tertiary, 2.1, 0.45, 0.5),
                        (palette.secondary, 4.2, 0.6, 0.7),
                    ]
                    for (color, phase, radiusFactor, alpha) in blobs {
                        let radius = max(size.width, size.height) * radiusFactor
                        let center = CGPoint(
                            x: size.width * CGFloat(0.5 + 0.3 * cos(t + phase)),
                            y: size.height * CGFloat(0.5 + 0.28 * sin(t * 1.3 + phase))
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
