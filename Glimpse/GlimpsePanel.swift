import AppKit

/// NSPanel subclass that accepts keyboard input and floats on fullscreen Spaces.
/// Key insight: NonactivatingPanel is NOT needed for keyboard or fullscreen.
/// FullScreenAuxiliary + floating level + canBecomeKey is sufficient.
class GlimpsePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init(size: NSSize) {
        self.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        // Fullscreen Space support
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating

        // Panel behavior
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Accept mouse events immediately
        acceptsMouseMovedEvents = true
    }

    /// Show panel with proper activation for keyboard input (non-fullscreen)
    func showAndFocus() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Show panel on fullscreen Space without activating app (avoids Space switch).
    /// Uses orderFront + floating level. Keyboard input works via makeKey().
    func showOnFullscreen() {
        orderFrontRegardless()
        makeKey()
        // Force first responder to content so clicks/keyboard work immediately
        if let contentView = contentView {
            makeFirstResponder(contentView)
        }
    }
}
