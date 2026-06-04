import AppKit
import HotKey

// A global keyboard shortcut: a key + modifiers + the display character (e.g. "L").
struct Shortcut: Equatable {
    let key: Key
    let modifiers: NSEvent.ModifierFlags
    let displayChar: String

    var displayString: String { modifiers.glyphs + displayChar }

    var keyCombo: KeyCombo { KeyCombo(key: key, modifiers: modifiers) }

    static let defaultLike = Shortcut(key: .l, modifiers: [.option], displayChar: "L")
    // No default for player window — users opt in explicitly.
    static let defaultAddToPlaylist = Shortcut(key: .a, modifiers: [.option, .command], displayChar: "A")
}

extension NSEvent.ModifierFlags {
    var glyphs: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

// MARK: -

@MainActor
final class HotkeySettings: ObservableObject {
    static let shared = HotkeySettings()

    @Published var likeShortcut: Shortcut? {
        didSet { saveLike(); registerLike() }
    }

    @Published var playerWindowShortcut: Shortcut? {
        didSet { savePlayerWindow(); registerPlayerWindow() }
    }

    @Published var addToPlaylistShortcut: Shortcut? {
        didSet { saveAddToPlaylist(); registerAddToPlaylist() }
    }

    var likeAction: (() -> Void)?
    var playerWindowAction: (() -> Void)?
    var addToPlaylistAction: (() -> Void)?

    private var likeHotKey: HotKey?
    private var playerWindowHotKey: HotKey?
    private var addToPlaylistHotKey: HotKey?

    private init() {
        likeShortcut = loadLike()
        playerWindowShortcut = loadPlayerWindow()
        addToPlaylistShortcut = loadAddToPlaylist()
        registerLike()
        registerPlayerWindow()
        registerAddToPlaylist()
    }

    private func registerLike() {
        likeHotKey = nil
        guard let s = likeShortcut else { return }
        let hk = HotKey(keyCombo: s.keyCombo)
        hk.keyDownHandler = { [weak self] in self?.likeAction?() }
        likeHotKey = hk
    }

    private func registerPlayerWindow() {
        playerWindowHotKey = nil
        guard let s = playerWindowShortcut else { return }
        let hk = HotKey(keyCombo: s.keyCombo)
        hk.keyDownHandler = { [weak self] in self?.playerWindowAction?() }
        playerWindowHotKey = hk
    }

    private func registerAddToPlaylist() {
        addToPlaylistHotKey = nil
        guard let s = addToPlaylistShortcut else { return }
        let hk = HotKey(keyCombo: s.keyCombo)
        hk.keyDownHandler = { [weak self] in self?.addToPlaylistAction?() }
        addToPlaylistHotKey = hk
    }

    // MARK: - Persistence

    private enum Defaults {
        static let likeKeyCode  = "hotkey.like.keyCode"
        static let likeMods     = "hotkey.like.mods"
        static let likeChar     = "hotkey.like.char"
        static let likeIsCustom = "hotkey.like.isCustom"

        static let winKeyCode  = "hotkey.playerWindow.keyCode"
        static let winMods     = "hotkey.playerWindow.mods"
        static let winChar     = "hotkey.playerWindow.char"
        static let winIsSet    = "hotkey.playerWindow.isSet"

        static let addToPlaylistKeyCode  = "hotkey.addToPlaylist.keyCode"
        static let addToPlaylistMods     = "hotkey.addToPlaylist.mods"
        static let addToPlaylistChar     = "hotkey.addToPlaylist.char"
        static let addToPlaylistIsCustom = "hotkey.addToPlaylist.isCustom"
    }

    private func loadLike() -> Shortcut? {
        let d = UserDefaults.standard
        guard d.bool(forKey: Defaults.likeIsCustom) else { return .defaultLike }
        guard d.object(forKey: Defaults.likeKeyCode) != nil else { return nil }
        let kc   = UInt32(d.integer(forKey: Defaults.likeKeyCode))
        let mods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: Defaults.likeMods)))
        let char = d.string(forKey: Defaults.likeChar) ?? "?"
        guard let key = Key(carbonKeyCode: kc) else { return .defaultLike }
        return Shortcut(key: key, modifiers: mods, displayChar: char)
    }

    private func saveLike() {
        let d = UserDefaults.standard
        d.set(true, forKey: Defaults.likeIsCustom)
        if let s = likeShortcut {
            d.set(Int(s.key.carbonKeyCode), forKey: Defaults.likeKeyCode)
            d.set(Int(s.modifiers.rawValue), forKey: Defaults.likeMods)
            d.set(s.displayChar, forKey: Defaults.likeChar)
        } else {
            d.removeObject(forKey: Defaults.likeKeyCode)
            d.removeObject(forKey: Defaults.likeMods)
            d.removeObject(forKey: Defaults.likeChar)
        }
    }

    private func loadPlayerWindow() -> Shortcut? {
        let d = UserDefaults.standard
        guard d.bool(forKey: Defaults.winIsSet),
              d.object(forKey: Defaults.winKeyCode) != nil else { return nil }
        let kc   = UInt32(d.integer(forKey: Defaults.winKeyCode))
        let mods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: Defaults.winMods)))
        let char = d.string(forKey: Defaults.winChar) ?? "?"
        guard let key = Key(carbonKeyCode: kc) else { return nil }
        return Shortcut(key: key, modifiers: mods, displayChar: char)
    }

    private func savePlayerWindow() {
        let d = UserDefaults.standard
        if let s = playerWindowShortcut {
            d.set(true, forKey: Defaults.winIsSet)
            d.set(Int(s.key.carbonKeyCode), forKey: Defaults.winKeyCode)
            d.set(Int(s.modifiers.rawValue), forKey: Defaults.winMods)
            d.set(s.displayChar, forKey: Defaults.winChar)
        } else {
            d.set(false, forKey: Defaults.winIsSet)
            d.removeObject(forKey: Defaults.winKeyCode)
            d.removeObject(forKey: Defaults.winMods)
            d.removeObject(forKey: Defaults.winChar)
        }
    }

    private func loadAddToPlaylist() -> Shortcut? {
        let d = UserDefaults.standard
        guard d.bool(forKey: Defaults.addToPlaylistIsCustom) else { return .defaultAddToPlaylist }
        guard d.object(forKey: Defaults.addToPlaylistKeyCode) != nil else { return nil }
        let kc   = UInt32(d.integer(forKey: Defaults.addToPlaylistKeyCode))
        let mods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: Defaults.addToPlaylistMods)))
        let char = d.string(forKey: Defaults.addToPlaylistChar) ?? "?"
        guard let key = Key(carbonKeyCode: kc) else { return .defaultAddToPlaylist }
        return Shortcut(key: key, modifiers: mods, displayChar: char)
    }

    private func saveAddToPlaylist() {
        let d = UserDefaults.standard
        d.set(true, forKey: Defaults.addToPlaylistIsCustom)
        if let s = addToPlaylistShortcut {
            d.set(Int(s.key.carbonKeyCode), forKey: Defaults.addToPlaylistKeyCode)
            d.set(Int(s.modifiers.rawValue), forKey: Defaults.addToPlaylistMods)
            d.set(s.displayChar, forKey: Defaults.addToPlaylistChar)
        } else {
            d.removeObject(forKey: Defaults.addToPlaylistKeyCode)
            d.removeObject(forKey: Defaults.addToPlaylistMods)
            d.removeObject(forKey: Defaults.addToPlaylistChar)
        }
    }
}
