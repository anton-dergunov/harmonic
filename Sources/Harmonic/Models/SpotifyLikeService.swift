import Foundation

@MainActor
final class SpotifyLikeService {

    weak var authService: SpotifyAuthService?

    func fetchLikedStatus(trackId: String) async -> Bool? {
        guard !trackId.isEmpty else { return nil }
        guard let auth = authService, auth.oauthEnabled, auth.isConnected else { return nil }
        guard let token = await auth.getValidToken() else { return nil }
        return await containsTrack(trackId: trackId, token: token).value
    }

    /// Sets the liked state, reporting *why* it failed so the caller can tell a
    /// temporary outage (worth queueing) from a refusal (worth reverting).
    func setLike(trackId: String, wantLiked: Bool) async -> SpotifyAPIOutcome<Bool> {
        guard !trackId.isEmpty else {
            return .rejected(SpotifyRejection(status: 0, message: "No track"))
        }
        guard let auth = authService, auth.oauthEnabled, auth.isConnected else {
            return .rejected(SpotifyRejection(status: 0, message: "Not connected"))
        }
        guard let token = await auth.getValidToken() else {
            // A failed refresh that left us connected was a network problem, so the
            // action is still worth keeping; otherwise the authorization is gone.
            return auth.isConnected ? .transient
                                    : .rejected(SpotifyRejection(status: 401, message: "Not connected"))
        }

        // Verify current state before mutating to avoid redundant API calls.
        switch await containsTrack(trackId: trackId, token: token) {
        case .ok(let current) where current == wantLiked: return .ok(current)
        case .ok: break
        case .transient: return .transient
        case .rejected(let rejection): return .rejected(rejection)
        }

        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks")!)
        req.httpMethod = wantLiked ? "PUT" : "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": [trackId]])

        switch await SpotifyHTTP.send(req) {
        case .ok:                      return .ok(wantLiked)
        case .transient:               return .transient
        case .rejected(let rejection): return handle(rejection)
        }
    }

    // MARK: - Private

    private func containsTrack(trackId: String, token: String) async -> SpotifyAPIOutcome<Bool> {
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/tracks/contains?ids=\(trackId)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        switch await SpotifyHTTP.send(req) {
        case .ok(let (data, _)):
            guard let flags = try? JSONSerialization.jsonObject(with: data) as? [Bool],
                  let isLiked = flags.first else { return .transient }
            return .ok(isLiked)
        case .transient:
            return .transient
        case .rejected(let rejection):
            return handle(rejection)
        }
    }

    /// A 401 means the access token died early. Drop it and report the failure as
    /// temporary — the next attempt refreshes and usually succeeds.
    private func handle(_ rejection: SpotifyRejection) -> SpotifyAPIOutcome<Bool> {
        guard rejection.status == 401 else { return .rejected(rejection) }
        authService?.invalidateAccessToken()
        return .transient
    }
}
