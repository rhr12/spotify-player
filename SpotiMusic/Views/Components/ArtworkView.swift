import SwiftUI

/// Album/playlist/artist artwork with async loading and a neutral placeholder.
struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 6
    var circular = false
    var placeholderSymbol = "music.note"

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
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
            image = url.flatMap { ImageCache.shared.cached($0) }
            if image == nil, let url {
                image = await ImageCache.shared.image(for: url)
            }
        }
    }
}
