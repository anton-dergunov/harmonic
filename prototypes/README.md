# spotify_like.py — Setup & Usage

Tracks the currently playing Spotify song and lets you toggle like/unlike —
**no developer account, no API keys, no Premium, no cookies required.**

---

## How it works

| Feature | Method |
|---------|--------|
| Track change detection | `NSDistributedNotificationCenter` — instant, zero polling |
| Like state (read) | macOS Accessibility API — reads the heart button's label from Spotify's UI |
| Like toggle (write) | macOS Accessibility API — programmatically clicks the heart button |

The Spotify desktop app (Electron) exposes its UI through the macOS
Accessibility tree. The heart/like button has an `AXDescription` of either
`"Add to Liked Songs"` (not liked) or `"Remove from Liked Songs"` (liked).
The script reads this to determine state, and clicks it to toggle.

**This works even when Spotify is minimized** — the Accessibility API queries
the app's process, not its visual render.

---

## Install

```bash
pip install pyobjc-framework-Cocoa
```

---

## One-time macOS permission (required)

macOS requires you to explicitly grant "Accessibility" access to whatever app
runs the script (your terminal).

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the **+** button
3. Add your terminal: `Terminal.app`, `iTerm.app`, `Warp.app`, etc.
4. Toggle it **ON**

You only do this once. The script will tell you if it's missing.

---

## Run

```bash
python3 spotify_like.py
```

Start playing something in Spotify first.

---

## Controls

| Key | Action |
|-----|--------|
| `L` | Toggle like / unlike current track |
| `Q` | Quit |

---

## What you'll see

```
═══════════════════════════════════════════════════════
  Spotify Like Tracker
  (uses macOS Accessibility — no API keys needed)
═══════════════════════════════════════════════════════

  ✅ Accessibility permission OK
  ✅ Ready

  Listening for Spotify track changes...

  ▶  Bohemian Rhapsody  —  Queen

───────────────────────────────────────────────────────
  ❤️  Bohemian Rhapsody
       Queen  ·  A Night at the Opera
───────────────────────────────────────────────────────
  [L] toggle like   [Q] quit

  ❤️  Liked: Mr. Brightside     ← after pressing L
```

---

## Limitations

**If the like button isn't found:**
- Spotify must be open (not just in the Dock/menu bar — the window must exist,
  even if minimized or behind other windows)
- The button is only present when a track is actively loaded in the Now Playing bar
- If Spotify ever significantly redesigns its UI, the button's accessibility label
  may change — but this is rare and easy to fix (just update the string in the script)

**Accessibility permission:**
- Your terminal needs to be in System Settings → Accessibility
- If you switch terminals (e.g. from Terminal.app to iTerm2), add the new one too

---

## Troubleshooting

**"Could not find the like button"**
1. Is Spotify open with a song loaded in the Now Playing bar?
2. Is your terminal listed in System Settings → Privacy → Accessibility?
3. Try clicking on the Spotify window once to make sure it's fully initialized,
   then run the script again.

**Script crashes on import**
```bash
pip install pyobjc-framework-Cocoa
```

**Like state shows ❓ after song change**
Normal — it takes ~0.5s for the Accessibility query to run after a track changes.
If it stays ❓, try pressing L and it will query fresh before toggling.
