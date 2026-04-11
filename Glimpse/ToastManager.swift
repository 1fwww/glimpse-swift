import AppKit

/// Native toast matching Tauri's show_toast spec:
/// Centered horizontally, 18% from top, dark glass, 13px font, green checkmark icon.
class ToastManager {
    static let shared = ToastManager()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(_ message: String, duration: TimeInterval = 1.8) {
        DispatchQueue.main.async { [weak self] in
            self?.hideTimer?.invalidate()
            self?.panel?.orderOut(nil)
            self?.panel = nil

            let screen = NSScreen.main ?? NSScreen.screens.first!
            let sf = screen.frame

            // Fixed size: 220×44 (matches Tauri toast)
            let w: CGFloat = 220
            let h: CGFloat = 44

            // Position: centered horizontally, 18% from top of screen
            let x = sf.midX - w / 2
            // Cocoa y: bottom-left origin → sf.maxY - (sf.height * 0.18) - h
            let y = sf.maxY - (sf.height * 0.18) - h

            let p = NSPanel(
                contentRect: NSRect(x: x, y: y, width: w, height: h),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // Backdrop blur via NSVisualEffectView
            let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 10
            blur.layer?.masksToBounds = true

            // Container view: rgba(20,24,36,0.92) + cyan border
            let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(
                calibratedRed: 20/255, green: 24/255, blue: 36/255, alpha: 0.92
            ).cgColor
            container.layer?.cornerRadius = 10
            // 1px rgba(0,229,255,0.2) border — cyan, matches Tauri
            container.layer?.borderColor = NSColor(
                calibratedRed: 0, green: 229/255, blue: 1.0, alpha: 0.2
            ).cgColor
            container.layer?.borderWidth = 1

            // Layout: [8px gap] [checkmark 16×16] [8px gap] [text] — centered vertically
            let hPad: CGFloat = 20
            let iconSize: CGFloat = 16
            let gap: CGFloat = 8

            // Green checkmark icon — draw as NSImage
            let checkmark = self?.drawCheckmark(size: iconSize)
            let iconView = NSImageView(frame: NSRect(
                x: hPad,
                y: (h - iconSize) / 2,
                width: iconSize,
                height: iconSize
            ))
            iconView.image = checkmark
            iconView.imageScaling = .scaleProportionallyUpOrDown

            // Label — rgba(230,240,255,0.9), 13px Outfit font
            let font = NSFont(name: "Outfit", size: 13) ?? NSFont.systemFont(ofSize: 13)
            let label = NSTextField(labelWithString: message)
            label.font = font
            label.textColor = NSColor(
                calibratedRed: 230/255, green: 240/255, blue: 1.0, alpha: 0.9
            )
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            let labelX = hPad + iconSize + gap
            let labelWidth = w - labelX - hPad
            let labelHeight = font.ascender - font.descender
            label.frame = NSRect(
                x: labelX,
                y: (h - labelHeight) / 2,
                width: labelWidth,
                height: labelHeight
            )

            container.addSubview(iconView)
            container.addSubview(label)

            let contentView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            contentView.addSubview(blur)
            contentView.addSubview(container)
            p.contentView = contentView

            p.orderFrontRegardless()
            self?.panel = p

            // Auto-dismiss with fade out
            self?.hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    self?.panel?.animator().alphaValue = 0
                }, completionHandler: {
                    self?.panel?.orderOut(nil)
                    self?.panel = nil
                })
            }
        }
    }

    /// Draw green checkmark matching Tauri's SVG: stroke rgb(52,199,89), strokeWidth 2.5
    private func drawCheckmark(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()

        let path = NSBezierPath()
        // SVG viewBox 0 0 24 24, path: M20 6L9 17l-5-5 — scale to `size`
        let s = size / 24.0
        path.move(to: NSPoint(x: 20 * s, y: size - 6 * s))    // M20,6 → flipped y
        path.line(to: NSPoint(x: 9 * s, y: size - 17 * s))     // L9,17
        path.line(to: NSPoint(x: 4 * s, y: size - 12 * s))     // l-5,-5 → L4,12

        NSColor(calibratedRed: 52/255, green: 199/255, blue: 89/255, alpha: 1.0).setStroke()
        path.lineWidth = 2.5 * s
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        img.unlockFocus()
        return img
    }
}
