import Foundation

/// The single source of truth for "what's playing". Playback commands go through the
/// Spotify Web API (so they work for any Spotify Connect device) and, when this Mac's
/// built-in Web Playback SDK device is active, directly through the SDK for low latency.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var volume: Double = 0.7
    @Published private(set) var device: Device?
    @Published private(set) var devices: [Device] = []
    @Published var errorMessage: String?

    let clock = PlaybackClock()

    private let api: SpotifyClient
    private let web: WebPlaybackHost
    private var pollTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var lastSDKUpdate = Date.distantPast
    private var ignoreRemoteStateUntil = Date.distantPast

    init(api: SpotifyClient, web: WebPlaybackHost) {
        self.api = api
        self.web = web
        web.onStateChange = { [weak self] state in self?.applySDK(state) }
        web.onDeviceReady = { [weak self] _ in Task { await self?.loadDevices() } }
        clock.onReachedEnd = { [weak self] in
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                await self?.refresh()
            }
        }
    }

    /// True when audio is streaming from this Mac's built-in player.
    var isLocalDeviceActive: Bool {
        guard let local = web.deviceID else { return false }
        return device?.deviceID == local
    }

    var localDeviceID: String? { web.deviceID }

    // MARK: Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval: UInt64 = self.isPlaying && !self.isLocalDeviceActive ? 3 : 8
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            }
        }
    }

    func reset() {
        pollTask?.cancel()
        pollTask = nil
        track = nil
        isPlaying = false
        device = nil
        devices = []
        clock.reset()
    }

    func refresh() async {
        do {
            let state: PlaybackState? = try await api.getIfPresent("me/player", query: ["additional_types": "track"])
            apply(state)
        } catch {
            // Polling failures are transient; commands surface their own errors.
        }
    }

    private func apply(_ state: PlaybackState?) {
        guard Date() >= ignoreRemoteStateUntil else { return }
        guard let state else {
            if !isLocalDeviceActive {
                device = nil
                isPlaying = false
                clock.sync(position: clock.positionMs, duration: clock.durationMs, playing: false)
            }
            return
        }
        device = state.device
        // While the SDK is pushing live events it is the more precise source.
        if isLocalDeviceActive, Date().timeIntervalSince(lastSDKUpdate) < 10 {
            if let item = state.item, item.id == track?.id { track = item }
            return
        }
        if let item = state.item { track = item }
        isPlaying = state.isPlaying
        if let value = state.shuffleState { shuffle = value }
        if let value = state.repeatState.flatMap(RepeatMode.init(rawValue:)) { repeatMode = value }
        if volumeTask == nil, let percent = state.device?.volumePercent { volume = Double(percent) / 100 }
        clock.sync(position: state.progressMs ?? 0, duration: track?.durationMs ?? 0, playing: isPlaying)
    }

    private func applySDK(_ state: WebPlaybackHost.SDKState?) {
        guard let state else { return }
        lastSDKUpdate = Date()
        if let sdkTrack = state.asTrack, sdkTrack.uri != track?.uri { track = sdkTrack }
        isPlaying = !state.paused
        shuffle = state.shuffle
        let modes: [Int: RepeatMode] = [0: .off, 1: .context, 2: .track]
        repeatMode = modes[state.repeatMode] ?? .off
        if let local = web.deviceID, device?.deviceID != local {
            device = Device(deviceID: local, name: "SpotiMusic", type: "Computer", isActive: true,
                            isRestricted: false, volumePercent: Int(volume * 100), supportsVolume: true)
        }
        clock.sync(position: state.position, duration: state.duration, playing: !state.paused)
    }

    // MARK: Commands

    /// Starts playback of a context (album, playlist, artist) or an explicit list of track URIs.
    func play(contextURI: String? = nil, uris: [String]? = nil, offsetURI: String? = nil, shuffle wantsShuffle: Bool? = nil) async {
        var body: [String: Any] = [:]
        if let contextURI { body["context_uri"] = contextURI }
        if let uris { body["uris"] = uris }
        if let offsetURI { body["offset"] = ["uri": offsetURI] }

        await perform {
            guard let target = self.playbackTargetID() else {
                throw PlayerError.noDevice(self.web.status)
            }
            if target == self.web.deviceID { await self.web.activateElement() }
            var shuffleApplied = false
            if let wantsShuffle {
                // Setting shuffle first makes the first song random too; an idle device may reject it.
                shuffleApplied = (try? await self.api.send("PUT", "me/player/shuffle",
                                                           query: ["state": String(wantsShuffle), "device_id": target])) != nil
            }
            try await self.api.send("PUT", "me/player/play", query: ["device_id": target], json: body)
            if let wantsShuffle {
                if !shuffleApplied {
                    try await self.api.send("PUT", "me/player/shuffle", query: ["state": String(wantsShuffle), "device_id": target])
                }
                self.shuffle = wantsShuffle
            }
        }
    }

    func togglePlayPause() async {
        if isLocalDeviceActive {
            setOptimistic(playing: !isPlaying)
            await web.togglePlay()
            return
        }
        if isPlaying {
            setOptimistic(playing: false)
            await perform { try await self.api.send("PUT", "me/player/pause") }
        } else if device != nil {
            setOptimistic(playing: true)
            await perform { try await self.api.send("PUT", "me/player/play") }
        } else if let local = web.deviceID, track != nil {
            await transfer(to: local, play: true)
        } else {
            errorMessage = web.deviceID == nil
                ? PlayerError.noDevice(web.status).localizedDescription
                : "Pick a song, album or playlist to start playing."
        }
    }

    func nextTrack() async {
        if isLocalDeviceActive { await web.nextTrack(); return }
        await perform { try await self.api.send("POST", "me/player/next") }
    }

    func previousTrack() async {
        if clock.positionMs > 3000 {
            await seek(to: 0)
            return
        }
        if isLocalDeviceActive { await web.previousTrack(); return }
        await perform { try await self.api.send("POST", "me/player/previous") }
    }

    func seek(to milliseconds: Int) async {
        let target = max(0, min(milliseconds, clock.durationMs))
        ignoreRemoteStateUntil = Date().addingTimeInterval(1.5)
        clock.sync(position: target, duration: clock.durationMs, playing: isPlaying)
        if isLocalDeviceActive { await web.seek(to: target); return }
        await perform { try await self.api.send("PUT", "me/player/seek", query: ["position_ms": String(target)]) }
    }

    func toggleShuffle() async {
        let newValue = !shuffle
        shuffle = newValue
        ignoreRemoteStateUntil = Date().addingTimeInterval(1.5)
        await perform { try await self.api.send("PUT", "me/player/shuffle", query: ["state": String(newValue)]) }
    }

    func cycleRepeat() async {
        let newValue = repeatMode.next
        repeatMode = newValue
        ignoreRemoteStateUntil = Date().addingTimeInterval(1.5)
        await perform { try await self.api.send("PUT", "me/player/repeat", query: ["state": newValue.rawValue]) }
    }

    /// Updates volume immediately in the UI and sends it to Spotify after a short debounce.
    func setVolume(_ value: Double) {
        volume = max(0, min(1, value))
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, !Task.isCancelled else { return }
            let level = self.volume
            if self.isLocalDeviceActive {
                await self.web.setVolume(level)
            } else if self.device != nil {
                do {
                    try await self.api.send("PUT", "me/player/volume", query: ["volume_percent": String(Int(level * 100))])
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.volumeTask = nil
        }
    }

    func addToQueue(_ track: Track) async {
        guard let uri = track.uri else { return }
        await perform {
            guard self.device != nil || self.web.deviceID != nil else { throw PlayerError.noDevice(self.web.status) }
            try await self.api.send("POST", "me/player/queue", query: ["uri": uri])
        }
    }

    func loadDevices() async {
        do {
            let response: DevicesResponse = try await api.get("me/player/devices")
            devices = response.devices
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func transfer(to deviceID: String, play: Bool? = nil) async {
        if deviceID == web.deviceID { await web.activateElement() }
        await perform {
            try await self.api.send("PUT", "me/player", json: ["device_ids": [deviceID], "play": play ?? self.isPlaying])
        }
        await loadDevices()
    }

    // MARK: Helpers

    private func playbackTargetID() -> String? {
        if let device, device.isActive, let id = device.deviceID { return id }
        return web.deviceID
    }

    private func setOptimistic(playing: Bool) {
        isPlaying = playing
        ignoreRemoteStateUntil = Date().addingTimeInterval(1.5)
        clock.sync(position: clock.positionMs, duration: clock.durationMs, playing: playing)
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            ignoreRemoteStateUntil = .distantPast
        }
        // Give Spotify a moment to apply the command, then pull authoritative state.
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        await refresh()
    }

    enum PlayerError: LocalizedError {
        case noDevice(WebPlaybackHost.Status)

        var errorDescription: String? {
            switch self {
            case .noDevice(let status):
                if case .failed(let reason) = status {
                    return "No Spotify device is available. \(reason)"
                }
                return "No Spotify device is available yet. Wait for the built-in player to connect, or open Spotify on another device."
            }
        }
    }
}
