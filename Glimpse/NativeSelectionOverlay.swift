import AppKit
import QuartzCore

/// NSPanel subclass that accepts key status — NSPanel can become key in .accessory mode
/// (unlike NSWindow which can't). Required for receiving mouseDown events.
private class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Native fullscreen selection overlay using Core Graphics drawing.
/// Zero WebKit overhead — mouseDragged triggers direct redraw at display refresh rate.
/// Handles: drag-to-select, window highlight on hover, dimension HUD, ESC to dismiss.
class NativeSelectionOverlay: NSView {

    // MARK: - State

    private var startPoint: CGPoint?
    private var currentRect: CGRect = .zero
    private var isDragging = false
    private var windowRects: [CGRect] = []         // view coordinates (flipped)
    private var windowInfos: [[String: Any]] = []  // raw data for handoff
    private var hoveredWindowIndex: Int?

    // MARK: - Window

    var overlayWindow: NSWindow?
    private var screenFrame: NSRect = .zero

    // MARK: - Callbacks

    var onSelectionComplete: ((_ rect: CGRect, _ windowBounds: [[String: Any]]) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - Coordinate system

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // Accept clicks immediately without requiring a prior activation click
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // MARK: - Factory

    @discardableResult
    static func show(
        on screen: NSScreen,
        windowBounds: [[String: Any]],
        completion: @escaping (_ rect: CGRect, _ windowBounds: [[String: Any]]) -> Void,
        dismiss: @escaping () -> Void
    ) -> NativeSelectionOverlay {
        let frame = screen.frame
        let view = NativeSelectionOverlay(frame: NSRect(origin: .zero, size: frame.size))
        view.screenFrame = frame
        view.onSelectionComplete = completion
        view.onDismiss = dismiss

        // Convert window bounds from CG global coords to view-local coords
        let mainHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let cgScreenOriginX = frame.origin.x
        let cgScreenOriginY = mainHeight - frame.origin.y - frame.height

        for info in windowBounds {
            // Skip the "Desktop" fallback entry — it covers the entire screen
            // and would prevent free-form drag on empty areas
            let owner = info["owner"] as? String ?? ""
            if owner == "Desktop" { continue }

            let x = (info["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (info["y"] as? NSNumber)?.doubleValue ?? 0
            let w = (info["w"] as? NSNumber)?.doubleValue ?? 0
            let h = (info["h"] as? NSNumber)?.doubleValue ?? 0
            let viewX = x - cgScreenOriginX
            let viewY = y - cgScreenOriginY
            view.windowRects.append(CGRect(x: viewX, y: viewY, width: w, height: h))
        }
        view.windowInfos = windowBounds

        // Create panel (NSPanel can become key in .accessory activation policy)
        let window = SelectionPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        // Use near-transparent background (not fully clear) so the window
        // receives mouse events — fully transparent windows pass clicks through.
        window.backgroundColor = NSColor(white: 0, alpha: 0.001)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        window.contentView = view
        view.overlayWindow = window

        // Same pattern as GlimpsePanel.showAndFocus() — this works for .accessory apps
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(view)
        // Retry key status after activation completes (async)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if !window.isKeyWindow {
                window.makeKey()
                NSLog("[NativeSelection] Retried makeKey, isKey=\(window.isKeyWindow)")
            }
        }
        NSLog("[NativeSelection] Overlay shown on \(Int(frame.width))x\(Int(frame.height)) screen, \(windowBounds.count) windows, isKey=\(window.isKeyWindow), firstResponder=\(window.firstResponder === view)")

        return view
    }

    // MARK: - Drawing (Core Graphics — reliable on transparent windows)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let viewRect = bounds

        // Determine the cutout rect (selection or hovered window)
        let cutout: CGRect?
        if hasDraggedPastThreshold && currentRect.width > 2 && currentRect.height > 2 {
            cutout = currentRect
        } else if !isDragging, let idx = hoveredWindowIndex, idx < windowRects.count {
            cutout = windowRects[idx]
        } else {
            cutout = nil
        }

        // Draw dark mask with even-odd cutout
        ctx.setFillColor(red: 4/255, green: 8/255, blue: 16/255, alpha: 0.55)
        if let cutout {
            // Even-odd: fill outer rect, subtract inner rect
            ctx.beginPath()
            ctx.addRect(viewRect)
            ctx.addRect(cutout)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(viewRect)
        }

        // "Screenshot Mode" label — top center, 50px from top (matches CSS .screenshot-mode-toast)
        // Only shown before selection starts
        if !hasDraggedPastThreshold && hoveredWindowIndex == nil {
            let toastText = "Screenshot Mode"
            let toastFont = NSFont(name: "Outfit", size: 18) ?? NSFont.systemFont(ofSize: 18)
            let toastAttrs: [NSAttributedString.Key: Any] = [
                .font: toastFont,
                .foregroundColor: NSColor(white: 1, alpha: 0.9)
            ]
            let toastSize = (toastText as NSString).size(withAttributes: toastAttrs)
            let toastW = toastSize.width + 56  // padding: 28px each side
            let toastH = toastSize.height + 24 // padding: 12px each side
            let toastX = (viewRect.width - toastW) / 2
            let toastY: CGFloat = 50

            // Background: rgba(20, 24, 36, 0.88) + 12px radius
            let toastRect = CGRect(x: toastX, y: toastY, width: toastW, height: toastH)
            ctx.setFillColor(red: 20/255, green: 24/255, blue: 36/255, alpha: 0.88)
            let toastPath = CGPath(roundedRect: toastRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.addPath(toastPath)
            ctx.fillPath()

            // Border: 1px rgba(108, 99, 255, 0.08)
            ctx.setStrokeColor(red: 108/255, green: 99/255, blue: 1.0, alpha: 0.08)
            ctx.setLineWidth(1)
            ctx.addPath(toastPath)
            ctx.strokePath()

            // Text
            let textX = toastX + (toastW - toastSize.width) / 2
            let textY = toastY + (toastH - toastSize.height) / 2
            (toastText as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: toastAttrs)
        }

        // Draw selection border
        if let cutout, cutout.width > 5 && cutout.height > 5 {
            ctx.setStrokeColor(red: 108/255, green: 99/255, blue: 1.0, alpha: 1.0)
            ctx.setLineWidth(1.5)
            ctx.stroke(cutout)

            // Dimension label
            if cutout.width > 20 && cutout.height > 20 {
                let text = "\(Int(cutout.width)) × \(Int(cutout.height))"
                let font = NSFont(name: "Outfit", size: 11) ?? NSFont.systemFont(ofSize: 11, weight: .medium)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white
                ]
                let textSize = (text as NSString).size(withAttributes: attrs)
                let labelW = textSize.width + 12
                let labelH: CGFloat = 20

                var labelX = cutout.maxX - labelW
                var labelY = cutout.maxY + 6
                if labelY + labelH > viewRect.height { labelY = cutout.minY - labelH - 6 }
                if labelX < 4 { labelX = cutout.minX }

                // Background pill
                let labelRect = CGRect(x: labelX, y: labelY, width: labelW, height: labelH)
                ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.7)
                let pillPath = CGPath(roundedRect: labelRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
                ctx.addPath(pillPath)
                ctx.fillPath()

                // Text
                let textX = labelX + (labelW - textSize.width) / 2
                let textY = labelY + (labelH - textSize.height) / 2
                (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
            }
        }
    }

    // MARK: - Mouse Tracking

    private var hasDraggedPastThreshold = false
    private let dragThreshold: CGFloat = 5

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Always start tracking — distinguish click vs drag on mouseUp
        startPoint = point
        isDragging = true
        hasDraggedPastThreshold = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)

