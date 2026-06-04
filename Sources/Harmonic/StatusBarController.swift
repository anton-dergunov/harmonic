import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private var playerWindow: PlayerWindow?
    private var quickAddWindow: QuickAddToPlaylistWindow?
    let playback = PlaybackViewModel()

    // Global monitor fires for mouse events delivered to OTHER apps, giving
    // us reliable dismissal when the user clicks anywhere outside our window.
    private var globalEventMonitor: Any?

    // Timestamp of the last time we proactively hid the window.  Used to
    // debounce the status-bar tap: if the window was just dismissed because
    // focus left it (< 150 ms ago), don't reopen on the same click.
    private var lastHideTime: TimeInterval = 0

    private var cancellables = Set<AnyCancellable>()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: 150)
        super.init()
        setupStatusItem()
        observeSpotifyRunningState()
        startInactiveDisplayDimming()
        HotkeySettings.shared.likeAction = { [weak self] in
            self?.playback.toggleLike()
        }
        HotkeySettings.shared.playerWindowAction = { [weak self] in
            self?.togglePlayerWindow()
        }
        HotkeySettings.shared.addToPlaylistAction = { [weak self] in
            self?.showQuickAddDialog()
        }
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        let menuBarView = MenuBarItemView(onOpenWindow: { [weak self] in
            self?.togglePlayerWindow()
        })
        .environmentObject(playback)
        .environmentObject(MenuBarSettings.shared)

        let hostingView = NSHostingView(rootView: menuBarView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])

        // Only intercept right-clicks via the button action mechanism.
        // Left-click events propagate normally to SwiftUI views inside hostingView.
        button.action = #selector(handleButtonAction(_:))
        button.target = self
        button.sendAction(on: [.rightMouseUp])
    }

    // On the inactive display(s) of a multi-monitor setup, macOS keeps the real
    // status item on the active display and shows a system bitmap "replicant" on
    // every inactive one. That replicant is a full-colour snapshot of our custom
    // SwiftUI view and does NOT receive the inactive-menu-bar dimming that plain
    // template-image status items get, so it stays bright while every other app's
    // item is greyed out. We dim it ourselves by lowering the replicant's alpha.
    private func startInactiveDisplayDimming() {
        dimInactiveDisplayReplicants()

        // The replicant is recreated whenever the active display changes, resetting
        // its alpha. Poll so we re-dim each freshly created replicant; the replicant
        // only exists on inactive displays, so there is nothing to restore.
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.dimInactiveDisplayReplicants() }
            .store(in: &cancellables)
    }

    private func dimInactiveDisplayReplicants() {
        for window in NSApp.windows where window.isVisible {
            guard let contentView = window.contentView,
                  let replicant = findView(in: contentView, classNameContains: "ReplicantView"),
                  replicant.alphaValue != Self.inactiveDisplayAlpha else { continue }
            replicant.alphaValue = Self.inactiveDisplayAlpha
        }
    }

    private static let inactiveDisplayAlpha: CGFloat = 0.5

    /// Recursively find the first descendant whose class name contains `substring`.
    private func findView(in view: NSView, classNameContains substring: String) -> NSView? {
        for sub in view.subviews {
            if "\(type(of: sub))".contains(substring) { return sub }
            if let found = findView(in: sub, classNameContains: substring) { return found }
        }
        return nil
    }

    private func observeSpotifyRunningState() {
        let mbSettings = MenuBarSettings.shared

        playback.$isSpotifyRunning
            .sink { [weak self] running in
                self?.statusItem.length = running ? CGFloat(mbSettings.itemWidth) : 32
                if !running { self?.hidePlayerWindow() }
            }
            .store(in: &cancellables)

        // React to width changes made in Settings while Spotify is running.
        mbSettings.$itemWidth
            .dropFirst()
            .sink { [weak self] width in
                guard let self, self.playback.isSpotifyRunning else { return }
                self.statusItem.length = CGFloat(width)
            }
            .store(in: &cancellables)
    }

    @objc private func handleButtonAction(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type == .rightMouseUp else { return }
        // Warm the playlist cache so the submenu has data to show.
        playback.loadPlaylistsIfNeeded()
        showContextMenu()
    }

    private enum TrackMenuAction: Int {
        case copyArtistSong, copySong, copyArtist
        case openTrack, openArtist, openAlbum
        case searchArtistSong, searchArtist
    }

    private func trackMenuItem(_ title: String, _ action: TrackMenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(handleTrackAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = action.rawValue
        item.isEnabled = !playback.currentTrackId.isEmpty
        return item
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // ── Controls group ────────────────────────────────────────
        let hasTrack = !playback.currentTrackId.isEmpty
        menu.addItem(controlItem(
            "Previous",
            symbol: "backward.end.fill",
            action: #selector(handlePrev),
            enabled: hasTrack
        ))
        menu.addItem(controlItem(
            playback.isPlaying ? "Pause" : "Play",
            symbol: playback.isPlaying ? "pause.fill" : "play.fill",
            action: #selector(handlePlayPause),
            enabled: hasTrack
        ))
        menu.addItem(controlItem(
            "Skip Forward",
            symbol: "forward.end.fill",
            action: #selector(handleNext),
            enabled: hasTrack
        ))

        let likeItem = controlItem(
            playback.isLiked ? "Unlike" : "Like",
            symbol: playback.isLiked ? "heart.fill" : "heart",
            action: #selector(handleLike),
            enabled: hasTrack && playback.isLikeAvailable
        )
        if let shortcut = HotkeySettings.shared.likeShortcut {
            likeItem.keyEquivalent = shortcut.displayChar.lowercased()
            likeItem.keyEquivalentModifierMask = shortcut.modifiers
        }
        menu.addItem(likeItem)

        if playback.isPlaylistAvailable {
            menu.addItem(buildAddToPlaylistItem())
        }

        // ── Track actions group ───────────────────────────────────
        menu.addItem(.separator())

        let copyMenu = NSMenu()
        copyMenu.autoenablesItems = false
        copyMenu.addItem(trackMenuItem("Artist – Song", .copyArtistSong))
        copyMenu.addItem(trackMenuItem("Song", .copySong))
        copyMenu.addItem(trackMenuItem("Artist", .copyArtist))
        let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        copyItem.submenu = copyMenu
        menuIcon(copyItem, symbol: "doc.on.doc")
        menu.addItem(copyItem)

        let openMenu = NSMenu()
        openMenu.autoenablesItems = false
        openMenu.addItem(trackMenuItem("Track", .openTrack))
        openMenu.addItem(trackMenuItem("Artist", .openArtist))
        openMenu.addItem(trackMenuItem("Album", .openAlbum))
        let openItem = NSMenuItem(title: "Open in Spotify", action: nil, keyEquivalent: "")
        openItem.submenu = openMenu
        menuIcon(openItem, symbol: "arrow.up.right.square")
        menu.addItem(openItem)

        let searchMenu = NSMenu()
        searchMenu.autoenablesItems = false
        searchMenu.addItem(trackMenuItem("Google: Artist – Song", .searchArtistSong))
        searchMenu.addItem(trackMenuItem("Google: Artist", .searchArtist))
        let searchItem = NSMenuItem(title: "Search", action: nil, keyEquivalent: "")
        searchItem.submenu = searchMenu
        menuIcon(searchItem, symbol: "magnifyingglass")
        menu.addItem(searchItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menuIcon(settingsItem, symbol: "gearshape")
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Harmonic",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menuIcon(quitItem, symbol: "power")
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    private func menuIcon(_ item: NSMenuItem, symbol: String) {
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            img.isTemplate = true
            item.image = img
        }
    }

    private func controlItem(_ title: String, symbol: String, action: Selector,
                              enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menuIcon(item, symbol: symbol)
        return item
    }

    private func buildAddToPlaylistItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let lists = playback.addablePlaylists
        if lists.isEmpty {
            let placeholder = NSMenuItem(
                title: playback.playlistsLoaded ? "No playlists" : "Loading…",
                action: nil, keyEquivalent: ""
            )
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        } else {
            let trackAvailable = !playback.currentTrackId.isEmpty
            for pl in lists {
                let item = NSMenuItem(
                    title: pl.name,
                    action: #selector(handleAddToPlaylist(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = pl.id
                item.isEnabled = trackAvailable
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())
        let refresh = NSMenuItem(
            title: "Refresh playlists",
            action: #selector(handleRefreshPlaylists),
            keyEquivalent: ""
        )
        refresh.target = self
        submenu.addItem(refresh)

        let item = NSMenuItem(title: "Add to playlist", action: nil, keyEquivalent: "")
        menuIcon(item, symbol: "text.badge.plus")
        item.submenu = submenu
        return item
    }

    @objc private func handleAddToPlaylist(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        playback.addCurrentTrackToPlaylistWithTracking(id)
    }

    @objc private func handleRefreshPlaylists() {
        playback.refreshPlaylists()
    }

    @objc private func handlePlayPause() { playback.togglePlayPause() }
    @objc private func handleNext()      { playback.skipForward() }
    @objc private func handlePrev()      { playback.skipBackward() }
    @objc private func handleLike()      { playback.toggleLike() }

    @objc private func handleTrackAction(_ sender: NSMenuItem) {
        guard let action = TrackMenuAction(rawValue: sender.tag) else { return }
        switch action {
        case .copyArtistSong:   playback.copyArtistSong()
        case .copySong:         playback.copySong()
        case .copyArtist:       playback.copyArtist()
        case .openTrack:        playback.openInSpotify()
        case .openArtist:       playback.openArtistInSpotify()
        case .openAlbum:        playback.openAlbumInSpotify()
        case .searchArtistSong: playback.searchGoogleArtistSong()
        case .searchArtist:     playback.searchGoogleArtist()
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(authService: playback.authService)
    }

    // Called by the tap gesture in MenuBarItemView (left-click on track info area).
    func togglePlayerWindow() {
        if let window = playerWindow, window.isVisible {
            // Clicking the status bar item while the window is open → close it.
            hidePlayerWindow()
        } else {
            // Debounce: skip if the window was just auto-dismissed (< 150 ms ago)
            // because that means this tap is the very click that defocused the window.
            let now = CACurrentMediaTime()
            guard now - lastHideTime > 0.15 else { return }
            showPlayerWindow()
        }
    }

    private func showPlayerWindow() {
        if playerWindow == nil {
            playerWindow = PlayerWindow(playback: playback)
            playerWindow?.delegate = self
        }

        guard let window = playerWindow,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonFrameInScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        let size = window.frame.size
        let x = buttonFrameInScreen.midX - size.width / 2
        // 6 pt gap between the bottom of the menu bar and the top of the window.
        let y = buttonFrameInScreen.minY - size.height - 6

        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.makeKeyAndOrderFront(nil)

        startGlobalMonitor()
    }

    private func hidePlayerWindow() {
        lastHideTime = CACurrentMediaTime()
        playerWindow?.orderOut(nil)
        stopGlobalMonitor()
    }

    // MARK: - Global event monitor

    // Fires for mouse-down events delivered to other applications, giving
    // reliable dismissal when the user clicks anywhere outside our window.
    private func startGlobalMonitor() {
        stopGlobalMonitor()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hidePlayerWindow()
            }
        }
    }

    private func stopGlobalMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    private func showQuickAddDialog() {
        playback.loadPlaylistsIfNeeded()

        if let window = quickAddWindow, window.isVisible {
            window.orderFront(self)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = QuickAddToPlaylistWindow(playback: playback)
        quickAddWindow = window

        let screenFrame = NSScreen.main?.frame ?? .zero
        let windowSize = window.frame.size
        let x = (screenFrame.width - windowSize.width) / 2
        let y = screenFrame.height * 0.25

        window.setFrameOrigin(NSPoint(x: x, y: y))
        window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)

        window.delegate = self
    }
}

extension StatusBarController: NSWindowDelegate {
    // Backup dismissal path: keyboard navigation (Cmd+Tab, Escape, etc.)
    // that shifts focus without generating a mouse-down in another app.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            if (notification.object as? NSWindow) === quickAddWindow {
                quickAddWindow?.close()
                quickAddWindow = nil
            } else {
                hidePlayerWindow()
            }
        }
    }
}
