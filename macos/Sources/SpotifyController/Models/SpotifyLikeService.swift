import CCommonCrypto
import Foundation
import Security

struct LikeResult {
    let isLiked: Bool
    let artworkURL: String?
}

// Handles like/unlike using the same two-phase approach as prototypes/spotify_liked.py:
//   1. Fast path  – inject JS into an open Chrome tab on the track's page.
//   2. Fallback   – call the Python script (which uses browser_cookie3 + playwright).
//
// The get_access_token Spotify endpoint returns 403 from non-browser clients, so a
// direct cookie→token→API chain does not work; only an actual browser (tab or headless)
// can authenticate correctly.
@MainActor
final class SpotifyLikeService {

    // MARK: - Public API

    /// Called when a new track starts playing.
    func fetchLikeAndArtwork(trackId: String) async -> LikeResult? {
        guard !trackId.isEmpty else {
            log("fetchLikeAndArtwork: trackId is empty, skipping")
            return nil
        }
        log("fetchLikeAndArtwork: trackId=\(trackId)")

        // 1. Chrome tab fast path (zero extra network traffic)
        if let r = await chromeFetchLike(trackId: trackId) {
            log("fetchLikeAndArtwork: chrome path succeeded, isLiked=\(r.isLiked)")
            return r
        }
        log("fetchLikeAndArtwork: chrome path failed, trying Python script")

        // 2. Python script fallback (same playwright approach as the prototype)
        if let liked = await pythonScript(action: "status") {
            log("fetchLikeAndArtwork: Python script returned isLiked=\(liked)")
            return LikeResult(isLiked: liked, artworkURL: nil)
        }
        log("fetchLikeAndArtwork: all paths failed")
        return nil
    }

    /// Called when the user taps the heart button.
    /// `wantLiked` is the UI's intended new state.
    func setLike(trackId: String, wantLiked: Bool) async -> Bool? {
        guard !trackId.isEmpty else {
            log("setLike: trackId empty, skipping")
            return nil
        }
        log("setLike: trackId=\(trackId) wantLiked=\(wantLiked)")

        // 1. Chrome tab fast path
        if let r = await chromeSetLike(trackId: trackId, wantLiked: wantLiked) {
            log("setLike: chrome path succeeded, actual=\(r)")
            return r
        }
        log("setLike: chrome path failed, trying Python script")

        // 2. Python script (handles reconciliation internally: only clicks if state differs)
        let action = wantLiked ? "like" : "unlike"
        if let result = await pythonScript(action: action) {
            log("setLike: Python script returned \(result)")
            return result
        }
        log("setLike: all paths failed")
        return nil
    }

    // MARK: - Chrome AppleScript fast path

    private func chromeFetchLike(trackId: String) async -> LikeResult? {
        log("chrome: trying tab injection for trackId=\(trackId)")
        guard let raw = await injectJSInChrome(trackId: trackId, js: readAndArtJS) else {
            log("chrome: no tab found or Chrome not running")
            return nil
        }
        log("chrome: raw result='\(raw)'")
        let parts = raw.components(separatedBy: "\t")
        guard parts.count >= 2, !parts[0].hasPrefix("ERROR:"), !parts[0].isEmpty else {
            log("chrome: parse failed, parts=\(parts)")
            return nil
        }
        guard let liked = parseLikedState(label: parts[0], checked: parts[1]) else {
            log("chrome: could not determine liked from label='\(parts[0])' checked='\(parts[1])'")
            return nil
        }
        let artURL = parts.count >= 3 && !parts[2].isEmpty ? parts[2] : nil
        return LikeResult(isLiked: liked, artworkURL: artURL)
    }

    private func chromeSetLike(trackId: String, wantLiked: Bool) async -> Bool? {
        guard let rawRead = await injectJSInChrome(trackId: trackId, js: readJS) else { return nil }
        log("chrome: read raw='\(rawRead)'")
        guard let current = parseLikedFromRaw(rawRead) else { return nil }

        if current == wantLiked {
            log("chrome: already in desired state \(current), no click needed")
            return current
        }

        if let rawClick = await injectJSInChrome(trackId: trackId, js: clickJS),
           let afterClick = parseLikedFromRaw(rawClick) {
            return afterClick
        }
        // Re-read if click result was ambiguous
        if let rawReread = await injectJSInChrome(trackId: trackId, js: readJS) {
            return parseLikedFromRaw(rawReread)
        }
        return nil
    }

