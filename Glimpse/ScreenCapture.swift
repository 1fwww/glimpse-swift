import AppKit
import CoreGraphics

/// Screen capture engine: captures the screen image, window bounds, and display info.
/// All data is formatted for the React frontend's `onScreenCaptured` handler.
struct ScreenCapture {

    struct CaptureResult {
        let dataUrl: String                 // data:image/png;base64,...
        let windowBounds: [[String: Any]]   // [{ x, y, w, h, owner, name }]
        let displayInfo: [String: Any]      // { width, height }
        let offset: [String: Any]           // { x, y }
    }

    /// Capture the screen where the cursor is. Runs synchronously — call from background thread.
    static func capture() -> CaptureResult? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            NSLog("[Capture] No screen found")
            return nil
        }

        // Screen geometry
        let screenFrame = screen.frame
        // Offset: screen origin relative to global coordinate space
        // macOS puts (0,0) at bottom-left of main display; CGWindowList uses top-left
        // Convert screen origin to CGWindowList coordinate space (top-left origin)
        guard let mainScreen = NSScreen.screens.first else {
            NSLog("[Capture] No main screen")
            return nil
        }
        let mainHeight = mainScreen.frame.height
        let cgOriginX = screenFrame.origin.x
        let cgOriginY = mainHeight - screenFrame.origin.y - screenFrame.height

        // Capture region in CGWindowList coordinates (top-left origin)
        let captureRect = CGRect(
            x: cgOriginX,
            y: cgOriginY,
            width: screenFrame.width,
            height: screenFrame.height
        )

        // Capture screen image
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            NSLog("[Capture] CGWindowListCreateImage failed")
            return nil
        }

        // Convert to PNG base64 data URL
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            NSLog("[Capture] PNG conversion failed")
            return nil
        }
        let base64 = pngData.base64EncodedString()
        let dataUrl = "data:image/png;base64,\(base64)"
        NSLog("[Capture] Image: \(cgImage.width)x\(cgImage.height), data size: \(pngData.count / 1024)KB")

        // Get window bounds
        let windowBounds = getWindowBounds(on: captureRect)

        // Display info: logical dimensions (what CSS sees)
        let displayInfo: [String: Any] = [
            "width": Int(screenFrame.width),
            "height": Int(screenFrame.height)
        ]

        // Offset for multi-monitor: the screen's origin in global coordinates
        let offset: [String: Any] = [
            "x": Int(cgOriginX),
            "y": Int(cgOriginY)
        ]

        return CaptureResult(
            dataUrl: dataUrl,
            windowBounds: windowBounds,
            displayInfo: displayInfo,
            offset: offset
        )
    }

    /// Get visible window bounds on the given screen rect.
    /// Returns array of { x, y, w, h, owner, name } in CGWindowList coordinates.
    private static func getWindowBounds(on screenRect: CGRect) -> [[String: Any]] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var bounds: [[String: Any]] = []

        for window in windowList {
            // Skip windows without bounds
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat else { continue }

            // Skip tiny windows (menu bar items, status icons, etc.)
            guard w >= 50 && h >= 50 else { continue }

            // Skip windows not on our target screen
            let windowRect = CGRect(x: x, y: y, width: w, height: h)
            guard windowRect.intersects(screenRect) else { continue }

            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let name = window[kCGWindowName as String] as? String ?? ""

            // Skip our own app
            if owner == "Glimpse" { continue }

            bounds.append([
                "x": Int(x),
                "y": Int(y),
                "w": Int(w),
                "h": Int(h),
                "owner": owner,
                "name": name
            ])
        }

        NSLog("[Capture] Found \(bounds.count) windows on screen")
        return bounds
    }
}
