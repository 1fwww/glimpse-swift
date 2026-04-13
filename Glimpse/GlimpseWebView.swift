import WebKit
import AppKit

private extension NSImage {
    func rotated(by degrees: CGFloat) -> NSImage {
        let s = size
        let img = NSImage(size: s)
        img.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: s.width / 2, yBy: s.height / 2)
        transform.rotate(byDegrees: degrees)
        transform.translateX(by: -s.width / 2, yBy: -s.height / 2)
        transform.concat()
        draw(at: .zero, from: NSRect(origin: .zero, size: s), operation: .copy, fraction: 1)
        img.unlockFocus()
        return img
    }
}

/// WKWebView subclass for window dragging via -webkit-app-region: drag.
/// WKWebView consumes mouseDragged internally, so we use NSEvent local monitors
/// to intercept drag/up events at the app level before WebKit processes them.
class GlimpseWebView: WKWebView {
    private var dragMonitor: Any?
    private var upMonitor: Any?

    /// Enable resize cursors + edge resize on chat panel edges.
    /// Borderless windows don't get system resize cursors or handling automatically.
    var showsResizeCursors = false

    private static let resizeInset: CGFloat = 6
    private static let cornerSize: CGFloat = 14

    // Resize state
    private var resizeEdge: ResizeEdge = .none
    private var resizeStartMouse: NSPoint = .zero
    private var resizeStartFrame: NSRect = .zero

    private enum ResizeEdge {
        case none
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // MARK: - Cursor rects

    private static var _nwseCursor: NSCursor?

    private static var nwseCursor: NSCursor {
        if let c = _nwseCursor { return c }
        let c = NSCursor(image: NSCursor.resizeLeftRight.image.rotated(by: 45), hotSpot: NSPoint(x: 8, y: 8))
        _nwseCursor = c
        return c
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard showsResizeCursors else { return }
        let b = bounds
        let ri = Self.resizeInset
        let cs = Self.cornerSize

        // Only right, bottom, bottom-right — left/top omitted (WKWebView jitter)
        // Bottom-right corner (flipped: y=maxY is bottom)
        addCursorRect(NSRect(x: b.maxX - cs, y: b.maxY - cs, width: cs, height: cs), cursor: Self.nwseCursor)

        // Right edge
        addCursorRect(NSRect(x: b.maxX - ri, y: cs, width: ri, height: b.height - cs * 2), cursor: .resizeLeftRight)
        // Bottom edge
        addCursorRect(NSRect(x: cs, y: b.maxY - ri, width: b.width - cs * 2, height: ri), cursor: .resizeUpDown)
    }

    // MARK: - Edge resize handling

    /// Detect which edge/corner a local point is on.
    /// Only right, bottom, and bottom-right supported — left/top resize causes
    /// jitter because WKWebView's compositor lags when the window origin moves.
    private func hitEdge(at point: NSPoint) -> ResizeEdge {
        guard showsResizeCursors else { return .none }
        let b = bounds
        let ri = Self.resizeInset
        let cs = Self.cornerSize

        let nearRight = point.x > b.width - ri
        // WKWebView isFlipped: y=0 is TOP, y=maxY is BOTTOM
        let nearBottom = point.y > b.height - ri

        let inCornerRight = point.x > b.width - cs
        let inCornerBottom = point.y > b.height - cs

        // Bottom-right corner
        if inCornerRight && inCornerBottom { return .bottomRight }

        // Edges
        if nearRight { return .right }
        if nearBottom { return .bottom }

        return .none
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let edge = hitEdge(at: local)

        if edge != .none, let window = window {
            // Start edge resize — intercept via local monitors (same pattern as drag)
            resizeEdge = edge
            resizeStartMouse = NSEvent.mouseLocation
            resizeStartFrame = window.frame

            dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                self?.handleResizeDrag()
                return nil  // consume
            }
            upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.finishResize()
                return event
            }
            return  // don't pass to WebKit
        }

        super.mouseDown(with: event)
    }

    private func handleResizeDrag() {
        guard let window = window, resizeEdge != .none else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - resizeStartMouse.x
        let dy = mouse.y - resizeStartMouse.y
        let sf = resizeStartFrame
        let minW = window.minSize.width
        let minH = window.minSize.height
        let maxW = window.maxSize.width
        let maxH = window.maxSize.height

        var x = sf.origin.x
        var y = sf.origin.y
        var w = sf.width
        var h = sf.height

        switch resizeEdge {
        case .right:
            w = max(minW, min(maxW, sf.width + dx))
        case .bottom:
            // Flipped: dragging bottom edge down = negative dy in screen coords
            let newH = max(minH, min(maxH, sf.height - dy))
            y = sf.maxY - newH
            h = newH
        case .bottomRight:
            w = max(minW, min(maxW, sf.width + dx))
            let newH = max(minH, min(maxH, sf.height - dy))
            y = sf.maxY - newH
            h = newH
        default:
            break
        }

        window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
    }

    private func finishResize() {
        resizeEdge = .none
        if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
        if let m = upMonitor { NSEvent.removeMonitor(m); upMonitor = nil }
        // Trigger didEndLiveResize so AppDelegate knows user resized
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
    }

    // MARK: - Window drag

    func startWindowDrag() {
        guard let window = window else { return }
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin

        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self, weak window] event in
            guard let window else { return event }
            let current = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(
                x: startOrigin.x + current.x - startMouse.x,
                y: startOrigin.y + current.y - startMouse.y
            ))
            _ = self
            return nil
        }

        upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.stopWindowDrag()
            return event
        }
    }

    private func stopWindowDrag() {
        if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
        if let m = upMonitor   { NSEvent.removeMonitor(m); upMonitor = nil }
    }
}
