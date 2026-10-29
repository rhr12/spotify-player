import SwiftUI

/// Apple Music–style thin scrubber: grows and reveals a knob on hover, supports click-to-seek and drag.
struct ProgressSlider: View {
    var value: Double
    var tint: Color = Color.primary.opacity(0.55)
    var trackColor: Color = Color.primary.opacity(0.14)
    var height: CGFloat = 4
    var showsKnob = true
    var onScrub: ((Double) -> Void)?
    var onCommit: (Double) -> Void

    @State private var dragValue: Double?
    @State private var isHovering = false

    private var isActive: Bool { isHovering || dragValue != nil }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let fraction = CGFloat(min(max(dragValue ?? value, 0), 1))
            let barHeight = isActive ? height + 2 : height
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(isActive ? tint.opacity(1) : tint)
                    .frame(width: max(barHeight, width * fraction))
                if showsKnob && isActive {
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .frame(width: barHeight + 6, height: barHeight + 6)
                        .offset(x: width * fraction - (barHeight + 6) / 2)
                }
            }
            .frame(height: barHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = Double(min(max(gesture.location.x / width, 0), 1))
                        dragValue = newValue
                        onScrub?(newValue)
                    }
                    .onEnded { gesture in
                        let newValue = Double(min(max(gesture.location.x / width, 0), 1))
                        dragValue = nil
                        onCommit(newValue)
                    }
            )
            .animation(.easeOut(duration: 0.12), value: isActive)
        }
        .frame(height: 14)
        .onHover { isHovering = $0 }
    }
}
