import Foundation

struct SpotifyCredentials: Codable {
    var accessToken:  String
    var refreshToken: String
    var expiresAt:    Date

    // A minute of headroom so a token doesn't expire mid-request.
    var isAccessTokenUsable: Bool {
        !accessToken.isEmpty && expiresAt > Date().addingTimeInterval(60)
    }
}

// Persists the OAuth tokens to a file instead of UserDefaults.
//
// Spotify's PKCE refresh rotates the refresh token and invalidates the previous
// one, so the new value must reach disk immediately — a UserDefaults write sits
// in cfprefsd and can be lost on power failure, which costs the user a full
// re-authorization. Keychain is not an option: the app is ad-hoc signed, so its
// signature changes every build and macOS would prompt on every launch.
struct SpotifyCredentialStore {

    private static let fileName = "credentials.json"

    // Pre-file storage; read once so existing installs keep their connection.
    private static let legacyAccessKey  = "harmonic.oauth.accessToken"
    private static let legacyRefreshKey = "harmonic.oauth.refreshToken"

    func load() -> SpotifyCredentials? {
        if let data = AppSupport.read(Self.fileName),
           let creds = try? AppSupport.decoder.decode(SpotifyCredentials.self, from: data) {
            return creds
        }
        return migrateFromUserDefaults()
    }

    func save(_ credentials: SpotifyCredentials) {
        guard let data = try? AppSupport.encoder.encode(credentials) else { return }
        AppSupport.write(data, to: Self.fileName)
    }

    func clear() {
        AppSupport.remove(Self.fileName)
    }

    // MARK: - Private

    private func migrateFromUserDefaults() -> SpotifyCredentials? {
        let defaults = UserDefaults.standard
        guard let refresh = defaults.string(forKey: Self.legacyRefreshKey), !refresh.isEmpty else {
            return nil
        }
        // The old storage never recorded an expiry, so assume the access token is
        // stale and let the first refresh replace it.
        let credentials = SpotifyCredentials(
            accessToken:  defaults.string(forKey: Self.legacyAccessKey) ?? "",
            refreshToken: refresh,
            expiresAt:    .distantPast
        )
        save(credentials)
        defaults.removeObject(forKey: Self.legacyAccessKey)
        defaults.removeObject(forKey: Self.legacyRefreshKey)
        return credentials
    }
}
