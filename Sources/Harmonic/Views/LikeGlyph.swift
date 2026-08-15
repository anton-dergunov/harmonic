import SwiftUI

/// The heart icon in its three states, shared by the menu bar item and the
/// player popover so the states stay in sync.
///
/// In `.logOnly` mode a small database badge sits just outside the heart's
/// lower-right diagonal, signalling that the like is recorded in the local log
/// and never reaches Spotify. The badge needs no background knockout: the menu
/// bar background is not a known color, so separation comes from the offset.
struct LikeGlyph: View {
    let mode: PlaybackViewModel.LikeMode
    let isLiked: Bool
    let size: CGFloat
    let color: Color
    let badgeColor: Color

    private var symbolName: String {
        switch mode {
        case .unavailable:      return "heart.slash"
        case .spotify, .logOnly: return isLiked ? "heart.fill" : "heart"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbolName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)

            if mode == .logOnly {
                Image(systemName: "cylinder.split.1x2.fill")
                    .font(.system(size: max(6, size * 0.55), weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .offset(x: size * 0.30, y: size * 0.28)
            }
        }
    }
}
