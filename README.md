# spotify-controller

CLI tool for macOS that prints whether the song currently playing in the **Spotify desktop app** is in your library / liked.

## Requirements

- macOS with [Spotify](https://www.spotify.com/download/mac/) desktop playing a track
- A Chromium browser where you are signed in at [open.spotify.com](https://open.spotify.com/) (Chrome, Brave, or Edge)
- Python 3.10+

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

Grant **Automation** access for your terminal to **Spotify** and **Google Chrome** when macOS prompts you (System Settings → Privacy & Security → Automation).

Optional fast path: in Chrome, enable **Develop → Allow JavaScript from Apple Events** so an already-open track tab can be read without launching headless Chromium.

## Usage

```bash
python spotify_liked.py
```

Prints `yes` or `no` and exits.

## How it works

1. Reads the current track ID from the Spotify app via AppleScript.
2. Opens that track on the Spotify web player using your browser login cookies (no Spotify Developer API).
3. Reads the save/like button `aria-checked` state on the track page.

Errors are written to stderr; stdout is only `yes` or `no`.
