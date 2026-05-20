import SwiftUI

struct MenuBarItemView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    let onOpenWindow: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Track info: fills all remaining width.
            // The entire column is a tap target that opens the player window.
            VStack(spacing: 1) {
                Text(playback.artist)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(playback.song)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenWindow)

            // Skip button: full-height column so any click in its vertical
            // strip registers, not just the icon itself.
            Button {
                playback.skipForward()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity)
            .frame(width: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("Next track")

            // Like button: same full-height column treatment.
            // Liked state shows a solid white heart (distinct from the outline).
            Button {
                playback.toggleLike()
            } label: {
                Image(systemName: playback.isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(playback.isLiked ? Color.white : Color(nsColor: .labelColor))
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity)
            .frame(width: 28)
            .contentShape(Rectangle())
            .accessibilityLabel(playback.isLiked ? "Unlike" : "Like")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
