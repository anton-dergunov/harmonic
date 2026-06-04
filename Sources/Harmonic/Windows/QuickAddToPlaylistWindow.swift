import AppKit
import SwiftUI

final class QuickAddToPlaylistWindow: NSWindow {
    init(playback: PlaybackViewModel) {
        let size = CGSize(width: Layout.width, height: Layout.total)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        isReleasedWhenClosed = false
        hasShadow = true
        collectionBehavior = [.transient, .canJoinAllSpaces, .ignoresCycle]

        let hostingView = NSHostingView(rootView:
            QuickAddContainer(playback: playback, window: self)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = CGColor.clear
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }

    // Called by macOS when Escape (or Cmd+.) is pressed, even when a text field
    // has first-responder focus. This is the correct override for "cancel".
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private struct QuickAddContainer: View {
    @ObservedObject var playback: PlaybackViewModel
    let window: NSWindow

    var body: some View {
        QuickAddToPlaylistDialog(
            playlists: playback.addablePlaylists,
            onAdd: { playlist in
                playback.addCurrentTrackToPlaylistWithTracking(playlist.id)
            },
            onDismiss: { window.close() }
        )
        .environmentObject(playback)
    }
}
