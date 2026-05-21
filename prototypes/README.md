# Harmonic Prototypes

This directory contains experimental tools and scripts. These are not part of the main app distribution.

## Python CLI: `spotify_liked.py`

A command-line tool that checks and toggles the liked state of the currently playing Spotify track.

### Features

- **Status checking** — Print whether the current track is in your library
- **Liked state control** — Like, unlike, or toggle the current track
- **Zero authentication** — Uses browser session cookies instead of Spotify Developer API

### Requirements

- macOS with [Spotify](https://www.spotify.com/download/mac/) desktop app running
- A Chromium-based browser (Chrome, Brave, or Edge) signed in at [open.spotify.com](https://open.spotify.com/)
- Python 3.10+

### Setup

```bash
# Create virtual environment (once)
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

Grant **Automation** access for your terminal to **Spotify** and your browser when macOS prompts you:
- System Settings → Privacy & Security → Automation

**Optional:** In Chrome, enable **Develop → Allow JavaScript from Apple Events** for faster operation if a track tab is already open.

### Usage

```bash
python spotify_liked.py              # Print yes or no (default: status)
python spotify_liked.py status       # Check if current track is liked
python spotify_liked.py toggle       # Flip liked state and print result
python spotify_liked.py like         # Like if needed; print yes
python spotify_liked.py unlike       # Unlike if needed; print no
```

Output is always `yes` or `no` on stdout; errors go to stderr.

### How It Works

1. **Get track ID** — Uses AppleScript to read the current track from Spotify
2. **Open web player** — Navigates to the track on Spotify's web player using your browser cookies
3. **Read/modify state** — Reads or toggles the like button's `aria-checked` attribute
4. **No API needed** — Works without registering a Spotify Developer App

### Exit Codes

- `0` — Success
- `1` — Error (Spotify not running, no track playing, cookie/browser issues, etc.)

See stderr for error details.