        let dx = abs(current.x - start.x)
        let dy = abs(current.y - start.y)

        // Only start free-form selection after drag exceeds threshold
        if !hasDraggedPastThreshold {
            if dx < dragThreshold && dy < dragThreshold { return }
            hasDraggedPastThreshold = true
            // Clear window hover once dragging starts
            if hoveredWindowIndex != nil {
                hoveredWindowIndex = nil
            }
        }

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        currentRect = CGRect(x: x, y: y, width: dx, height: dy)

        needsDisplay = true
        displayIfNeeded()
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        let wasDrag = hasDraggedPastThreshold
        hasDraggedPastThreshold = false
        startPoint = nil

        if wasDrag && currentRect.width >= 10 && currentRect.height >= 10 {
            // Free-form drag selection
            completeSelection()
        } else {
            // Click (no drag) — snap to hovered window, or full screen if empty area
            if let idx = hoveredWindowIndex, idx < windowRects.count {
                currentRect = windowRects[idx]
            } else {
                // Full screen selection (Desktop fallback)
                currentRect = bounds
            }
            needsDisplay = true
            // Brief flash of selection then complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.completeSelection()
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard !isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)

        let idx = findWindowAt(point)
        if idx != hoveredWindowIndex {
            hoveredWindowIndex = idx
            setNeedsDisplay(bounds)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onDismiss?()
        }
    }

    // MARK: - Window Hit Testing

    private func findWindowAt(_ point: CGPoint) -> Int? {
        for (i, rect) in windowRects.enumerated() {
            if rect.contains(point) {
                return i
            }
        }
        return nil
    }

    // MARK: - Selection Complete

    private func completeSelection() {
        onSelectionComplete?(currentRect, windowInfos)
    }

    // MARK: - Dismiss

    func dismiss() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}
