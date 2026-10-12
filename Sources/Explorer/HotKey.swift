import AppKit
import Carbon.HIToolbox

struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: NSEvent.ModifierFlags
    var key: String

    static let standard = Shortcut(keyCode: kVK_ANSI_E, modifiers: .command, key: "E")
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Shortcut.relevantModifiers)
        self.key = key
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Shortcut.relevantModifiers)
        guard !modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
        let key = Shortcut.names[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !key.isEmpty else { return nil }
        self.init(keyCode: Int(event.keyCode), modifiers: modifiers, key: key)
    }

    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }

    var carbonModifiers: Int {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return flags
    }

    private static let names: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

enum HotKey {
    private static var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?
    private static var installed = false
    private static var current: Shortcut?

    static func register(_ shortcut: Shortcut?, action: @escaping () -> Void) {
        handler = action
        current = shortcut
        apply(shortcut)
    }

    static func pause() { apply(nil) }

    static func resume() { apply(current) }

    private static func apply(_ shortcut: Shortcut?) {
        if !installed {
            installed = true
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.handler?() }
                return noErr
            }, 1, &eventType, nil, nil)
        }
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let shortcut else { return }
        let id = EventHotKeyID(signature: OSType(0x4558504C), id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.carbonModifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            ref = nil
            showError("\(shortcut.display) is already used by another app.")
        }
    }
}
