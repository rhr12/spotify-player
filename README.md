# SpotiMusic

A native macOS music player that looks and feels like Apple Music, and plays your music from **Spotify**.

SwiftUI interface, Spotify Web API for your library, the Spotify Web Playback SDK for audio, and time-synced lyrics from [LRCLIB](https://lrclib.net). No Electron and no cross-platform frameworks.

> SpotiMusic is an independent project. It is not affiliated with, endorsed by, or sponsored by Spotify or Apple.

![Screenshot placeholder: main window](docs/screenshot-main.png)
![Screenshot placeholder: Now Playing with lyrics](docs/screenshot-now-playing.png)

## Features

- **Apple Music layout**: translucent sidebar (Listen Now, Browse, Radio · Library: Recently Added, Artists, Albums, Songs · Playlists), a search field in the sidebar, and Light mode by default (Dark and System are in Settings).
- **Songs table** with #, Title, Artist, Album and Time columns. Rows alternate in shade and highlight on hover. Double-click a row to play it. The context menu has Play, Play Later, Go to Artist, Go to Album and Copy Song Link.
- **Album, playlist and artist pages** with large artwork, Play and Shuffle buttons, and full track lists. Artist pages also have a Station button.
- **Listen Now** shows your recently played music, top songs this month, top artists and your playlists.
- **Browse** has genre tiles that open live Spotify search results. **Radio** starts artist stations built from your top and followed artists.
- **Bottom player bar**:
  - left: artwork, title and artist
  - center: shuffle, previous, play/pause, next, repeat (off/all/one) and a scrubber with elapsed and remaining time
  - right: lyrics toggle, an AirPlay-style device picker and volume
- **Now Playing full screen** (<kbd>⇧⌘F</kbd> or click the artwork): large artwork that breathes while playing and shrinks when paused, over a blurred background colored from the album art that slowly drifts.
- **Time-synced lyrics** in a panel that slides in from the right (or next to the artwork in full screen):
  - Past lines are grey and smaller, the current line is large, bold and white, and upcoming lines are dimmer.
  - The view scrolls with a spring animation.
  - Click any line to jump to it.
- **Spotify Connect**: play on this Mac through the built-in player, or move playback to any of your Spotify devices.
- **Keyboard**: <kbd>Space</kbd> play/pause, <kbd>⌘→</kbd>/<kbd>⌘←</kbd> next/previous, <kbd>⌘↑</kbd>/<kbd>⌘↓</kbd> volume, <kbd>⌥⌘S</kbd> shuffle, <kbd>⌥⌘R</kbd> repeat, <kbd>⇧⌘L</kbd> lyrics, <kbd>Esc</kbd> closes Now Playing.

## Requirements

- macOS 13 Ventura or later
- **Spotify Premium.** Spotify requires it for the Web Playback SDK and for playback control.
- A free Spotify Developer app (Client ID). Setup is below.

## Spotify Developer Dashboard setup

1. Go to <https://developer.spotify.com/dashboard> and log in with your Spotify account.
2. Click **Create app**:
   - **App name / description**: anything, e.g. "SpotiMusic".
   - **Redirect URI**: `http://127.0.0.1:43824/callback` (exactly this value).
   - **Which API/SDKs are you planning to use?** Check **Web API** and **Web Playback SDK**.
3. Save, open the app's **Settings** and copy the **Client ID**. You don't need the Client Secret: SpotiMusic uses PKCE.
4. Apps in *Development Mode* only work for users listed under **User Management**. If anyone other than you will sign in, add their Spotify email there.

## Install

1. Download `SpotiMusic-x.y.z.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **SpotiMusic** to **Applications**.
3. The build is ad-hoc signed, not notarized. The first time you open it, right-click the app and choose **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/SpotiMusic.app
   ```
4. Paste your Client ID, click **Connect Spotify** and approve access in your browser.

## Build from source

```sh
brew install xcodegen create-dmg
./scripts/build.sh          # generates SpotiMusic.xcodeproj and builds build/SpotiMusic.app
./scripts/package_dmg.sh    # creates build/SpotiMusic-1.0.0.dmg
```

To work in Xcode, run `xcodegen generate` and open `SpotiMusic.xcodeproj`. The Xcode project is generated from `project.yml` and is not committed.

GitHub Actions (`.github/workflows/build.yml`) builds the app and DMG on every push. Pushing a `v*` tag publishes a GitHub Release with the DMG attached.

## How it works

| Piece | Implementation |
| --- | --- |
| Sign-in | OAuth 2.0 Authorization Code + **PKCE** in your default browser. A one-shot loopback HTTP server (`Network.framework`) on `127.0.0.1:43824` catches the redirect. |
| Tokens | Stored in the **Keychain** and refreshed silently before they expire. The Client ID is kept in user defaults on your Mac only. |
| Library & metadata | Spotify Web API through a small async/await client (`SpotifyClient`) with token refresh, 429 back-off and paging. |
| Audio | The **Spotify Web Playback SDK** runs inside a hidden, 1-point `WKWebView` and registers this Mac as the "SpotiMusic" Spotify Connect device. |
| Controls | Spotify Web API player endpoints, which work with any Connect device. Calls go straight to the SDK when this Mac is the active device. |
| Lyrics | `GET https://lrclib.net/api/get` (exact match), falling back to `/api/search`. LRC timestamps are parsed and synced to the playback clock, with plain lyrics or "No lyrics available" as fallbacks. Results are cached in memory. |
| Colors | `CIAreaAverage` over bands of the artwork, then tuned for legible white text. |

### Notes and limitations

- **Built-in player and DRM.** Spotify streams through Encrypted Media Extensions. If WebKit on your macOS version can't start the Web Playback SDK, SpotiMusic says so (in the device picker and Settings ▸ Playback) and keeps working as a full remote. Open Spotify on any phone, speaker or computer and SpotiMusic browses, plays and controls it, including lyrics.
- **Spotify's February 2026 API changes.** Spotify removed several endpoints for Development Mode apps, including new releases, browse categories, artist top tracks and featured or editorial playlists. SpotiMusic uses only endpoints that remain available: Browse runs on genre search and Radio on artist contexts. Playlist items are read from the new `/playlists/{id}/items` endpoint, with a fallback to the old `/tracks` path.
- **Rate limits.** Development Mode apps share a modest rate limit. SpotiMusic polls playback state only every 3–8 seconds and works out the position in between.

## Privacy

SpotiMusic talks only to Spotify (`accounts.spotify.com`, `api.spotify.com`, `sdk.scdn.co`, Spotify's audio CDNs) and `lrclib.net`. It has no analytics and no servers of its own. No credentials or tokens are stored in this repository.

## License

MIT
