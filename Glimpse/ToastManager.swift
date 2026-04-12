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
            p.hasShadow = true
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

            // Custom drawn container — pixel-perfect centering via Core Graphics
            let toastView = ToastContentView(
                frame: NSRect(x: 0, y: 0, width: w, height: h),
                message: message
            )
            toastView.wantsLayer = true
            toastView.layer?.cornerRadius = 10
            toastView.layer?.masksToBounds = true

            let contentView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            contentView.addSubview(blur)
            contentView.addSubview(toastView)
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

/// Custom-drawn toast content — background, checkmark, and text via Core Graphics.
/// No NSTextField = no internal padding issues = pixel-perfect centering.
private class ToastContentView: NSView {
    let message: String

    init(frame: NSRect, message: String) {
        self.message = message
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds

        // Background: dark with warm green tint — success feel, visible on any background
        ctx.setFillColor(red: 20/255, green: 30/255, blue: 24/255, alpha: 0.88)
        ctx.fill(b)

        // Border: green accent
        ctx.setStrokeColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 0.25)
        ctx.setLineWidth(1)
        ctx.stroke(b.insetBy(dx: 0.5, dy: 0.5))

        let iconSize: CGFloat = 16
        let gap: CGFloat = 8

        // Measure total content width, then center horizontally
        let font = NSFont(name: "Outfit", size: 13) ?? NSFont.systemFont(ofSize: 13)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 240/255, green: 245/255, blue: 240/255, alpha: 0.92)
        ]
        let textSize = (message as NSString).size(withAttributes: attrs)
        let totalWidth = iconSize + gap + textSize.width
        let startX = (b.width - totalWidth) / 2

        // Draw green checkmark — centered vertically
        let iconY = (b.height - iconSize) / 2
        ctx.saveGState()
        ctx.translateBy(x: startX, y: iconY)
        let s = iconSize / 24.0
        let checkPath = CGMutablePath()
        checkPath.move(to: CGPoint(x: 20 * s, y: iconSize - 6 * s))
        checkPath.addLine(to: CGPoint(x: 9 * s, y: iconSize - 17 * s))
        checkPath.addLine(to: CGPoint(x: 4 * s, y: iconSize - 12 * s))
        ctx.setStrokeColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1.0)
        ctx.setLineWidth(2.5 * s)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(checkPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Draw text — centered both horizontally and vertically
        let textX = startX + iconSize + gap
        let textY = (b.height - textSize.height) / 2
        (message as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }
}
