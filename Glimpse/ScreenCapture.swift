import AppKit
import CoreGraphics

/// Screen capture engine: captures the screen image, window bounds, and display info.
/// All data is formatted for the React frontend's `onScreenCaptured` handler.
struct ScreenCapture {

    struct CaptureResult {
        let imageURL: String                // file:// URL to JPEG in temp directory
        let windowBounds: [[String: Any]]   // [{ x, y, w, h, owner, name }]
        let displayInfo: [String: Any]      // { width, height }
        let offset: [String: Any]           // { x, y }
        let cursorX: Int                    // cursor position in CSS coords (top-left)
        let cursorY: Int
    }

    /// Temp file path for screenshot — reused each capture to avoid accumulating files.
    private static let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("glimpse-capture.jpg")

    /// Capture the screen where the cursor is. Runs synchronously — call from background thread.
    /// If `belowWindowID` is provided, captures only windows below that window (excludes it).
    static func capture(belowWindowID: CGWindowID = kCGNullWindowID) -> CaptureResult? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            NSLog("[Capture] No screen found")
            return nil
        }

        // Screen geometry
        let screenFrame = screen.frame
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

        // Capture screen image (optionally below a specific window to exclude it)
        let startTime = CFAbsoluteTimeGetCurrent()
        let listOption: CGWindowListOption = belowWindowID != kCGNullWindowID
            ? .optionOnScreenBelowWindow : .optionOnScreenOnly
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            listOption,
            belowWindowID,
            [.bestResolution]
        ) else {
            NSLog("[Capture] CGWindowListCreateImage failed")
            return nil
        }
        let captureMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        // Encode as JPEG and write to temp file (10-20x faster than PNG, smaller file)
        let encodeStart = CFAbsoluteTimeGetCurrent()
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.85]
        ) else {
            NSLog("[Capture] JPEG conversion failed")
            return nil
        }

        do {
            try jpegData.write(to: tempURL)
        } catch {
            NSLog("[Capture] Failed to write temp file: \(error)")
            return nil
        }
        let encodeMs = (CFAbsoluteTimeGetCurrent() - encodeStart) * 1000

        let imageURL = tempURL.absoluteString
        NSLog("[Capture] \(cgImage.width)x\(cgImage.height), \(jpegData.count / 1024)KB JPEG, capture: \(Int(captureMs))ms, encode+write: \(Int(encodeMs))ms")

        // Get window bounds
        let windowBounds = getWindowBounds(on: captureRect)

        // Display info: logical dimensions (what CSS sees)
        let displayInfo: [String: Any] = [
            "width": Int(screenFrame.width),
            "height": Int(screenFrame.height)
        ]

        // Offset for multi-monitor
        let offset: [String: Any] = [
            "x": Int(cgOriginX),
            "y": Int(cgOriginY)
        ]

        // Cursor position in CSS coordinates (top-left origin, relative to screen)
        let cursorX = Int(mouseLocation.x - screenFrame.origin.x)
        let cursorY = Int(screenFrame.height - (mouseLocation.y - screenFrame.origin.y))

        return CaptureResult(
            imageURL: imageURL,
            windowBounds: windowBounds,
            displayInfo: displayInfo,
            offset: offset,
            cursorX: cursorX,
            cursorY: cursorY
        )
    }

    /// Get visible window bounds on the given screen rect.
    static func getWindowBounds(on screenRect: CGRect) -> [[String: Any]] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var bounds: [[String: Any]] = []

        for window in windowList {
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat else { continue }

            guard w >= 50 && h >= 50 else { continue }

            let windowRect = CGRect(x: x, y: y, width: w, height: h)
            guard windowRect.intersects(screenRect) else { continue }

            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let name = window[kCGWindowName as String] as? String ?? ""

            if owner == "Glimpse" { continue }
            if owner == "Dock" { continue }
            if owner == "Notification Center" { continue }
            if owner == "Window Server" { continue }
            if owner == "Control Center" { continue }

            bounds.append([
                "x": Int(x),
                "y": Int(y),
                "w": Int(w),
                "h": Int(h),
                "owner": owner,
                "name": name
            ])
        }

        bounds.append([
            "x": Int(screenRect.origin.x),
            "y": Int(screenRect.origin.y),
            "w": Int(screenRect.width),
            "h": Int(screenRect.height),
            "owner": "Desktop",
            "name": ""
        ])

        NSLog("[Capture] Found \(bounds.count - 1) windows + Desktop on \(Int(screenRect.width))x\(Int(screenRect.height)) screen")
        return bounds
    }
}
