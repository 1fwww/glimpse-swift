import AppKit
import Carbon.HIToolbox

/// Global shortcut + window drag detection via CGEventTap.
/// Single tap handles: Cmd+Shift+X, Cmd+Shift+Z, ESC, and window dragging.
/// CGEventTap intercepts at HID level — works even when WKWebView consumes events.
class ShortcutManager {
    static weak var shared: ShortcutManager?

    var onChatShortcut: (() -> Void)?
    var onScreenshotShortcut: (() -> Void)?
    var onEscape: (() -> Void)?

    private var eventTap: CFMachPort?

    // Window drag state
    private var isDragging = false
    private var dragStartMouse: CGPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    weak var dragWindow: NSWindow?

    func start() {
        ShortcutManager.shared = self

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            NSLog("[Shortcut] Failed to create event tap — Accessibility permission needed")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Shortcut] Event tap installed")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    func startDrag(window: NSWindow) {
        isDragging = true
        dragWindow = window
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window.frame.origin
    }

    fileprivate func handleKey(_ keyCode: Int64, flags: CGEventFlags) {
        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)

        if hasCmd && hasShift {
            if keyCode == kVK_ANSI_X {
                NSLog("[Shortcut] Cmd+Shift+X")
                onChatShortcut?()
            } else if keyCode == kVK_ANSI_Z {
                NSLog("[Shortcut] Cmd+Shift+Z")
                onScreenshotShortcut?()
            }
        } else if keyCode == kVK_Escape {
            onEscape?()
        }
    }

    fileprivate func handleMouseDragged(location: CGPoint) {
        guard isDragging, let window = dragWindow else { return }
        // CGPoint from event is in flipped screen coordinates (origin top-left)
        // NSEvent.mouseLocation is in Cocoa coordinates (origin bottom-left)
        // Use NSEvent.mouseLocation for consistency with dragStartMouse
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartMouse.x
        let dy = current.y - dragStartMouse.y
        window.setFrameOrigin(NSPoint(
            x: dragStartOrigin.x + dx,
            y: dragStartOrigin.y + dy
        ))
    }

    fileprivate func handleMouseUp() {
        isDragging = false
        dragWindow = nil
    }

    fileprivate func reEnableTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("[Shortcut] Re-enabled timed-out event tap")
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type.rawValue == 0xFFFFFFFE {
        DispatchQueue.main.async { ShortcutManager.shared?.reEnableTap() }
        return Unmanaged.passRetained(event)
    }

    switch type {
    case .keyDown:
        // Ignore key repeat events (holding key down generates these)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
        guard isRepeat == 0 else { break }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        DispatchQueue.main.async {
            ShortcutManager.shared?.handleKey(keyCode, flags: flags)
        }

    case .leftMouseDragged:
        let loc = event.location
        DispatchQueue.main.async {
            ShortcutManager.shared?.handleMouseDragged(location: loc)
        }

    case .leftMouseUp:
        DispatchQueue.main.async {
            ShortcutManager.shared?.handleMouseUp()
        }

    default:
        break
    }

    return Unmanaged.passRetained(event)
}
