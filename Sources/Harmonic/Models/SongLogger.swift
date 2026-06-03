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

    func logPlayPause(track: String, artist: String, trackId: String, action: String, positionS: Int) {
        write([
            "event": "play_pause",
            "ts": isoNow(),
            "track": track,
            "artist": artist,
            "track_id": trackId,
            "action": action,
            "position_s": positionS,
        ])
    }

    func logSkipBackward(track: String, artist: String, trackId: String, positionS: Int) {
        write([
            "event": "skip_backward",
            "ts": isoNow(),
            "track": track,
            "artist": artist,
            "track_id": trackId,
            "position_s": positionS,
        ])
    }

    func logSkipForward(track: String, artist: String, trackId: String, positionS: Int) {
        write([
            "event": "skip_forward",
            "ts": isoNow(),
            "track": track,
            "artist": artist,
            "track_id": trackId,
            "position_s": positionS,
        ])
    }

    func logSeek(track: String, artist: String, trackId: String, fromS: Int, toS: Int) {
        write([
            "event": "seek",
            "ts": isoNow(),
            "track": track,
            "artist": artist,
            "track_id": trackId,
            "from_position_s": fromS,
            "to_position_s": toS,
        ])
    }

    func logAddedToPlaylist(track: String, artist: String, trackId: String,
                            playlistId: String, playlistName: String) {
        write([
            "event": "added_to_playlist",
            "ts": isoNow(),
            "track": track,
            "artist": artist,
            "track_id": trackId,
            "playlist_id": playlistId,
            "playlist_name": playlistName,
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
