import Foundation

// Why Spotify said no, when it bothered to say.
struct SpotifyRejection {
    let status: Int
    // Server-supplied reason. Nil means the response carried no recognisable
    // Spotify error body — which usually means something other than Spotify
    // answered (captive portal, corporate proxy).
    let message: String?
}

// Separates "couldn't reach Spotify right now" from "Spotify refused".
//
// The distinction matters everywhere: a transient failure must never be shown as
// a revoked authorization, and must never silently discard what the user asked
// for.
enum SpotifyAPIOutcome<Value> {
    case ok(Value)
    case transient                    // offline, timeout, 408, 429, 5xx — retry later
    case rejected(SpotifyRejection)   // the request itself is not going to succeed

    var value: Value? {
        if case .ok(let v) = self { return v }
        return nil
    }
}

enum SpotifyHTTP {

    /// Sends a request and classifies the result. Transport errors and the status
    /// codes worth retrying become `.transient`; everything else `.rejected`.
    static func send(
        _ request: URLRequest,
        session: URLSession = .shared
    ) async -> SpotifyAPIOutcome<(Data, HTTPURLResponse)> {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .transient }
            if (200...299).contains(http.statusCode) { return .ok((data, http)) }
            if http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500 {
                return .transient
            }
            return .rejected(SpotifyRejection(status: http.statusCode, message: errorMessage(in: data)))
        } catch {
            return .transient
        }
    }

    /// Reads the two error shapes Spotify uses: `{"error": "...", "error_description": "..."}`
    /// from the accounts endpoints and `{"error": {"message": "..."}}` from the Web API.
    static func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? String {
            let detail = json["error_description"] as? String ?? ""
            return detail.isEmpty ? error : "\(error) — \(detail)"
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return nil
    }
}
