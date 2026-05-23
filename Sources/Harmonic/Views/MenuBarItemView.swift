import SwiftUI

struct MenuBarItemView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    @EnvironmentObject private var settings: MenuBarSettings
    let onOpenWindow: () -> Void

    @GestureState private var prevPressed      = false
    @GestureState private var playPausePressed = false
    @GestureState private var nextTrackPressed = false
    @GestureState private var likePressed      = false

    var body: some View {
        if playback.isSpotifyRunning {
            ZStack {
                if settings.showAlbumArtBackground {
                    albumArtBackground
                }
                trackInfoView
            }
        } else {
            notRunningView
        }
    }

    // MARK: - Spotify not running

    private var notRunningView: some View {
        Image(systemName: "speaker.zzz.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: .labelColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { playback.launchSpotify() }
            .accessibilityLabel("Spotify not running — click to launch")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Album art background

    private var albumArtBackground: some View {
        Group {
            if let img = playback.coverImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .saturation(settings.albumArtBgStyle.saturation)
                    .opacity(settings.albumArtBgOpacity)
            }
        }
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Element row

    private var trackInfoView: some View {
        let oauthAvailable = playback.isLikeAvailable
        return HStack(spacing: 0) {
            ForEach(settings.elementOrder) { element in
                switch element {
                case .albumArtThumb:
                    if settings.showAlbumArtThumb   { albumArtThumbColumn }
                case .trackInfo:
                    if settings.showTrackInfo        { trackInfoColumn }
                case .previousTrack:
                    if settings.showPreviousTrack    { previousTrackColumn }
                case .playPause:
                    if settings.showPlayPause        { playPauseColumn }
                case .nextTrack:
                    if settings.showNextTrack        { nextTrackColumn }
                case .like:
                    if settings.showLikeButton       { likeColumn(oauthAvailable: oauthAvailable) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Template rendering

    private func render(_ template: String) -> String {
        var s = template
        s = s.replacingOccurrences(of: "{artist}", with: playback.artist.isEmpty ? "Spotify"     : playback.artist)
        s = s.replacingOccurrences(of: "{song}",   with: playback.song.isEmpty   ? "Not playing" : playback.song)
        s = s.replacingOccurrences(of: "{album}",  with: playback.albumSubtitle)
        s = s.replacingOccurrences(of: "{year}",   with: playback.albumYear > 0  ? "\(playback.albumYear)" : "")
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? " " : trimmed
    }

    // MARK: - Element columns

    private var albumArtThumbColumn: some View {
        Group {
            if let img = playback.coverImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .saturation(settings.albumArtThumbStyle.saturation)
                    .frame(width: settings.albumArtThumbSize, height: settings.albumArtThumbSize)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: settings.albumArtThumbSize * 0.55))
                    .foregroundStyle(settings.effectiveForeground.opacity(0.5))
            }
        }
        .frame(maxHeight: .infinity)
        .frame(width: settings.albumArtThumbSize + 8)
        .padding(.leading, 2)
    }

    private var trackInfoColumn: some View {
        VStack(spacing: 1) {
            Text(render(settings.line1Template))
                .font(.system(
                    size: settings.artistFontSize,
                    weight: settings.artistBold ? .semibold : .regular
                ))
                .foregroundStyle(settings.effectiveForeground)
                .lineLimit(1)
                .truncationMode(.tail)

            if settings.showTwoLines {
                Text(render(settings.line2Template))
                    .font(.system(
                        size: settings.songFontSize,
                        weight: settings.songBold ? .semibold : .regular
                    ))
                    .foregroundStyle(
                        settings.effectiveForeground
                            .opacity(settings.dimSecondLine ? 0.65 : 1.0)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenWindow)
    }

    private var previousTrackColumn: some View {
        Image(systemName: "backward.end.fill")
            .font(.system(size: settings.buttonIconSize, weight: .medium))
            .foregroundStyle(settings.effectiveForeground)
            .scaleEffect(prevPressed ? 0.75 : 1.0)
            .opacity(prevPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: prevPressed)
            .frame(maxHeight: .infinity)
            .frame(width: settings.buttonColumnWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($prevPressed) { _, state, _ in state = true }
                    .onEnded { _ in playback.skipBackward() }
            )
            .accessibilityLabel("Previous track")
            .accessibilityAddTraits(.isButton)
    }

    private var playPauseColumn: some View {
        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: settings.buttonIconSize, weight: .medium))
            .foregroundStyle(settings.effectiveForeground)
            .scaleEffect(playPausePressed ? 0.75 : 1.0)
            .opacity(playPausePressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: playPausePressed)
            .frame(maxHeight: .infinity)
            .frame(width: settings.buttonColumnWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($playPausePressed) { _, state, _ in state = true }
                    .onEnded { _ in playback.togglePlayPause() }
            )
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            .accessibilityAddTraits(.isButton)
    }

    private var nextTrackColumn: some View {
        Image(systemName: "forward.end.fill")
            .font(.system(size: settings.buttonIconSize, weight: .medium))
            .foregroundStyle(settings.effectiveForeground)
            .scaleEffect(nextTrackPressed ? 0.75 : 1.0)
            .opacity(nextTrackPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: nextTrackPressed)
            .frame(maxHeight: .infinity)
            .frame(width: settings.buttonColumnWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($nextTrackPressed) { _, state, _ in state = true }
                    .onEnded { _ in playback.skipForward() }
            )
            .accessibilityLabel("Next track")
            .accessibilityAddTraits(.isButton)
    }

    private func likeColumn(oauthAvailable: Bool) -> some View {
        Image(systemName: oauthAvailable
              ? (playback.isLiked ? "heart.fill" : "heart")
              : "heart.slash")
            .font(.system(size: settings.buttonIconSize, weight: .medium))
            .foregroundStyle(
                // White when actively liked — gives a clear "selected" signal regardless of chosen color.
                playback.isLiked && oauthAvailable
                    ? Color.white
                    : settings.effectiveForeground
            )
            .opacity(oauthAvailable ? (likePressed ? 0.7 : 1.0) : 0.4)
            .scaleEffect(likePressed ? 0.75 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: likePressed)
            .modifier(ShakeEffect(animatableData: CGFloat(playback.likeShakeCount)))
            .animation(.linear(duration: 0.4), value: playback.likeShakeCount)
            .frame(maxHeight: .infinity)
            .frame(width: settings.buttonColumnWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($likePressed) { _, state, _ in state = true }
                    .onEnded { _ in if oauthAvailable { playback.toggleLike() } }
            )
            .accessibilityLabel(
                oauthAvailable ? (playback.isLiked ? "Unlike" : "Like") : "Like unavailable"
            )
            .accessibilityAddTraits(.isButton)
    }
}
