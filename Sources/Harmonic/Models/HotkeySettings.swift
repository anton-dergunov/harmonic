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

    var likeAction: (() -> Void)?
    var playerWindowAction: (() -> Void)?

    private var likeHotKey: HotKey?
    private var playerWindowHotKey: HotKey?

    private init() {
        likeShortcut = loadLike()
        playerWindowShortcut = loadPlayerWindow()
        registerLike()
        registerPlayerWindow()
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
}
