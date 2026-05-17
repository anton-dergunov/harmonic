#!/usr/bin/env python3
"""
Print whether the track currently playing in the Spotify desktop app is liked.

Uses the logged-in Spotify web session from Chrome (no Spotify Developer API).
Reads the save/like control on the track page (aria-checked on the action bar).
"""

from __future__ import annotations

import subprocess
import sys
from typing import Iterable

import browser_cookie3
from playwright.sync_api import TimeoutError as PlaywrightTimeout
from playwright.sync_api import sync_playwright

LIKE_BUTTON_SELECTOR = (
    '[data-testid="action-bar"] [data-testid="add-button"], '
    'button[aria-label="Add to Liked Songs"], '
    'button[aria-label="Remove from Liked Songs"]'
)

BROWSER_COOKIE_LOADERS: tuple[tuple[str, callable], ...] = (
    ("Chrome", browser_cookie3.chrome),
    ("Brave", browser_cookie3.brave),
    ("Edge", browser_cookie3.edge),
)


def _fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _spotify_track_id() -> str:
    try:
        state = subprocess.run(
            ["osascript", "-e", 'tell application "Spotify" to player state as string'],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except subprocess.CalledProcessError:
        _fail("Spotify is not running or not reachable via AppleScript.")
    if state != "playing":
        _fail(f"Spotify is not playing (state: {state!r}).")

    track_uri = subprocess.run(
        ["osascript", "-e", 'tell application "Spotify" to get id of current track'],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not track_uri or ":" not in track_uri:
        _fail("Could not read the current track from Spotify.")
    return track_uri.rsplit(":", 1)[-1]


def _load_spotify_cookies() -> list[dict]:
    last_error: Exception | None = None
    for browser_name, loader in BROWSER_COOKIE_LOADERS:
        try:
            jar = loader(domain_name=".spotify.com")
        except Exception as exc:  # noqa: BLE001 - try next browser
            last_error = exc
            continue

        cookies: list[dict] = []
        for cookie in jar:
            cookies.append(
                {
                    "name": cookie.name,
                    "value": cookie.value,
                    "domain": cookie.domain,
                    "path": cookie.path or "/",
                    "expires": int(cookie.expires) if cookie.expires else -1,
                    "httpOnly": False,
                    "secure": bool(cookie.secure),
                    "sameSite": "Lax",
                }
            )
        if any(c["name"] == "sp_dc" for c in cookies):
            return cookies

    if last_error:
        _fail(
            "Could not read Spotify login cookies from Chrome/Brave/Edge. "
            f"Last error: {last_error}"
        )
    _fail(
        "No Spotify login found in Chrome/Brave/Edge. "
        "Open https://open.spotify.com/ in your browser and sign in once."
    )


def _liked_from_control(label: str | None, checked: str | None) -> bool:
    label = label or ""
    if "Remove from Liked Songs" in label or "Remove from Your Library" in label:
        return True
    if "Add to Liked Songs" in label or "Save to Your Library" in label:
        return checked == "true"
    if checked in ("true", "false"):
        return checked == "true"
    _fail(f"Unexpected like button: label={label!r} aria-checked={checked!r}")


def _read_liked_from_page(page, track_id: str) -> bool:
    page.goto(
        f"https://open.spotify.com/track/{track_id}",
        wait_until="domcontentloaded",
        timeout=60_000,
    )
    button = page.locator(LIKE_BUTTON_SELECTOR).first
    button.wait_for(state="attached", timeout=30_000)
    return _liked_from_control(
        button.get_attribute("aria-label"),
        button.get_attribute("aria-checked"),
    )


def _try_chrome_applescript(track_id: str) -> bool | None:
    """Fast path when Chrome already shows this track and allows JS from Apple Events."""
    js = (
        "(function() {"
        "  const btn = document.querySelector('[data-testid=\"action-bar\"] [data-testid=\"add-button\"]')"
        "    || document.querySelector('button[aria-label=\"Add to Liked Songs\"]')"
        "    || document.querySelector('button[aria-label=\"Remove from Liked Songs\"]');"
        "  if (!btn) return '';"
        "  return (btn.getAttribute('aria-label') || '') + '\\t' + (btn.getAttribute('aria-checked') || '');"
        "})();"
    )
    script = f'''
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabUrl to URL of t
                    if tabUrl contains "open.spotify.com/track/{track_id}" then
                        try
                            set jsResult to execute javascript {js!r} in t
                            return jsResult
                        on error errMsg number errNum
                            return "ERROR:" & errMsg
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return ""
    '''
    try:
        raw = subprocess.run(
            ["osascript", "-e", script],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout.strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None

    if not raw or raw.startswith("ERROR:"):
        return None
    if "\t" not in raw:
        return None
    label, checked = raw.split("\t", 1)
    if not label:
        return None
    return _liked_from_control(label, checked or None)


def _read_liked_playwright(track_id: str, cookies: Iterable[dict]) -> bool:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context()
        context.add_cookies(list(cookies))

        page = context.new_page()

        def block_heavy(route) -> None:
            if route.request.resource_type in ("image", "media", "font"):
                route.abort()
            else:
                route.continue_()

        page.route("**/*", block_heavy)

        try:
            return _read_liked_from_page(page, track_id)
        except PlaywrightTimeout as exc:
            _fail(f"Timed out reading like status from Spotify web UI: {exc}")
        finally:
            browser.close()


def main() -> None:
    track_id = _spotify_track_id()
    liked = _try_chrome_applescript(track_id)
    if liked is None:
        liked = _read_liked_playwright(track_id, _load_spotify_cookies())
    print("yes" if liked else "no")


if __name__ == "__main__":
    main()
