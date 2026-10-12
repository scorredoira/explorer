import AppKit

final class ShortcutRecorder: NSButton {
    var shortcut: Shortcut? { didSet { updateTitle() } }
    var onChange: ((Shortcut?) -> Void)?
    private var recording = false { didSet { updateTitle() } }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        toolTip = "Click, then press the new shortcut. Delete turns it off, Esc cancels."
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        recording = true
        HotKey.pause()
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        HotKey.resume()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        let plain = event.modifierFlags.intersection(Shortcut.relevantModifiers).isEmpty
        if plain && event.keyCode == 53 {
            stopRecording()
        } else if plain && (event.keyCode == 51 || event.keyCode == 117) {
            stopRecording()
            shortcut = nil
            onChange?(nil)
        } else if let recorded = Shortcut(event: event) {
            stopRecording()
            shortcut = recorded
            onChange?(recorded)
        } else {
            NSSound.beep()
        }
    }

    private func updateTitle() {
        title = recording ? "Type shortcut…" : shortcut?.display ?? "None"
    }
}
