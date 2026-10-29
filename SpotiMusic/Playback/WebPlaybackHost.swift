import Foundation
import WebKit

/// Hosts the Spotify Web Playback SDK inside an invisible `WKWebView`. The SDK registers
/// this Mac as a Spotify Connect device ("SpotiMusic") and streams the audio; the native
/// UI drives it through the Web API and the JavaScript bridge below.
@MainActor
final class WebPlaybackHost: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case ready
        case failed(String)

        var description: String {
            switch self {
            case .idle: return "Not started"
            case .connecting: return "Connecting…"
            case .ready: return "Ready"
            case .failed(let message): return message
            }
        }
    }

    /// Snapshot of the SDK's `player_state_changed` payload, simplified in JavaScript.
    struct SDKState: Decodable {
        struct SDKImage: Decodable { let url: String; let width: Int?; let height: Int? }
        struct SDKArtist: Decodable { let name: String; let uri: String? }
        struct SDKAlbum: Decodable { let name: String; let uri: String?; let images: [SDKImage] }
        struct SDKTrack: Decodable {
            let id: String?
            let uri: String?
            let name: String
            let durationMs: Int
            let artists: [SDKArtist]
            let album: SDKAlbum
        }
        let paused: Bool
        let position: Int
        let duration: Int
        let shuffle: Bool
        let repeatMode: Int
        let track: SDKTrack?

        var asTrack: Track? {
            guard let track else { return nil }
            func id(from uri: String?) -> String? { uri?.split(separator: ":").last.map(String.init) }
            let albumURI = track.album.uri ?? ""
            let album = Album(
                id: id(from: albumURI) ?? albumURI,
                name: track.album.name,
                uri: albumURI,
                images: track.album.images.map { SpotifyImage(url: $0.url, width: $0.width, height: $0.height) },
                artists: track.artists.map { SimpleArtist(id: id(from: $0.uri), name: $0.name, uri: $0.uri) },
                releaseDate: nil, totalTracks: nil, albumType: nil, genres: nil
            )
            return Track(
                id: track.id ?? id(from: track.uri),
                name: track.name,
                uri: track.uri,
                durationMs: track.durationMs,
                artists: track.artists.map { SimpleArtist(id: id(from: $0.uri), name: $0.name, uri: $0.uri) },
                album: album
            )
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var deviceID: String?

    var tokenProvider: (() async throws -> String)?
    var onStateChange: ((SDKState?) -> Void)?
    var onDeviceReady: ((String) -> Void)?

    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        // Present as Safari so the SDK enables its supported-browser code path.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        super.init()
        controller.add(WeakMessageHandler(self), name: "native")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
    }

    // MARK: Lifecycle

    func start() {
        guard status == .idle || isFailed else { return }
        status = .connecting
        deviceID = nil
        // A loopback origin is a secure context, which the SDK's DRM (EME) playback requires.
        webView.loadHTMLString(Self.page, baseURL: URL(string: "http://127.0.0.1:43824/"))
    }

    func stop() {
        Task { try? await call("window.player && window.player.disconnect()") }
        webView.loadHTMLString("<html></html>", baseURL: nil)
        status = .idle
        deviceID = nil
    }

    func restart() {
        stop()
        start()
    }

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    // MARK: Commands

    func togglePlay() async { try? await call("await window.player.togglePlay()") }
    func pause() async { try? await call("await window.player.pause()") }
    func resume() async { try? await call("await window.player.resume()") }
    func nextTrack() async { try? await call("await window.player.nextTrack()") }
    func previousTrack() async { try? await call("await window.player.previousTrack()") }

    func seek(to milliseconds: Int) async {
        try? await call("await window.player.seek(ms)", arguments: ["ms": milliseconds])
    }

    func setVolume(_ volume: Double) async {
        try? await call("await window.player.setVolume(v)", arguments: ["v": max(0, min(1, volume))])
    }

    /// Unlocks media playback in the web view; call before starting playback on this device.
    func activateElement() async {
        try? await call("window.player && window.player.activateElement && await window.player.activateElement()")
    }

    private func call(_ script: String, arguments: [String: Any] = [:]) async throws {
        guard status == .ready else { return }
        try await evaluate(script, arguments: arguments)
    }

    private func evaluate(_ script: String, arguments: [String: Any]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Bridge

    fileprivate func receive(_ body: Any) {
        guard let json = body as? String, let data = json.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = message["type"] as? String else { return }

        switch type {
        case "token":
            Task { await deliverToken() }
        case "ready":
            let id = message["deviceID"] as? String
            deviceID = id
            status = .ready
            if let id { onDeviceReady?(id) }
        case "notReady":
            deviceID = nil
            status = .connecting
        case "state":
            struct Envelope: Decodable { let state: SDKState? }
            let state = (try? JSONDecoder().decode(Envelope.self, from: data))?.state
            onStateChange?(state)
        case "error":
            let kind = message["kind"] as? String ?? "error"
            let text = message["message"] as? String ?? "Unknown error"
            switch kind {
            case "playback_error":
                // Transient; the SDK keeps working.
                break
            case "account_error":
                status = .failed("Spotify Premium is required for the built-in player.")
            case "initialization_error":
                status = .failed("The built-in player isn't supported here (\(text)). Use Spotify on another device; SpotiMusic will control it.")
            default:
                status = .failed("Built-in player error: \(text)")
            }
        default:
            break
        }
    }

    private func deliverToken() async {
        guard let tokenProvider, let token = try? await tokenProvider() else { return }
        try? await evaluate("window.__spotiToken(t)", arguments: ["t": token])
    }

    private static let page = """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>SpotiMusic Player</title></head>
    <body>
    <script>
      const post = (m) => window.webkit.messageHandlers.native.postMessage(JSON.stringify(m));
      let waiting = [];
      window.__spotiToken = (t) => { const w = waiting; waiting = []; w.forEach(cb => cb(t)); };
      const simplify = (s) => {
        const t = s.track_window && s.track_window.current_track;
        return {
          paused: !!s.paused, position: s.position || 0, duration: s.duration || 0,
          shuffle: !!s.shuffle, repeatMode: s.repeat_mode || 0,
          track: t ? {
            id: t.id, uri: t.uri, name: t.name, durationMs: t.duration_ms || s.duration || 0,
            artists: (t.artists || []).map(a => ({ name: a.name, uri: a.uri })),
            album: { name: (t.album && t.album.name) || '', uri: t.album && t.album.uri,
                     images: ((t.album && t.album.images) || []).map(i => ({ url: i.url, width: i.width, height: i.height })) }
          } : null
        };
      };
      window.onSpotifyWebPlaybackSDKReady = () => {
        const player = new Spotify.Player({
          name: 'SpotiMusic',
          volume: 0.7,
          getOAuthToken: cb => { waiting.push(cb); post({ type: 'token' }); }
        });
        window.player = player;
        player.addListener('ready', ({ device_id }) => post({ type: 'ready', deviceID: device_id }));
        player.addListener('not_ready', ({ device_id }) => post({ type: 'notReady', deviceID: device_id }));
        player.addListener('player_state_changed', s => post({ type: 'state', state: s ? simplify(s) : null }));
        ['initialization_error', 'authentication_error', 'account_error', 'playback_error'].forEach(kind =>
          player.addListener(kind, ({ message }) => post({ type: 'error', kind, message })));
        player.connect().then(ok => { if (!ok) post({ type: 'error', kind: 'connect', message: 'Could not connect to Spotify.' }); });
      };
      if (!navigator.requestMediaKeySystemAccess) {
        post({ type: 'error', kind: 'initialization_error', message: 'Encrypted Media Extensions are unavailable' });
      }
    </script>
    <script src="https://sdk.scdn.co/spotify-player.js"
            onerror="post({ type: 'error', kind: 'load', message: 'Could not download the Spotify Web Playback SDK.' })"></script>
    </body></html>
    """
}

/// Breaks the retain cycle between `WKUserContentController` and its handler.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var host: WebPlaybackHost?
    init(_ host: WebPlaybackHost) { self.host = host }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        let host = self.host
        Task { @MainActor in host?.receive(body) }
    }
}
