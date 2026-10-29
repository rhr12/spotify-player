import Foundation
import WebKit

/// Hosts the am-lyrics web component (bundled, MPL-2.0) in a transparent WKWebView.
/// am-lyrics searches its providers first; if it finds nothing and the user has added a
/// Spicy Lyrics API key, we fetch Spicy Lyrics natively and hand am-lyrics the result as TTML.
@MainActor
final class LyricsController: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case searching
        case found(source: String)
        case searchingSpicy
        case notFound(reason: String)
    }

    @Published private(set) var status: Status = .idle

    let webView: WKWebView
    var onSeek: ((Int) -> Void)?

    private var pageReady = false
    private var pendingScripts: [String] = []
    private var requestID = 0
    private var track: NowPlayingTrack?
    private var spicyTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        super.init()
        configuration.userContentController.add(LyricsMessageHandler(self), name: "native")
        loadPage()
    }

    private func loadPage() {
        guard let url = Bundle.main.url(forResource: "am-lyrics", withExtension: "js"),
              let component = try? String(contentsOf: url, encoding: .utf8) else {
            status = .notFound(reason: "The lyrics component is missing from the app bundle.")
            return
        }
        let html = Self.pageTemplate.replacingOccurrences(of: "/*AM_LYRICS*/", with: component)
        // An https origin gives the page a secure context and normal CORS behaviour for the providers.
        webView.loadHTMLString(html, baseURL: URL(string: "https://localhost/"))
    }

    // MARK: API

    func load(_ track: NowPlayingTrack?) {
        guard track?.key != self.track?.key else { return }
        self.track = track
        spicyTask?.cancel()
        requestID += 1
        guard let track else {
            status = .idle
            evaluate("window.spoti.clear()")
            return
        }
        status = .searching
        let payload: [String: Any] = [
            "id": requestID,
            "title": track.title,
            "artist": track.artist,
            "album": track.album,
            "durationMs": track.durationMs,
            "spotifyId": track.spotifyID ?? "",
        ]
        evaluate("window.spoti.load(\(Self.json(payload)))")
    }

    func sync(positionMs: Int, playing: Bool) {
        evaluate("window.spoti.sync(\(positionMs), \(playing))")
    }

    // MARK: Bridge

    fileprivate func receive(_ body: Any) {
        guard let text = body as? String,
              let message = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = message["type"] as? String else { return }
        let id = message["id"] as? Int

        switch type {
        case "ready":
            pageReady = true
            pendingScripts.forEach { webView.evaluateJavaScript($0) }
            pendingScripts.removeAll()
        case "found":
            guard id == requestID else { return }
            if status != .searchingSpicy {
                status = .found(source: (message["source"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "am-lyrics")
            }
        case "notFound":
            guard id == requestID else { return }
            trySpicyLyrics()
        case "seek":
            if let ms = message["ms"] as? Double { onSeek?(Int(ms)) }
        default:
            break
        }
    }

    private func trySpicyLyrics() {
        guard let key = SpicyLyricsClient.apiKey else {
            status = .notFound(reason: "No lyrics found. Add a Spicy Lyrics API key in Settings for another source.")
            return
        }
        guard let track, let spotifyID = track.spotifyID else {
            status = .notFound(reason: "No lyrics found. (Spicy Lyrics needs a song playing in Spotify.)")
            return
        }
        status = .searchingSpicy
        let id = requestID
        spicyTask = Task { [weak self] in
            do {
                let ttml = try await SpicyLyricsClient().ttml(spotifyTrackID: spotifyID, apiKey: key)
                guard let self, !Task.isCancelled, id == self.requestID else { return }
                if let ttml {
                    self.status = .found(source: "Spicy Lyrics")
                    self.evaluate("window.spoti.showTTML(\(id), \(Self.json(["ttml": ttml])).ttml)")
                } else {
                    self.status = .notFound(reason: "No lyrics found for this song.")
                }
            } catch {
                guard let self, !Task.isCancelled, id == self.requestID else { return }
                self.status = .notFound(reason: "No lyrics found. \(error.localizedDescription)")
            }
        }
    }

    private func evaluate(_ script: String) {
        if pageReady {
            webView.evaluateJavaScript(script)
        } else {
            pendingScripts.append(script)
        }
    }

    private static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private static let pageTemplate = """
    <!doctype html>
    <html><head><meta charset="utf-8">
    <style>
      html, body { margin: 0; height: 100%; background: transparent; overflow: hidden; }
      body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif; }
      am-lyrics {
        display: block; height: 100vh;
        --am-lyrics-highlight-color: #ffffff;
        --lyplus-font-size-base: 34px;
        --lyrics-scroll-padding-top: 30%;
      }
    </style></head>
    <body>
    <am-lyrics id="lyrics" highlight-color="#ffffff"
      font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif"
      autoscroll interpolate></am-lyrics>
    <script type="module">/*AM_LYRICS*/</script>
    <script type="module">
      const el = document.getElementById('lyrics');
      const post = (m) => window.webkit.messageHandlers.native.postMessage(JSON.stringify(m));
      let anchor = { pos: 0, at: performance.now(), playing: false };
      let current = 0;

      // Advance currentTime every frame so word-by-word highlighting stays smooth between polls.
      const frame = () => {
        if (anchor.playing) el.currentTime = Math.round(anchor.pos + performance.now() - anchor.at);
        requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);

      // am-lyrics has no "done" event, so watch its state to learn whether any provider had lyrics.
      const watch = (id) => {
        const started = performance.now();
        let sawLoading = false;
        const timer = setInterval(() => {
          if (id !== current) { clearInterval(timer); return; }
          if (el.isLoading) sawLoading = true;
          const elapsed = performance.now() - started;
          if (el.lyrics && el.lyrics.length) {
            clearInterval(timer);
            post({ type: 'found', id, source: el.lyricsSource || '' });
          } else if (!el.isLoading && el.hasFetchedAllProviders && (sawLoading || elapsed > 4000)) {
            clearInterval(timer);
            post({ type: 'notFound', id });
          } else if (elapsed > 45000) {
            clearInterval(timer);
            post({ type: 'notFound', id });
          }
        }, 250);
      };

      window.spoti = {
        load(meta) {
          current = meta.id;
          el.ttml = undefined;
          el.duration = -1;
          el.songTitle = meta.title;
          el.songArtist = meta.artist;
          el.songAlbum = meta.album || undefined;
          el.songDurationMs = meta.durationMs || undefined;
          el.spotifyId = meta.spotifyId || undefined;
          el.query = `${meta.title} ${meta.artist}`;
          watch(meta.id);
        },
        showTTML(id, ttml) {
          if (id !== current) return;
          el.ttml = ttml;
        },
        sync(pos, playing) {
          anchor = { pos, at: performance.now(), playing };
          el.currentTime = pos;
        },
        clear() {
          current = -1;
          el.duration = -1;
          el.ttml = undefined;
          el.songTitle = undefined;
          el.songArtist = undefined;
          el.query = undefined;
        },
      };
      el.addEventListener('line-click', (e) => post({ type: 'seek', ms: e.detail.timestamp }));
      post({ type: 'ready' });
    </script>
    </body></html>
    """
}

/// Breaks the retain cycle between `WKUserContentController` and the controller.
private final class LyricsMessageHandler: NSObject, WKScriptMessageHandler {
    weak var controller: LyricsController?
    init(_ controller: LyricsController) { self.controller = controller }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        let controller = self.controller
        Task { @MainActor in controller?.receive(body) }
    }
}
