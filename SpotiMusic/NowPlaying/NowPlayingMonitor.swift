import AppKit
import Foundation

/// The song currently playing in a desktop music app.
struct NowPlayingTrack: Equatable {
    enum Source: String, CaseIterable {
        case spotify = "Spotify"
        case music = "Music"

        var bundleID: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music: return "com.apple.Music"
            }
        }

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }

        var isInstalled: Bool {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }

        var icon: NSImage? {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        }

        var defaultsKey: String { "follow\(rawValue)" }
    }

    let source: Source
    let title: String
    let artist: String
    let album: String
    let durationMs: Int
    /// The 22-character Spotify track ID (Spotify only), used for the Spicy Lyrics fallback.
    let spotifyID: String?
    let persistentID: String?
    let artworkURL: URL?

    var key: String {
        "\(source.rawValue):\(spotifyID ?? persistentID ?? "\(title)|\(artist)|\(durationMs)")"
    }
}

/// Watches Spotify and Music through AppleScript (plus their playback notifications for
/// instant updates), and exposes the current song, play state and position.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var volume: Double?
    @Published private(set) var artworkData: Data?
    /// Set when macOS blocked SpotiMusic from asking an app what's playing.
    @Published private(set) var permissionDenied: NowPlayingTrack.Source?

    let clock = PlaybackClock()

    /// Called whenever the playback position is re-anchored (track change, play/pause, seek or drift).
    var onSync: ((_ positionMs: Int, _ playing: Bool) -> Void)?

    private struct Snapshot {
        let source: NowPlayingTrack.Source
        let state: String
        let track: NowPlayingTrack?
        let positionMs: Int
        let volume: Double?
        var isPlaying: Bool { state == "playing" }
    }

    private let runner = AppleScriptRunner()
    private var timer: Timer?
    private var polling = false
    private var lastSource: NowPlayingTrack.Source?
    private var anchorPosition = 0
    private var anchorDate = Date()
    private var ignoreUntil = Date.distantPast
    private var volumeTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.poll() }
            })
        }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await poll() }
    }

    private func isFollowing(_ source: NowPlayingTrack.Source) -> Bool {
        UserDefaults.standard.object(forKey: source.defaultsKey) as? Bool ?? true
    }

    // MARK: Polling

    func poll() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }

        var snapshots: [Snapshot] = []
        var denied: NowPlayingTrack.Source?
        for source in NowPlayingTrack.Source.allCases where isFollowing(source) && source.isRunning {
            switch await runner.run(Self.pollScript(for: source)) {
            case .success(let result):
                snapshots.append(Self.snapshot(from: result, source: source))
            case .failure(let error):
                if error.isPermissionDenied { denied = source }
            }
        }
        permissionDenied = denied
        guard Date() >= ignoreUntil else { return }
        apply(choose(from: snapshots))
    }

    /// Prefers whichever app is playing; otherwise sticks with the last app we followed.
    private func choose(from snapshots: [Snapshot]) -> Snapshot? {
        let withTrack = snapshots.filter { $0.track != nil }
        return withTrack.first { $0.isPlaying && $0.source == lastSource }
            ?? withTrack.first { $0.isPlaying }
            ?? withTrack.first { $0.source == lastSource }
            ?? withTrack.first
    }

    private func apply(_ snapshot: Snapshot?) {
        guard let snapshot, let newTrack = snapshot.track else {
            if track != nil {
                track = nil
                artworkData = nil
                isPlaying = false
                clock.reset()
                onSync?(0, false)
            }
            return
        }
        lastSource = snapshot.source
        if let level = snapshot.volume, volumeTask == nil { volume = level }

        let trackChanged = newTrack.key != track?.key
        if trackChanged {
            track = newTrack
            artworkData = nil
            if newTrack.source == .music { Task { await loadMusicArtwork(for: newTrack) } }
        }

        let predicted = isPlaying ? anchorPosition + Int(Date().timeIntervalSince(anchorDate) * 1000) : anchorPosition
        let drift = abs(predicted - snapshot.positionMs)
        if trackChanged || snapshot.isPlaying != isPlaying || drift > 350 {
            isPlaying = snapshot.isPlaying
            anchor(snapshot.positionMs)
        }
    }

    private func anchor(_ positionMs: Int) {
        anchorPosition = positionMs
        anchorDate = Date()
        clock.sync(position: positionMs, duration: track?.durationMs ?? 0, playing: isPlaying)
        onSync?(positionMs, isPlaying)
    }

    private func loadMusicArtwork(for track: NowPlayingTrack) async {
        let script = """
        tell application id "com.apple.Music"
            try
                return raw data of artwork 1 of current track
            end try
        end tell
        """
        guard case .success(let result) = await runner.run(script), self.track?.key == track.key else { return }
        let data = result.data
        if !data.isEmpty { artworkData = data }
    }

    // MARK: Commands

    func playPause() async {
        guard let source = track?.source else { return }
        isPlaying.toggle()
        ignoreUntil = Date().addingTimeInterval(0.6)
        anchor(clock.positionMs)
        await command("playpause", source)
    }

    func next() async {
        guard let source = track?.source else { return }
        await command("next track", source)
    }

    func previous() async {
        guard let source = track?.source else { return }
        // Like the apps themselves: restart the song unless we're at its very beginning.
        if clock.positionMs > 3000 {
            await seek(to: 0)
        } else {
            await command("previous track", source)
        }
    }

    func seek(to milliseconds: Int) async {
        guard let track else { return }
        let target = max(0, min(milliseconds, track.durationMs))
        ignoreUntil = Date().addingTimeInterval(0.8)
        anchor(target)
        let seconds = String(format: "%.3f", Double(target) / 1000)
        await command("set player position to \(seconds)", track.source)
    }

    func setVolume(_ level: Double) {
        guard let source = track?.source else { return }
        let clamped = max(0, min(1, level))
        volume = clamped
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.command("set sound volume to \(Int((clamped * 100).rounded()))", source)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled { self.volumeTask = nil }
        }
    }

    func activateSourceApp() {
        guard let source = track?.source,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first
        else { return }
        app.activate(options: [])
    }

    private func command(_ statement: String, _ source: NowPlayingTrack.Source) async {
        guard source.isRunning else { return }
        let result = await runner.run("tell application id \"\(source.bundleID)\" to \(statement)")
        if case .failure(let error) = result, error.isPermissionDenied { permissionDenied = source }
        try? await Task.sleep(nanoseconds: 250_000_000)
        ignoreUntil = .distantPast
        await poll()
    }

    // MARK: Scripts

    private static func pollScript(for source: NowPlayingTrack.Source) -> String {
        switch source {
        case .spotify:
            return """
            tell application id "com.spotify.client"
                set ps to player state as string
                if ps is "stopped" then return {ps}
                set t to current track
                return {ps, name of t, artist of t, album of t, (duration of t) as string, (player position) as string, id of t, artwork url of t, (sound volume) as string}
            end tell
            """
        case .music:
            return """
            tell application id "com.apple.Music"
                set ps to player state as string
                if ps is "stopped" then return {ps}
                try
                    set t to current track
                    return {ps, name of t, artist of t, album of t, (duration of t) as string, (player position) as string, persistent ID of t, "", (sound volume) as string}
                on error
                    return {ps}
                end try
            end tell
            """
        }
    }

    private static func snapshot(from result: NSAppleEventDescriptor, source: NowPlayingTrack.Source) -> Snapshot {
        let state = result.string(at: 1) ?? "stopped"
        guard result.numberOfItems >= 9, let title = result.string(at: 2), !title.isEmpty else {
            return Snapshot(source: source, state: state, track: nil, positionMs: 0, volume: nil)
        }
        let rawDuration = result.number(at: 5) ?? 0
        // Spotify reports duration in milliseconds, Music in seconds.
        let durationMs = source == .spotify ? Int(rawDuration) : Int(rawDuration * 1000)
        let positionMs = Int((result.number(at: 6) ?? 0) * 1000)
        let identifier = result.string(at: 7) ?? ""
        let spotifyID = source == .spotify ? identifier.split(separator: ":").last.map(String.init) : nil
        let track = NowPlayingTrack(
            source: source,
            title: title,
            artist: result.string(at: 3) ?? "",
            album: result.string(at: 4) ?? "",
            durationMs: durationMs,
            spotifyID: spotifyID.flatMap { $0.count == 22 ? $0 : nil },
            persistentID: source == .music ? identifier : nil,
            artworkURL: result.string(at: 8).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        )
        return Snapshot(source: source, state: state, track: track, positionMs: positionMs,
                        volume: result.number(at: 9).map { $0 / 100 })
    }
}
