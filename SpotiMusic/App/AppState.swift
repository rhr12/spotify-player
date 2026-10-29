import AppKit
import Combine
import SwiftUI

/// Wires the now-playing monitor to the artwork theme and the lyrics view.
@MainActor
final class AppState: ObservableObject {
    let monitor = NowPlayingMonitor()
    let lyrics = LyricsController()
    let theme = ArtworkTheme()

    @Published var showLyrics: Bool {
        didSet { UserDefaults.standard.set(showLyrics, forKey: "showLyrics") }
    }

    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?

    init() {
        showLyrics = UserDefaults.standard.object(forKey: "showLyrics") as? Bool ?? true

        monitor.onSync = { [weak self] position, playing in
            self?.lyrics.sync(positionMs: position, playing: playing)
        }
        lyrics.onSeek = { [weak self] ms in
            Task { await self?.monitor.seek(to: ms) }
        }

        monitor.$track
            .removeDuplicates { $0?.key == $1?.key }
            .sink { [weak self] track in
                guard let self else { return }
                self.lyrics.load(track)
                self.theme.update(key: track?.key, url: track?.artworkURL, data: nil)
            }
            .store(in: &cancellables)

        monitor.$artworkData
            .compactMap { $0 }
            .sink { [weak self] data in
                guard let self, let track = self.monitor.track else { return }
                self.theme.setArtwork(data, key: track.key)
            }
            .store(in: &cancellables)

        monitor.start()
        installKeyMonitor()
    }

    func toggleLyrics() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showLyrics.toggle() }
    }

    /// Space toggles play/pause unless a text field is being edited.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(event.window?.firstResponder is NSText),
                  self.monitor.track != nil
            else { return event }
            Task { await self.monitor.playPause() }
            return nil
        }
    }
}
