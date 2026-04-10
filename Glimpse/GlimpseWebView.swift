import WebKit

/// WKWebView subclass for window dragging via -webkit-app-region: drag.
/// WKWebView consumes mouseDragged internally, so we use NSEvent local monitors
/// to intercept drag/up events at the app level before WebKit processes them.
class GlimpseWebView: WKWebView {
    private var dragMonitor: Any?
    private var upMonitor: Any?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

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
            // Return nil to consume the event (prevents text selection etc.)
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
