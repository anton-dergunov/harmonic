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

    /// True while we hold credentials Spotify has not rejected. Deliberately stays
    /// true through network outages: a refresh that fails because the machine is
    /// offline is not a revoked authorization, and treating it as one is what used
    /// to force a re-connect after every reboot.
    @Published private(set) var isConnected = false

    /// A refresh failed for a reason that looks temporary and a retry is queued.
    @Published private(set) var isRefreshPending = false

    @Published var isAuthenticating = false
    @Published var lastError: String?

    /// Fired after a refresh succeeds, so work parked during the outage can run.
    var onReconnected: (() -> Void)?

    private let store = SpotifyCredentialStore()
    private var credentials: SpotifyCredentials?

    // One in-flight refresh at a time. Several callers (like status, playlists)
    // routinely ask for a token at the same moment; without this they'd each
    // spend a request and race to rotate the refresh token.
    private var refreshTask: Task<String?, Never>?

    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    // Bounded backoff: a long outage costs a handful of requests per hour, not a flood.
    private static let backoff: [TimeInterval] = [2, 5, 15, 60, 300, 900]

    private var wakeObserver: NSObjectProtocol?

    // waitsForConnectivity keeps a refresh issued a moment too early — login items
    // start before Wi-Fi is up — queued instead of failing outright.
    private static let tokenSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!

    override init() {
        super.init()
        credentials = store.load()
        isConnected = credentials != nil
        observeRecoveryTriggers()
        // No network call when the stored access token is still good — most
        // relaunches then need no connectivity at all.
        if isConnected, credentials?.isAccessTokenUsable != true {
            scheduleRetry(after: 0)
        }
    }

    // MARK: - Public API

    func getValidToken() async -> String? {
        if let credentials, credentials.isAccessTokenUsable { return credentials.accessToken }
        return await coalescedRefresh()
    }

    /// Retries outside the on-demand path — used by the recovery hooks and by the
    /// Settings panel, so opening it never shows a stale "not connected" state.
    func refreshNow() {
        guard isConnected, !clientId.isEmpty else { return }
        guard credentials?.isAccessTokenUsable != true else { return }
        scheduleRetry(after: 0)
    }

    /// A 401 from the Web API means the access token died before its stated expiry
    /// (revoked scope, server-side invalidation). Drop it so the next call refreshes
    /// rather than retrying with a token we know is dead.
    func invalidateAccessToken() {
        guard var credentials else { return }
        credentials.expiresAt = .distantPast
        self.credentials = credentials
        store.save(credentials)
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
        credentials = nil
        store.clear()
        cancelPendingWork()
        isConnected = false
        isRefreshPending = false
        retryAttempt = 0
        lastError = nil
    }

    // MARK: - Token exchange / refresh (PKCE)

    private func exchangeCode(_ code: String, verifier: String) async {
        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode([
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectURI,
            "client_id":     clientId,
            "code_verifier": verifier,
        ])

        switch await SpotifyHTTP.send(req, session: Self.tokenSession) {
        case .ok(let (data, response)):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                lastError = "Could not parse token response"
                return
            }
            guard let access  = json["access_token"]  as? String,
                  let refresh = json["refresh_token"] as? String else {
                lastError = "Missing tokens in response (HTTP \(response.statusCode))"
                return
            }
            storeTokens(access: access, refresh: refresh,
                        expiresIn: json["expires_in"] as? TimeInterval ?? 3600)
            markConnected()
        case .transient:
            lastError = "Network error during token exchange"
        case .rejected(let rejection):
            lastError = rejection.message.map { "Spotify error: \($0)" }
                ?? "Token exchange failed (HTTP \(rejection.status))"
        }
    }

    private func coalescedRefresh() async -> String? {
        if let refreshTask { return await refreshTask.value }
        let task = Task { [weak self] () -> String? in
            await self?.performRefresh() ?? nil
        }
        refreshTask = task
        let token = await task.value
        refreshTask = nil
        return token
    }

    private func performRefresh() async -> String? {
        guard let refresh = credentials?.refreshToken, !refresh.isEmpty, !clientId.isEmpty else {
            markRejected("Spotify authorization is missing — please connect again.")
            return nil
        }

        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode([
            "grant_type":    "refresh_token",
            "refresh_token": refresh,
            "client_id":     clientId,
        ])

        switch await SpotifyHTTP.send(req, session: Self.tokenSession) {
        case .ok(let (data, _)):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String else {
                // A 200 we can't parse is not Spotify answering — a captive portal
                // or proxy is in the way. Worth retrying, not worth disconnecting.
                markTransient()
                return nil
            }
            // Spotify rotates the refresh token on most refreshes and invalidates
            // the old one, so whatever comes back has to be kept.
            storeTokens(access: access,
                        refresh: json["refresh_token"] as? String ?? refresh,
                        expiresIn: json["expires_in"] as? TimeInterval ?? 3600)
            markConnected()
            return access

        case .transient:
            markTransient()
            return nil

        case .rejected(let rejection):
            // Only a genuine OAuth error body proves the credentials are dead. An
            // opaque 4xx is far more likely to be something between us and Spotify.
            guard let message = rejection.message else {
                markTransient()
                return nil
            }
            markRejected("Spotify rejected the saved authorization (\(message)). Please connect again.")
            return nil
        }
    }

    private func storeTokens(access: String, refresh: String, expiresIn: TimeInterval) {
        let credentials = SpotifyCredentials(
            accessToken:  access,
            refreshToken: refresh,
            expiresAt:    Date().addingTimeInterval(expiresIn)
        )
        self.credentials = credentials
        // Atomic write: the rotated refresh token is on disk before this returns.
        store.save(credentials)
    }

    // MARK: - Connection state

    private func markConnected() {
        isConnected = true
        isRefreshPending = false
        lastError = nil
        retryAttempt = 0
        retryTask?.cancel()
        retryTask = nil
        onReconnected?()
    }

    private func markTransient() {
        isRefreshPending = true
        scheduleRetry(after: Self.backoff[min(retryAttempt, Self.backoff.count - 1)])
        retryAttempt += 1
    }

    private func markRejected(_ message: String) {
        credentials = nil
        store.clear()
        cancelPendingWork()
        isConnected = false
        isRefreshPending = false
        retryAttempt = 0
        lastError = message
    }

    private func scheduleRetry(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            guard let self, self.isConnected else { return }
            _ = await self.coalescedRefresh()
        }
    }

    private func cancelPendingWork() {
        retryTask?.cancel()
        retryTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Recovery triggers

    private func observeRecoveryTriggers() {
        // The primary post-reboot fix: retry the instant the interface comes up.
        NetworkMonitor.shared.onCameOnline { [weak self] in
            self?.refreshNow()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
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
