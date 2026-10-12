import AppKit
import Carbon.HIToolbox

enum HotKey {
    private static var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?

    static func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        handler = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.handler?() }
            return noErr
        }, 1, &eventType, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4558504C), id: 1)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }
}
