import AppKit
import Combine
import SwiftUI

@MainActor
final class PlaybackViewModel: ObservableObject {

    // MARK: - Track info

    @Published var artist = ""
    @Published var song = ""
    @Published var album = ""
    @Published var albumYear = 0
    @Published var duration: TimeInterval = 0

    // MARK: - Playback state

    @Published var isPlaying = false
    @Published var isLiked = false
    @Published var progress: TimeInterval = 0

    // MARK: - UI state

    @Published var coverImage: NSImage?
    @Published var showSettings = false
    @Published var isSpotifyRunning = false

    // MARK: - Private

    private let bridge = SpotifyBridge()
    private let likeService = SpotifyLikeService()

    private var currentTrackId = ""

    private var displayTimer: AnyCancellable?
    private var positionSyncTimer: AnyCancellable?

    private var reportedPosition: TimeInterval = 0
    private var reportedAt = Date()

    private var artworkRequestID = 0
    private var loadedArtworkURL = ""
    // Artwork URL obtained from the web (like-service fetch); used as step-2 fallback.
    private var webArtworkURL = ""
    // Guards against fetching like status twice for the same track.
    // The initial PlaybackStateChanged notification often carries an empty trackId;
    // the follow-up fetchAndDispatchState() fills it 0.3 s later with trackChanged=false,
    // so we must check here rather than only in the trackChanged branch.
    private var likeStatusFetched = false

    // MARK: - Init

    init() {
        wireBridge()
        isSpotifyRunning = bridge.isRunning()
        if isSpotifyRunning {
            bridge.queryCurrentState()
        }
        startDisplayTimer()
        startPositionSyncTimer()
    }

    // MARK: - Computed

