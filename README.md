# SpotiMusic

A macOS app that shows Apple Music–style, time-synced lyrics for whatever is playing on your Mac in **Spotify** or **Music**.

Start a song in either app and SpotiMusic follows it. You get the artwork over a blurred, color-matched background, a scrubber and controls, and word-by-word lyrics that move with the song. You don't need to sign in, have Spotify Premium, or set up a developer account.

> SpotiMusic is an independent project. It is not affiliated with Spotify, Apple, am-lyrics or Spicy Lyrics.

![Screenshot placeholder](docs/screenshot.png)

## Features

- **Follows your music**: detects the song, artist, album, artwork, play state and position in Spotify and Music (via AppleScript and their playback notifications). It switches to whichever app is playing.
- **Lyrics from [am-lyrics](https://github.com/binimum/am-lyrics)** first: Apple Music–style word-by-word lyrics from lrc.red, BiniLyrics, Spicy Lyrics, Unison, LyricsPlus, LRCLIB and Genius.
- **Spicy Lyrics fallback** (optional): if am-lyrics has nothing, SpotiMusic asks [Spicy Lyrics](https://spicylyrics.org) using **your own API key** (Settings ▸ Lyrics).
- **Stays in sync**: lyrics advance every frame between position checks, and re-sync on seek, skip, play and pause. Click a lyric line to jump the song to it.
- **Now Playing look**: large artwork that breathes while playing and shrinks when paused, over blurred artwork with slowly drifting album colors.
- **Controls** that drive the source app: play/pause, previous/next, scrubbing and volume.
- **Keyboard**: <kbd>Space</kbd> play/pause, <kbd>⌘→</kbd>/<kbd>⌘←</kbd> next/previous, <kbd>⌘↑</kbd>/<kbd>⌘↓</kbd> volume, <kbd>⇧⌘L</kbd> show/hide lyrics.

## Requirements

- macOS 13 Ventura or later
- Spotify for Mac and/or the Music app

The first time SpotiMusic reads from Spotify or Music, macOS asks for permission to control that app. Click **OK**. You can change this later in System Settings ▸ Privacy & Security ▸ Automation.

## Install

1. Download `SpotiMusic-x.y.z.dmg` from [Releases](../../releases).
2. Open it and drag **SpotiMusic** to **Applications**.
3. The build is ad-hoc signed, not notarized. The first time you open it, right-click the app and choose **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/SpotiMusic.app
   ```

## Lyrics sources

| Order | Source | Notes |
| --- | --- | --- |
| 1 | **am-lyrics** web component, v1.8.8, bundled in the app | Searches its providers by title, artist, album, duration and (for Spotify) track ID. |
| 2 | **Spicy Lyrics** with your API key | Used only when am-lyrics finds nothing. Needs the Spotify track ID, so it applies to songs playing in Spotify. The key is stored in your Keychain. |

## Build from source

```sh
brew install xcodegen create-dmg
./scripts/build.sh          # generates SpotiMusic.xcodeproj and builds build/SpotiMusic.app
./scripts/package_dmg.sh    # creates build/SpotiMusic-1.0.0.dmg
```

GitHub Actions builds the app and DMG on every push. Pushing a `v*` tag publishes a GitHub Release with the DMG attached.

## How it works

- `NowPlayingMonitor` polls Spotify and Music once a second with AppleScript, and immediately when they post playback notifications. It keeps a playback clock and re-anchors it whenever the reported position drifts.
- `LyricsController` hosts the bundled am-lyrics component in a transparent `WKWebView`:
  - It passes in the track metadata and updates `currentTime` every animation frame.
  - It watches the component's state to tell whether any provider found lyrics.
  - If none did, it fetches Spicy Lyrics natively, converts the response to TTML and hands that back to am-lyrics, so it renders the same way.
- `ArtworkTheme` extracts colors from the artwork with `CIAreaAverage` for the background.

## Privacy

SpotiMusic reads only the current track from Spotify and Music on your Mac. Lyrics lookups send the song's title, artist, album and duration to the providers listed above. It has no analytics and no servers of its own. No API keys or tokens are stored in this repository.

## License

SpotiMusic is MIT licensed. The bundled am-lyrics component (`SpotiMusic/Resources/Web/am-lyrics.js`) is © its authors under the Mozilla Public License 2.0. Its license is in `SpotiMusic/Resources/Web/am-lyrics-LICENSE.txt`, and the source is at <https://github.com/binimum/am-lyrics>.
