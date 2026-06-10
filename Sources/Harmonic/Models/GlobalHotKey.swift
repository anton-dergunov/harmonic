import AppKit
import Carbon

// Global hotkey registration via the Carbon Event Manager (RegisterEventHotKey).
// Does not require the Accessibility permission.
final class GlobalHotKey {
    // Holds weak references only — a strong-reference registry would keep every
    // GlobalHotKey alive forever, preventing deinit (and UnregisterEventHotKey)
    // from ever running when a hotkey is replaced or cleared.
    fileprivate final class WeakBox {
        weak var value: GlobalHotKey?
        init(_ value: GlobalHotKey) { self.value = value }
    }
    fileprivate static var registry: [UInt32: WeakBox] = [:]
    private static var eventHandlerRef: EventHandlerRef?
    private static var nextID: UInt32 = 1
    private static let signature: FourCharCode = 0x48726D4E  // "HrmN"

    var keyDownHandler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    init(carbonKeyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        id = Self.nextID
        Self.nextID += 1
        Self.registry[id] = WeakBox(self)
        Self.ensureEventHandler()

        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(carbonKeyCode, modifiers.carbonFlags, hkID,
                            GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        Self.registry.removeValue(forKey: id)
    }

    private static func ensureEventHandler() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), globalHotKeyHandler,
                            1, &spec, nil, &eventHandlerRef)
    }
}

private func globalHotKeyHandler(_: EventHandlerCallRef?,
                                  _ event: EventRef?,
                                  _: UnsafeMutableRawPointer?) -> OSStatus {
    var hkID = EventHotKeyID()
    GetEventParameter(event, UInt32(kEventParamDirectObject),
                      UInt32(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    GlobalHotKey.registry[hkID.id]?.value?.keyDownHandler?()
    return noErr
}

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var f: UInt32 = 0
        if contains(.command) { f |= UInt32(cmdKey) }
        if contains(.shift)   { f |= UInt32(shiftKey) }
        if contains(.option)  { f |= UInt32(optionKey) }
        if contains(.control) { f |= UInt32(controlKey) }
        return f
    }
}
