# Changelog

All notable changes to Harmonic are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-21

### Added
- Initial public release
- SwiftUI menu bar player with track info display
- Transport controls: skip forward, like/unlike, play/pause
- Borderless popover player window (300×300 pt)
- Spotify OAuth 2.0 integration for secure authentication
- Live playback tracking with 1-second update frequency
- Hover-activated controls overlay in player
- Settings sheet for Spotify account configuration
- Keyboard shortcut: Cmd+Q to quit
- Global mouse monitor for window dismissal
- Support for Spotify artwork display (from CDN or iTunes fallback)

### Technical
- macOS 13+ support
- Built with Swift 5.9 and SwiftUI
- No external dependencies beyond Apple frameworks
- Uses Spotify Web API for official integration
