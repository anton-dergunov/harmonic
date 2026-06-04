import Foundation

@MainActor
final class RecentPlaylistSettings: ObservableObject {
    static let shared = RecentPlaylistSettings()

    @Published var recentPlaylistId: String? {
        didSet { UserDefaults.standard.set(recentPlaylistId, forKey: "harmonic.recentPlaylist.id") }
    }

    @Published var likeWhenAdding: Bool {
        didSet { UserDefaults.standard.set(likeWhenAdding, forKey: "harmonic.playlist.likeWhenAdding") }
    }

    private init() {
        recentPlaylistId = UserDefaults.standard.string(forKey: "harmonic.recentPlaylist.id")
        likeWhenAdding   = UserDefaults.standard.bool(forKey: "harmonic.playlist.likeWhenAdding")
    }
}
