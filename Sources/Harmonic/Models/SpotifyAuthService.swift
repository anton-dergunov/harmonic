import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

// Optional OAuth path for Spotify Web API (PKCE flow — no client secret required).
// Credentials from any pre-existing Spotify developer app work here, e.g. Spotica Menu's
// grandfathered app (client_id=c305b358e164433b9eed2b3671a3419a,
// redirect_uri=spoticamenu://oauth-callback/spotify).
// New apps since Feb 2026 cannot enable Web API scopes.
@MainActor
final class SpotifyAuthService: NSObject, ObservableObject {

    @AppStorage("spotify.oauth.enabled")     var oauthEnabled: Bool   = false
    @AppStorage("spotify.oauth.clientId")    var clientId:     String = ""
    @AppStorage("spotify.oauth.redirectURI") var redirectURI:  String = "harmonic://callback"

    let scopes = "user-library-read user-library-modify playlist-read-private playlist-modify-private playlist-modify-public"

    @Published var isConnected     = false
    @Published var isAuthenticating = false
    @Published var lastError:       String?

    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    override init() {
        super.init()
        isConnected = loadToken(key: "refreshToken") != nil
        if isConnected {
            Task { _ = await getValidToken() }
        }
    }

    // MARK: - Public API

    func getValidToken() async -> String? {
        if let t = cachedToken, tokenExpiry > Date().addingTimeInterval(60) { return t }
        return await refreshAccessToken()
    }

    func authorize() async {
        guard !clientId.isEmpty else { lastError = "Client ID is required"; return }
        guard let scheme = callbackScheme(for: redirectURI) else {
            lastError = "Could not parse scheme from redirect URI"
            return
        }
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let verifier = generateCodeVerifier()

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id",            value: clientId),
            .init(name: "response_type",         value: "code"),
            .init(name: "redirect_uri",          value: redirectURI),
            .init(name: "scope",                 value: scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge",        value: codeChallenge(for: verifier)),
        ]
        guard let authURL = comps.url else { lastError = "Could not build auth URL"; return }

        let callbackURL: URL? = await withCheckedContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { url, _ in
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let callback = callbackURL else { lastError = "Auth cancelled"; return }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            lastError = "No code in callback URL"
            return
        }
        await exchangeCode(code, verifier: verifier)
    }

    func disconnect() {
        cachedToken = nil
        tokenExpiry = .distantPast
        deleteToken(key: "accessToken")
        deleteToken(key: "refreshToken")
        isConnected = false
        lastError = nil
    }

    // MARK: - Token exchange / refresh (PKCE)

    private func exchangeCode(_ code: String, verifier: String) async {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode([
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectURI,
            "client_id":     clientId,
            "code_verifier": verifier,
        ])

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            lastError = "Network error during token exchange"
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lastError = "Could not parse token response"
            return
        }
        if let err = json["error"] as? String {
            let desc = json["error_description"] as? String ?? ""
            lastError = "Spotify error: \(err)\(desc.isEmpty ? "" : " — \(desc)")"
            return
        }
        guard let access  = json["access_token"]  as? String,
              let refresh = json["refresh_token"] as? String else {
            lastError = "Missing tokens in response (HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0))"
            return
        }
        storeTokens(access: access, refresh: refresh,
                    expiresIn: json["expires_in"] as? TimeInterval ?? 3600)
        isConnected = true
    }

    private func refreshAccessToken() async -> String? {
        guard let refresh = loadToken(key: "refreshToken"), !refresh.isEmpty,
              !clientId.isEmpty else {
            isConnected = false
            return nil
        }
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode([
            "grant_type":    "refresh_token",
            "refresh_token": refresh,
            "client_id":     clientId,
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            isConnected = false
            return nil
        }
        storeTokens(access: access,
                    refresh: json["refresh_token"] as? String ?? refresh,
                    expiresIn: json["expires_in"] as? TimeInterval ?? 3600)
        isConnected = true
        return access
    }

    private func storeTokens(access: String, refresh: String, expiresIn: TimeInterval) {
        cachedToken = access
        tokenExpiry = Date().addingTimeInterval(expiresIn)
        saveToken(value: access,  key: "accessToken")
        saveToken(value: refresh, key: "refreshToken")
    }

    // MARK: - Helpers

    private func callbackScheme(for uri: String) -> String? {
        guard let url = URL(string: uri), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return scheme
    }

    private func formEncode(_ params: [String: String]) -> Data {
        params.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private func generateCodeVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncoded()
    }

    private func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    // MARK: - Token persistence

    private func saveToken(value: String, key: String) {
        UserDefaults.standard.set(value, forKey: "harmonic.oauth.\(key)")
    }

    private func loadToken(key: String) -> String? {
        UserDefaults.standard.string(forKey: "harmonic.oauth.\(key)")
    }

    private func deleteToken(key: String) {
        UserDefaults.standard.removeObject(forKey: "harmonic.oauth.\(key)")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SpotifyAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Helpers

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