    var albumSubtitle: String {
        albumYear > 0 ? "\(album) (\(albumYear))" : album
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, progress / duration))
    }

    // MARK: - Commands

    func togglePlayPause() {
        if isPlaying {
            bridge.pause()
            reportedPosition = progress
            isPlaying = false
        } else {
            bridge.play()
            reportedAt = Date()
            isPlaying = true
        }
    }

    func skipBackward() { bridge.previousTrack() }
    func skipForward()  { bridge.nextTrack() }

    func seek(fraction: Double) {
        let target = duration * min(1, max(0, fraction))
        progress         = target
        reportedPosition = target
        reportedAt       = Date()
        bridge.seek(to: target)
    }

    func toggleLike() {
        guard !currentTrackId.isEmpty else { return }
        // Determine the intended new state from the UI's current display.
        let wantLiked = !isLiked
        // Optimistically update UI immediately for responsiveness.
        isLiked = wantLiked

        let trackId = currentTrackId
        Task { [weak self] in
            guard let self else { return }
            if let actual = await likeService.setLike(trackId: trackId, wantLiked: wantLiked) {
                // Reconcile: if actual state differs (e.g. was already liked), sync UI.
                self.isLiked = actual
            } else {
                // Request failed — revert optimistic update.
                self.isLiked = !wantLiked
            }
        }
    }

    func launchSpotify() { bridge.launchSpotify() }

    // MARK: - Private

    private func wireBridge() {
        bridge.onRunningChanged = { [weak self] running in
            self?.isSpotifyRunning = running
            if !running { self?.resetToIdle() }
        }
        bridge.onTrackChanged = { [weak self] info in
            self?.applyTrackInfo(info)
        }
        bridge.onStateChanged = { [weak self] state in
            self?.applyPlayerState(state)
        }
    }

    private func applyTrackInfo(_ info: SpotifyTrackInfo) {
        let trackChanged = info.name != song || info.artist != artist

        song   = info.name
        artist = info.artist
        album  = info.album
        if info.albumYear > 0 { albumYear = info.albumYear }
        if info.duration  > 0 { duration  = info.duration  }

        if trackChanged {
            currentTrackId   = info.trackId
            isLiked          = false
            likeStatusFetched = false
            webArtworkURL    = ""
            loadedArtworkURL = info.artworkURL
            coverImage       = nil
            startArtworkFetch(cdnURL: info.artworkURL, artist: info.artist, track: info.name)
        } else {
            // Same track — update trackId if we just got it for the first time.
            if !info.trackId.isEmpty && currentTrackId.isEmpty {
                currentTrackId = info.trackId
            }

            let urlChanged = !info.artworkURL.isEmpty && info.artworkURL != loadedArtworkURL
            if urlChanged {
                loadedArtworkURL = info.artworkURL
                startArtworkFetch(cdnURL: info.artworkURL, artist: info.artist, track: info.name)
            }
        }

        // Fetch like status whenever we have a non-empty trackId and haven't fetched yet
        // for this track. Covers both the trackChanged path and the delayed-trackId path.
        if !currentTrackId.isEmpty && !likeStatusFetched {
            likeStatusFetched = true
            fetchLikeStatus(trackId: currentTrackId)
        }
    }

    // Fetch like status (and bonus web artwork URL) for the newly-playing track.
    private func fetchLikeStatus(trackId: String) {
        guard !trackId.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let result = await likeService.fetchLikeAndArtwork(trackId: trackId) else { return }
            // Make sure the track hasn't changed while we were fetching.
            guard self.currentTrackId == trackId else { return }
            self.isLiked = result.isLiked
            // Store the web artwork URL for use as a fallback in artwork fetch.
            if let url = result.artworkURL, !url.isEmpty {
                self.webArtworkURL = url
                // If we still don't have a cover image, try this URL now.
                if self.coverImage == nil {
                    self.startArtworkFetch(
                        cdnURL: self.loadedArtworkURL.isEmpty ? url : self.loadedArtworkURL,
                        webFallbackURL: url,
                        artist: self.artist,
                        track: self.song)
                }
            }
        }
    }

    private func startArtworkFetch(cdnURL: String, artist: String, track: String) {
        startArtworkFetch(cdnURL: cdnURL, webFallbackURL: webArtworkURL, artist: artist, track: track)
    }

    private func startArtworkFetch(cdnURL: String, webFallbackURL: String, artist: String, track: String) {
        artworkRequestID += 1
        let id = artworkRequestID

        Task { [weak self] in
            guard let self else { return }

            var data: Data?

            // 1. Spotify CDN URL (from AppleScript `artwork url of current track`).
            if !cdnURL.isEmpty {
                data = await bridge.downloadArtwork(from: cdnURL)
            }

            // 2. Web fallback URL obtained alongside the like-status fetch.
            if data == nil, !webFallbackURL.isEmpty, webFallbackURL != cdnURL {
                data = await bridge.downloadArtwork(from: webFallbackURL)
            }

            // 3. iTunes Search API — works for virtually all mainstream music.
            if data == nil {
                data = await bridge.searchITunesArtwork(artist: artist, track: track)
            }

            guard self.artworkRequestID == id else { return }
            self.coverImage = data.flatMap { NSImage(data: $0) }
        }
    }

    private func applyPlayerState(_ state: SpotifyPlayerState) {
        switch state {
        case .playing(let position):
            isPlaying        = true
            reportedPosition = position
            reportedAt       = Date()
        case .paused(let position):
            isPlaying        = false
            progress         = position
            reportedPosition = position
        case .stopped:
            isPlaying        = false
            progress         = 0
            reportedPosition = 0
        }
    }

    private func resetToIdle() {
        song             = ""
        artist           = ""
        album            = ""
        albumYear        = 0
        duration         = 0
        progress         = 0
        reportedPosition = 0
        isPlaying        = false
        isLiked           = false
        likeStatusFetched = false
        coverImage        = nil
        loadedArtworkURL  = ""
        webArtworkURL     = ""
        currentTrackId    = ""
    }

    private func startDisplayTimer() {
        displayTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, isPlaying, duration > 0 else { return }
                let elapsed = Date().timeIntervalSince(reportedAt)
                progress = min(duration, reportedPosition + elapsed)
            }
    }

    private func startPositionSyncTimer() {
        positionSyncTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, isSpotifyRunning, isPlaying else { return }
                Task { [weak self] in
                    guard let self else { return }
                    if let pos = await bridge.queryPosition() {
                        reportedPosition = pos
                        reportedAt       = Date()
                    }
                }
            }
    }
}
