import Foundation

@MainActor
final class SongLogger {

    func logSongChanged(track: String, artist: String, album: String, trackId: String, durationS: Int, liked: Bool?) {
        var dict: [String: Any] = [
            "event": "song_changed",
            "ts": isoNow(),
            "track": track,
            "artist": artist,
            "album": album,
            "track_id": trackId,
            "duration_s": durationS,
        ]
        if let liked { dict["liked"] = liked }
        write(dict)
    }

    func logLikeToggled(track: String, artist: String, trackId: String, action: String) {
        write([
            "event": "like_toggled",
            "ts": isoNow(),
            "track": track,
            "artist": artist,
            "track_id": trackId,
            "action": action,
        ])
    }

    // MARK: - Private

    private func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func write(_ dict: [String: Any]) {
        let path = LoggingSettings.shared.logFilePath
        guard !path.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let line = String(data: data, encoding: .utf8) else { return }
        let text = line + "\n"
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let d = text.data(using: .utf8) { handle.write(d) }
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
