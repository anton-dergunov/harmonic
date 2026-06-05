import SwiftUI

// Heights are fixed so the window frame exactly covers the content — no transparent
// dead-zones that would eat mouse events without doing anything visible.
enum Layout {
    static let width: CGFloat     = 320
    static let appBar: CGFloat    = 30
    static let trackInfo: CGFloat = 78
    static let search: CGFloat    = 38
    static let listMax: CGFloat   = 230
    // Total height equals the window height set in QuickAddToPlaylistWindow.
    static var total: CGFloat { appBar + 1 + trackInfo + 1 + search + 1 + listMax }
}

struct QuickAddToPlaylistDialog: View {
    @EnvironmentObject private var playback: PlaybackViewModel

    let playlists: [SpotifyPlaylist]
    let onAdd: (SpotifyPlaylist) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedPlaylist: SpotifyPlaylist?
    @FocusState private var searchFocused: Bool

    private var filteredPlaylists: [SpotifyPlaylist] {
        guard !searchText.isEmpty else { return playlists }
        return playlists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            appBar
            Divider()
            trackInfoSection
            Divider()
            searchBar
            Divider()
            listSection
        }
        .frame(width: Layout.width, height: Layout.total)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onAppear(perform: setupInitialState)
        .onChange(of: searchText, perform: { _ in
            // Keep selection in sync with the filtered list.
            if filteredPlaylists.first(where: { $0.id == selectedPlaylist?.id }) == nil {
                selectedPlaylist = filteredPlaylists.first
            }
        })
    }

    // MARK: - Sections

    private var appBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Harmonic — Add to Playlist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { playback.refreshPlaylists() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
                    .rotationEffect(.degrees(playback.isLoadingPlaylists ? 360 : 0))
                    .animation(
                        playback.isLoadingPlaylists
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: playback.isLoadingPlaylists
                    )
            }
            .buttonStyle(.plain)
            .disabled(playback.isLoadingPlaylists)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: Layout.appBar)
        .padding(.horizontal, 14)
    }

    private var trackInfoSection: some View {
        HStack(spacing: 12) {
            coverArt
            VStack(alignment: .leading, spacing: 3) {
                Text(playback.song.isEmpty ? "Nothing playing" : playback.song)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !playback.artist.isEmpty {
                    Text(playback.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !playback.album.isEmpty {
                    Text(playback.album)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: Layout.trackInfo)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var coverArt: some View {
        let size: CGFloat = 52
        if let image = playback.coverImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.20))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            TextField("Search playlists…", text: $searchText)
                .focused($searchFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(confirmSelected)
        }
        .frame(height: Layout.search)
        .padding(.horizontal, 14)
    }

    private var listSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredPlaylists.isEmpty {
                    Text(playlists.isEmpty ? "No playlists available" : "No matches")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(filteredPlaylists) { playlist in
                        PlaylistRow(
                            name: playlist.name,
                            isSelected: selectedPlaylist?.id == playlist.id,
                            action: { addAndClose(playlist) }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: Layout.listMax)
    }

    // MARK: - Actions

    private func setupInitialState() {
        let recentId = RecentPlaylistSettings.shared.recentPlaylistId
        let initial  = playlists.first { $0.id == recentId } ?? playlists.first
        selectedPlaylist = initial
        searchText       = initial?.name ?? ""
        // Focus + select all so typing immediately replaces the pre-filled name.
        DispatchQueue.main.async {
            searchFocused = true
            NSApp.keyWindow?.firstResponder?
                .tryToPerform(#selector(NSText.selectAll(_:)), with: nil)
        }
    }

    private func confirmSelected() {
        // Prefer the current selection if it's still in the filtered results;
        // otherwise fall back to the first visible item.
        let target = filteredPlaylists.first(where: { $0.id == selectedPlaylist?.id })
                  ?? filteredPlaylists.first
        if let playlist = target {
            addAndClose(playlist)
        }
    }

    private func addAndClose(_ playlist: SpotifyPlaylist) {
        onAdd(playlist)
        RecentPlaylistSettings.shared.recentPlaylistId = playlist.id
        onDismiss()
    }
}

// MARK: - Row

private struct PlaylistRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected || isHovered ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Vibrancy

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
