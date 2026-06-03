import Foundation

// A user's playlist as shown in the add-to-playlist UI.
struct SpotifyPlaylist: Identifiable, Hashable, Codable {
    let id: String        // playlist id
    let name: String
    let isOwn: Bool       // owner is the current user (own/collaborative are writable)
}

@MainActor
final class SpotifyPlaylistService {

    weak var authService: SpotifyAuthService?

    // Cached once per session to decide which playlists are writable.
    private var currentUserId: String?

    /// Fetch the user's playlists. Returns nil on failure (auth/network).
    /// Most users fit in one page; we follow `next` defensively up to a few pages.
    func fetchPlaylists() async -> [SpotifyPlaylist]? {
        guard let auth = authService, auth.oauthEnabled, auth.isConnected else { return nil }
        guard let token = await auth.getValidToken() else { return nil }
        guard let userId = await fetchCurrentUserId(token: token) else { return nil }

        var result: [SpotifyPlaylist] = []
        var url: URL? = URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")
        var pagesRemaining = 5  // safety bound: up to 250 playlists

        while let pageURL = url, pagesRemaining > 0 {
            pagesRemaining -= 1
            var req = URLRequest(url: pageURL)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                return result.isEmpty ? nil : result
            }

            for item in items {
                guard let id = item["id"] as? String,
                      let name = item["name"] as? String else { continue }
                let ownerId = (item["owner"] as? [String: Any])?["id"] as? String
                let collaborative = item["collaborative"] as? Bool ?? false
                let isOwn = (ownerId == userId) || collaborative
                result.append(SpotifyPlaylist(id: id, name: name, isOwn: isOwn))
            }

            url = (json["next"] as? String).flatMap(URL.init(string:))
        }
        return result
    }

    /// Add a track to a playlist. Returns true on success (HTTP 2xx, typically 201).
    func addTrack(playlistId: String, trackId: String) async -> Bool {
        guard !playlistId.isEmpty, !trackId.isEmpty else { return false }
        guard let auth = authService, auth.oauthEnabled, auth.isConnected else { return false }
        guard let token = await auth.getValidToken() else { return false }

        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["uris": ["spotify:track:\(trackId)"]]
        )
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              (200...299).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { return false }
        return true
    }

    // MARK: - Private

    private func fetchCurrentUserId(token: String) async -> String? {
        if let cached = currentUserId { return cached }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else { return nil }
        currentUserId = id
        return id
    }
}
