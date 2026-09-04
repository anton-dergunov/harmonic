import Foundation

// A like/unlike the user made while Spotify was unreachable.
struct PendingLike: Codable {
    let trackId:   String
    let wantLiked: Bool
    let track:     String
    let artist:    String
    let queuedAt:  Date
}

// Holds like/unlike actions that couldn't be sent, so a tap made on a train or
// right after a reboot isn't silently lost. Replayed once a token is available.
@MainActor
final class PendingLikeQueue {

    private static let fileName   = "pending-likes.json"
    private static let maxEntries = 200
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private var entries: [PendingLike]
    private var isFlushing = false

    init() {
        entries = Self.load()
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Records an intent, superseding any earlier one for the same track — liking
    /// then unliking the same song collapses to the final state.
    func enqueue(_ entry: PendingLike) {
        entries.removeAll { $0.trackId == entry.trackId }
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        persist()
    }

    /// Replays queued actions oldest first. Stops at the first transient failure so
    /// the rest survive for the next attempt; drops anything Spotify refuses outright.
    func flush(using send: (PendingLike) async -> SpotifyAPIOutcome<Bool>) async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while let entry = entries.first {
            if case .transient = await send(entry) { return }
            // Match on identity, not position: the user may have re-toggled this
            // very track while the request was in flight, in which case the newer
            // entry has to stay.
            entries.removeAll { $0.trackId == entry.trackId && $0.queuedAt == entry.queuedAt }
            persist()
            guard !entries.isEmpty else { break }
            // Spacing keeps a long backlog from tripping Spotify's rate limiter.
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: - Persistence

    private static func load() -> [PendingLike] {
        guard let data = AppSupport.read(fileName),
              let list = try? AppSupport.decoder.decode([PendingLike].self, from: data) else {
            return []
        }
        // Replaying a week-old like would be more confusing than helpful.
        let cutoff = Date().addingTimeInterval(-maxAge)
        return list.filter { $0.queuedAt > cutoff }
    }

    private func persist() {
        guard !entries.isEmpty else {
            AppSupport.remove(Self.fileName)
            return
        }
        guard let data = try? AppSupport.encoder.encode(entries) else { return }
        AppSupport.write(data, to: Self.fileName)
    }
}
