import AppKit

// MARK: - Image Content View

/// Draws an image directly into a rounded-rect clip path via draw().
/// No NSImageView, no CALayer.contents — the image IS the view.
private class ImageContentView: NSView {
    var image: NSImage?
    let cornerRadius: CGFloat = 12

    /// Edge inset (points) that counts as a resize zone instead of drag
    private let resizeEdge: CGFloat = 6

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }

        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        // Clip to rounded rect — image pixels get rounded corners
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        // Hairline border matching chat panel
        NSColor(white: 1, alpha: 0.06).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    /// Returns true if the point is near the window edge (resize zone)
    private func isInResizeZone(_ point: NSPoint) -> Bool {
        let b = bounds
        return point.x < resizeEdge || point.x > b.width - resizeEdge ||
               point.y < resizeEdge || point.y > b.height - resizeEdge
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isInResizeZone(point) {
            // Let the system handle resize
            super.mouseDown(with: event)
        } else {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Image Viewer Panel

/// The image IS the window. Rounded corners clip the image pixels directly.
/// System shadow + hairline border for native feel. Close button on hover.
/// Resizable with aspect ratio locked. Draggable from interior.
class ImageViewerPanel: GlimpsePanel {
    private var imageContentView: ImageContentView!
    private let closeButton = NSButton()

    private let closeButtonSize: CGFloat = 24
    private let closeButtonInset: CGFloat = 8
    private var closeWidthConstraint: NSLayoutConstraint!
    private var closeHeightConstraint: NSLayoutConstraint!
    private var closeTopConstraint: NSLayoutConstraint!
    private var closeTrailingConstraint: NSLayoutConstraint!

    /// Image scales to fit within these bounds while preserving exact aspect ratio
    private let maxViewerWidth: CGFloat = 700
    private let maxViewerHeight: CGFloat = 500
    private let minViewerWidth: CGFloat = 100
    private let minViewerHeight: CGFloat = 75

    convenience init() {
        self.init(size: NSSize(width: 480, height: 320))
        styleMask = [.borderless, .resizable]
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false

        setupViews()
    }

    private func setupViews() {
        imageContentView = ImageContentView(frame: NSRect(origin: .zero, size: frame.size))
        imageContentView.autoresizingMask = [.width, .height]
        contentView = imageContentView

        // Close button — semi-transparent dark circle with white ×
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = closeButtonSize / 2
        closeButton.layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ]
        )
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        closeButton.setAccessibilityLabel("Close image viewer")
        closeButton.alphaValue = 0
        imageContentView.addSubview(closeButton)

        closeWidthConstraint = closeButton.widthAnchor.constraint(equalToConstant: closeButtonSize)
        closeHeightConstraint = closeButton.heightAnchor.constraint(equalToConstant: closeButtonSize)
        closeTopConstraint = closeButton.topAnchor.constraint(equalTo: imageContentView.topAnchor, constant: closeButtonInset)
        closeTrailingConstraint = closeButton.trailingAnchor.constraint(equalTo: imageContentView.trailingAnchor, constant: -closeButtonInset)
        NSLayoutConstraint.activate([closeWidthConstraint, closeHeightConstraint, closeTopConstraint, closeTrailingConstraint])

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        imageContentView.addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 0
        }
    }

    @discardableResult
    func showImage(at path: String) -> Bool {
        guard let image = NSImage(contentsOfFile: path) else {
            NSLog("[ImageViewer] Failed to load image: \(path)")
            return false
        }
        imageContentView.image = image
        resizeToFitImage(image)
        imageContentView.needsDisplay = true
        return true
    }

    private func resizeToFitImage(_ image: NSImage) {
        // Convert pixel dimensions to points using screen backing scale.
        let backingScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pointW: CGFloat
        let pointH: CGFloat
        if let rep = image.representations.first, rep.pixelsWide > 0 {
            pointW = CGFloat(rep.pixelsWide) / backingScale
            pointH = CGFloat(rep.pixelsHigh) / backingScale
        } else {
            pointW = image.size.width
            pointH = image.size.height
        }

        // 1. Start at natural 1:1 size
        // 2. Scale up if below min bounds
        // 3. Scale down if above max bounds
        // Max always wins over min — never exceed max bounds
        let scaleUp = max(minViewerWidth / pointW, minViewerHeight / pointH, 1.0)
        let scaleDown = min(maxViewerWidth / (pointW * scaleUp), maxViewerHeight / (pointH * scaleUp), 1.0)
        let scale = scaleUp * scaleDown
        let w = pointW * scale
        let h = pointH * scale

        // Set image.size to match window so draw(in: bounds) has zero distortion
        image.size = NSSize(width: w, height: h)

        let origin = frame.origin
        setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)

        // Lock resize to this image's aspect ratio
        contentAspectRatio = NSSize(width: w, height: h)
        // Allow resize within reasonable bounds
        minSize = NSSize(width: max(w * 0.3, 60), height: max(h * 0.3, 45))
        maxSize = NSSize(width: w * 3, height: h * 3)
    }

    /// Scale close button to fit within the window if the window is very small.
    private func fitCloseButton() {
        let w = frame.width
        let h = frame.height
        // Button needs closeButtonSize + 2*inset to fit. Scale everything proportionally.
        let needed = closeButtonSize + closeButtonInset * 2
        let scaleFactor = min(w / needed, h / needed, 1.0)
        let size = max(closeButtonSize * scaleFactor, 10)
        let inset = max(closeButtonInset * scaleFactor, 2)
        closeWidthConstraint.constant = size
        closeHeightConstraint.constant = size
        closeTopConstraint.constant = inset
        closeTrailingConstraint.constant = -inset
        closeButton.layer?.cornerRadius = size / 2

        let fontSize = max(11 * scaleFactor, 6)
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            ]
        )
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        fitCloseButton()
    }

    func showWithFade() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
        // Flash close button briefly so users discover it
        closeButton.alphaValue = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.isMouseInside else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.closeButton.animator().alphaValue = 0
            }
        }
    }

    /// Track whether mouse is inside to avoid fading out during hover
    private var isMouseInside = false

    @objc private func closePanel() {
        orderOut(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            closePanel()
        } else {
            super.keyDown(with: event)
        }
    }
}
