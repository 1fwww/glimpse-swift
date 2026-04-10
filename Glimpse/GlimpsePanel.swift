import AppKit

/// NSPanel subclass that accepts keyboard input.
/// NonactivatingPanel style allows floating on fullscreen Spaces.
/// canBecomeKey/canBecomeMain overrides enable keyboard + mouse interaction.
class GlimpsePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init(size: NSSize) {
        self.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.resizable, .titled], // TEMP: visible for testing (add .nonactivatingPanel later)
            backing: .buffered,
            defer: false
        )

        // Fullscreen Space support
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating

        // Panel behavior
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = NSColor.white.withAlphaComponent(0.95) // TEMP: visible for debugging
        hasShadow = true // TEMP

        // Accept mouse events immediately (no need to click-to-focus first)
        acceptsMouseMovedEvents = true
    }
}