    private func injectJSInChrome(trackId: String, js: String) async -> String? {
        let escaped = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        let script = """
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabUrl to URL of t
                    if tabUrl contains "open.spotify.com/track/\(trackId)" then
                        try
                            return execute javascript "\(escaped)" in t
                        on error errMsg
                            return "ERROR:" & errMsg
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        let result = await runOsascript(script)
        guard let r = result, !r.isEmpty else { return nil }
        return r
    }

    // MARK: - JS snippets (same selectors as the Python prototype)

    private let readAndArtJS = """
    (function(){
      var b=document.querySelector('[data-testid="action-bar"] [data-testid="add-button"]')
        ||document.querySelector('button[aria-label="Add to Liked Songs"]')
        ||document.querySelector('button[aria-label="Remove from Liked Songs"]');
      if(!b)return '';
      var og=document.querySelector('meta[property="og:image"]');
      return (b.getAttribute('aria-label')||'')+'\\t'+(b.getAttribute('aria-checked')||'')+'\\t'+(og?og.getAttribute('content'):'');
    })();
    """

    private let readJS = """
    (function(){
      var b=document.querySelector('[data-testid="action-bar"] [data-testid="add-button"]')
        ||document.querySelector('button[aria-label="Add to Liked Songs"]')
        ||document.querySelector('button[aria-label="Remove from Liked Songs"]');
      if(!b)return '';
      return (b.getAttribute('aria-label')||'')+'\\t'+(b.getAttribute('aria-checked')||'');
    })();
    """

    private let clickJS = """
    (function(){
      var b=document.querySelector('[data-testid="action-bar"] [data-testid="add-button"]')
        ||document.querySelector('button[aria-label="Add to Liked Songs"]')
        ||document.querySelector('button[aria-label="Remove from Liked Songs"]');
      if(!b)return '';
      b.click();
      return (b.getAttribute('aria-label')||'')+'\\t'+(b.getAttribute('aria-checked')||'');
    })();
    """

    // MARK: - Parsing

    private func parseLikedFromRaw(_ raw: String) -> Bool? {
        guard !raw.isEmpty, !raw.hasPrefix("ERROR:"), raw.contains("\t") else { return nil }
        let p = raw.components(separatedBy: "\t")
        guard !p[0].isEmpty else { return nil }
        return parseLikedState(label: p[0], checked: p.count > 1 ? p[1] : "")
    }

    private func parseLikedState(label: String, checked: String) -> Bool? {
        if label.contains("Remove from Liked Songs") || label.contains("Remove from Your Library") {
            return true
        }
        if label.contains("Add to Liked Songs") || label.contains("Save to Your Library") {
            return checked == "true"
        }
        if checked == "true"  { return true  }
        if checked == "false" { return false }
        return nil
    }

    // MARK: - Python script subprocess

    // The Python script lives at <repo_root>/prototypes/spotify_liked.py.
    // The binary is at <repo_root>/macos/.build/{debug,release}/SpotifyController,
    // so the repo root is 4 path components up from the binary.
    private func findPythonAndScript() -> (python: String, script: String)? {
        guard let execURL = Bundle.main.executableURL else {
            log("python: Bundle.main.executableURL is nil")
            return nil
        }
        log("python: binary at \(execURL.path)")

        // Walk up from the binary until we find prototypes/spotify_liked.py
        var candidate = execURL
        for _ in 0..<8 {
            candidate = candidate.deletingLastPathComponent()
            let scriptURL = candidate.appendingPathComponent("prototypes/spotify_liked.py")
            if FileManager.default.fileExists(atPath: scriptURL.path) {
                let venvPython = candidate.appendingPathComponent(".venv/bin/python3").path
                let python = FileManager.default.fileExists(atPath: venvPython)
                    ? venvPython
                    : "/usr/bin/python3"
                log("python: found script=\(scriptURL.path) python=\(python)")
                return (python, scriptURL.path)
            }
        }
        log("python: script not found (searched up to 8 levels from binary)")
        return nil
    }

    // Calls the Python script with the given action ("status", "like", "unlike").
    // Returns true=liked, false=unliked, nil=error.
    private func pythonScript(action: String) async -> Bool? {
        guard let (python, script) = findPythonAndScript() else { return nil }

        return await withCheckedContinuation { cont in
            Task.detached(priority: .utility) { [self] in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: python)
                proc.arguments = action == "status" ? [script] : [script, action]
                proc.currentDirectoryURL = URL(fileURLWithPath: script)
                    .deletingLastPathComponent()

                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError  = errPipe

                do {
                    try proc.run()
                } catch {
                    await MainActor.run { self.log("python: failed to launch: \(error)") }
                    cont.resume(returning: nil)
                    return
                }

                // 60 s timeout matches playwright's page.goto timeout in the Python script.
                // A second detached task terminates the process if it runs too long.
                let processRef = proc
                let timeoutTask = Task.detached {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if processRef.isRunning { processRef.terminate() }
                }

                proc.waitUntilExit()
                timeoutTask.cancel()

                if proc.terminationReason == .uncaughtSignal {
                    await MainActor.run { self.log("python: terminated (timed out after 60s)") }
                    cont.resume(returning: nil)
                    return
                }

                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                await MainActor.run {
                    self.log("python: stdout='\(out)' stderr='\(err.prefix(200))'")
                }

                let result: Bool? = out == "yes" ? true : out == "no" ? false : nil
                cont.resume(returning: result)
            }
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        NSLog("[SpotifyLike] %@", message)
    }
}

// MARK: - osascript helper (mirrors SpotifyBridge; scoped to this file only)

@discardableResult
private func runOsascript(_ script: String) async -> String? {
    await withCheckedContinuation { cont in
        Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError  = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: text.flatMap { $0.isEmpty ? nil : $0 })
            } catch {
                cont.resume(returning: nil)
            }
        }
    }
}
