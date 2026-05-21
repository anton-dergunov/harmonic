import AppKit
import SwiftUI

final class PlayerWindow: NSWindow {
    init(playback: PlaybackViewModel) {
        let size = CGSize(width: PlayerTheme.popoverSize, height: PlayerTheme.popoverSize)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        // Level just above normal floating panels; high enough to appear
        // over most app windows when triggered from the menu bar.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        isReleasedWhenClosed = false
        hasShadow = true
        // Transient: excluded from Exposé/Mission Control; appears on all spaces.
        collectionBehavior = [.transient, .canJoinAllSpaces, .ignoresCycle]

        let hostingView = NSHostingView(rootView:
            PlayerPopoverView()
                .environmentObject(playback)
        )
        // Clear the hosting view's layer background so the SwiftUI clip shape's
        // rounded corners are transparent rather than showing a white rectangle.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = CGColor.clear
        contentView = hostingView
    }

    // Borderless windows don't become key by default; override so the window
    // can receive keyboard events and the resign-key mechanism works for dismissal.
    override var canBecomeKey: Bool { true }
}
