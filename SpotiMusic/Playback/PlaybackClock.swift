import Foundation

/// Interpolates the playback position between state updates. Kept separate from
/// the monitor so only the scrubber re-renders several times per second.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published private(set) var positionMs = 0
    @Published private(set) var durationMs = 0

    private var anchorPosition = 0
    private var anchorDate = Date()
    private var isRunning = false
    private var timer: Timer?

    var onReachedEnd: (() -> Void)?

    func sync(position: Int, duration: Int, playing: Bool) {
        anchorPosition = max(0, position)
        anchorDate = Date()
        durationMs = duration
        isRunning = playing
        positionMs = min(anchorPosition, duration > 0 ? duration : anchorPosition)
        if playing { startTimer() } else { stopTimer() }
    }

    func reset() {
        sync(position: 0, duration: 0, playing: false)
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isRunning else { return }
        let elapsed = Int(Date().timeIntervalSince(anchorDate) * 1000)
        let position = anchorPosition + elapsed
        if durationMs > 0, position >= durationMs {
            positionMs = durationMs
            isRunning = false
            stopTimer()
            onReachedEnd?()
        } else {
            positionMs = position
        }
    }
}
