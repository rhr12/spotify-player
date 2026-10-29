import AppKit
import CoreImage
import SwiftUI

/// Colors extracted from the current album art, used for the Now Playing and lyrics backgrounds.
struct ArtworkPalette: Equatable {
    var primary: Color
    var secondary: Color
    var tertiary: Color

    static let fallback = ArtworkPalette(
        primary: Color(red: 0.36, green: 0.16, blue: 0.22),
        secondary: Color(red: 0.18, green: 0.10, blue: 0.20),
        tertiary: Color(red: 0.55, green: 0.18, blue: 0.25)
    )
}

@MainActor
final class ArtworkTheme: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var palette: ArtworkPalette = .fallback

    private var currentURL: URL?
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    func update(for track: Track?) {
        let url = track?.album?.images?.largeURL
        guard url != currentURL else { return }
        currentURL = url
        guard let url else {
            image = nil
            palette = .fallback
            return
        }
        Task {
            guard let image = await ImageCache.shared.image(for: url), self.currentURL == url else { return }
            let palette = Self.extractPalette(from: image) ?? .fallback
            withAnimation(.easeInOut(duration: 0.8)) {
                self.image = image
                self.palette = palette
            }
        }
    }

    /// Averages three horizontal bands of the artwork with `CIAreaAverage`, then darkens and
    /// saturates the results so white text stays legible on top of them.
    static func extractPalette(from image: NSImage) -> ArtworkPalette? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let bandHeight = extent.height / 3
        let bands = (0..<3).map { index in
            CGRect(x: extent.minX, y: extent.minY + CGFloat(2 - index) * bandHeight, width: extent.width, height: bandHeight)
        }
        let colors = bands.compactMap { averageColor(of: ciImage, in: $0) }
        guard colors.count == 3 else { return nil }
        return ArtworkPalette(
            primary: Color(nsColor: tuned(colors[0], brightness: 0.55)),
            secondary: Color(nsColor: tuned(colors[2], brightness: 0.32)),
            tertiary: Color(nsColor: tuned(colors[1], brightness: 0.7))
        )
    }

    private static func averageColor(of image: CIImage, in rect: CGRect) -> NSColor? {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    private static func tuned(_ color: NSColor, brightness maximum: CGFloat) -> NSColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        (color.usingColorSpace(.sRGB) ?? color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(1, saturation * 1.25 + 0.05), brightness: min(brightness, maximum) * 0.9 + 0.08, alpha: 1)
    }
}
