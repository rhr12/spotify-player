import SwiftUI

/// Album/playlist/artist artwork with async loading and a neutral placeholder.
struct ArtworkView: View {
    let url: URL?
    /// Artwork already in memory (e.g. read from the Music app); takes precedence over `url`.
    var image: NSImage?
    var cornerRadius: CGFloat = 6
    var circular = false
    var placeholderSymbol = "music.note"

    @State private var loaded: NSImage?

    private var shown: NSImage? { image ?? loaded }

    var body: some View {
        ZStack {
            if let shown {
                Image(nsImage: shown)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(nsColor: .quaternaryLabelColor), Color(nsColor: .tertiaryLabelColor)],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(0.6)
                GeometryReader { geometry in
                    Image(systemName: placeholderSymbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: geometry.size.width * 0.36, height: geometry.size.height * 0.36)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
        .overlay {
            if circular {
                Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
        .task(id: url) {
            loaded = url.flatMap { ImageCache.shared.cached($0) }
            if loaded == nil, let url {
                loaded = await ImageCache.shared.image(for: url)
            }
        }
    }
}
