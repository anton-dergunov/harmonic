# Changelog

## [0.6.0] - 2026-06-05

### Harmonic v0.6.0 - Auto-Update

- **Auto-update** — Harmonic can now check for and install new versions directly from within the app. When an update is found, a dialog shows the full release notes and lets you install with one click. Updates installed this way skip the Gatekeeper security warning you normally see when installing manually from a downloaded file. Options to enable automatic daily checking and automatic silent installation are in Settings → General, along with a "Check Now" button
- **Fixed**: The quick-add playlist dialog (⌥⌘A) no longer opens when Spotify is not connected
- **Fixed**: After closing the quick-add playlist dialog, focus now correctly returns to the app you were previously working in

## [0.5.0] - 2026-06-04

### Harmonic v0.5.0 - Quick-Add Playlist Hotkey

- **Quick-add to playlist** — press ⌥⌘A from any app to open a searchable playlist picker; type to filter, press Enter or click to add the current track instantly
- **Alphabetical playlist order** — playlists are now sorted A–Z in all menus and the picker dialog
- **Like when adding to playlist** — new toggle in Settings → Spotify that automatically likes the track whenever you add it to a playlist (skips if already liked)
- **Configurable Add-to-Playlist hotkey** — the new shortcut is adjustable in Settings → Shortcuts alongside the existing Like and Player Window shortcuts

## [0.4.0] - 2026-06-03

### Harmonic v0.4.0 - Playlists & Richer Controls

- **Add to playlist** — add the current song to any of your Spotify playlists directly from the player window or the right-click menu
- **Playback controls in right-click menu** — play/pause, previous, skip forward, like/unlike, and add-to-playlist are now available from the status-bar context menu
- **Action logging** — when song logging is enabled, Harmonic now also records play/pause, skip, seek, and add-to-playlist actions with timestamps

## [0.3.0] - 2026-05-28

### Harmonic v0.3.0 - Richer Right-Click Menu

- **Copy track details** - right-click to copy "Artist – Song", just the song, or just the artist to the clipboard
- **Open in Spotify, expanded** - the right-click menu now opens the current track, artist, or album in Spotify
- **Search on Google** - right-click to look up "Artist – Song" or the artist in your default browser
- **Polished menu bar item** - the menu bar item now dims on inactive displays, matching the rest of the menu bar

## [0.2.0] - 2026-05-24

### Harmonic v0.2.0 - Settings, Shortcuts & More

- **Customizable menu bar** - choose which controls appear in the menu bar strip
- **Keyboard shortcuts** - global hotkeys to like/unlike (⌥L by default) and toggle the player window, all customizable
- **Launch at Login** - start Harmonic automatically when you log in
- **Open in Spotify** - jump to the current track in the Spotify app from the player or right-click menu
- **Idle state** - a friendly placeholder appears when nothing is playing
- **Song logging** - optionally keep a local log of your listening history

## [0.1.0] - 2026-05-21

### Harmonic v0.1.0 - Initial Release

The first release of Harmonic, a minimal Spotify controller that lives in your macOS menu bar.

- **Menu bar track info** - see artist and song name at a glance without switching apps
- **Like / unlike** - save or remove the current track from your Liked Songs with one click
- **Skip forward** - jump ahead in a track directly from the menu bar
- **Player window** - see album art and control playback
- **Spotify connection** - connect your Spotify account once through Settings; Harmonic handles the rest

---

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
