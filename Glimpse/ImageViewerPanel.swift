import AppKit

// MARK: - Image Content View

/// Draws an image directly into a rounded-rect clip path via draw().
/// No NSImageView, no CALayer.contents — the image IS the view.
/// Supports pinch-to-zoom and drag-to-pan when zoomed.
private class ImageContentView: NSView {
    var image: NSImage?
    let cornerRadius: CGFloat = 12

    /// Edge inset (points) that counts as a resize zone instead of drag
    private let resizeEdge: CGFloat = 6

    /// Called when pinch gesture starts/ends to hide/show chrome
    var onZoomingChanged: ((Bool) -> Void)?

    // Zoom + pan state
    private(set) var zoomScale: CGFloat = 1.0
    private var panOffset: CGPoint = .zero       // offset in image-space points
    private var isPanning = false
    private var lastDragPoint: NSPoint = .zero
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 10.0

    override var isFlipped: Bool { false }

    var isZoomed: Bool { zoomScale > 1.001 }

    func resetZoom() {
        zoomScale = 1.0
        panOffset = .zero
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }

        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        if isZoomed {
            // Draw zoomed: scale from center, offset by pan
            let scaledW = bounds.width * zoomScale
            let scaledH = bounds.height * zoomScale
            // Center the scaled image, then apply pan offset
            let x = (bounds.width - scaledW) / 2 + panOffset.x
            let y = (bounds.height - scaledH) / 2 + panOffset.y
            let drawRect = NSRect(x: x, y: y, width: scaledW, height: scaledH)
            image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        NSGraphicsContext.restoreGraphicsState()

        // Hairline border matching chat panel
        NSColor(white: 1, alpha: 0.06).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    /// Clamp pan offset so image edges don't pull away from window edges
    private func clampPan() {
        let scaledW = bounds.width * zoomScale
        let scaledH = bounds.height * zoomScale
        let maxPanX = max((scaledW - bounds.width) / 2, 0)
        let maxPanY = max((scaledH - bounds.height) / 2, 0)
        panOffset.x = min(max(panOffset.x, -maxPanX), maxPanX)
        panOffset.y = min(max(panOffset.y, -maxPanY), maxPanY)
    }

    // MARK: - Pinch to zoom

    override func magnify(with event: NSEvent) {
        if event.phase == .began {
            onZoomingChanged?(true)
        }

        let oldScale = zoomScale
        zoomScale = min(max(zoomScale * (1 + event.magnification), minZoom), maxZoom)

        if zoomScale > minZoom {
            // Adjust pan so zoom centers on cursor position
            let loc = convert(event.locationInWindow, from: nil)
            let centerX = bounds.midX
            let centerY = bounds.midY
            let dx = loc.x - centerX
            let dy = loc.y - centerY
            let ratio = zoomScale / oldScale
            panOffset.x = panOffset.x * ratio + dx * (1 - ratio)
            panOffset.y = panOffset.y * ratio + dy * (1 - ratio)
        } else {
            panOffset = .zero
        }

        clampPan()
        needsDisplay = true

        if event.phase == .ended || event.phase == .cancelled {
            onZoomingChanged?(false)
        }
    }

    // MARK: - Mouse handling

    /// Returns true if the point is near the window edge (resize zone)
    private func isInResizeZone(_ point: NSPoint) -> Bool {
        let b = bounds
        return point.x < resizeEdge || point.x > b.width - resizeEdge ||
               point.y < resizeEdge || point.y > b.height - resizeEdge
    }

    override func mouseDown(with event: NSEvent) {
        // Double-click resets zoom
        if event.clickCount == 2 {
            resetZoom()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if isInResizeZone(point) {
            super.mouseDown(with: event)
        } else if isZoomed {
            // Start panning
            isPanning = true
            lastDragPoint = event.locationInWindow
        } else {
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            let current = event.locationInWindow
            let dx = current.x - lastDragPoint.x
            let dy = current.y - lastDragPoint.y
            panOffset.x += dx
            panOffset.y += dy
            lastDragPoint = current
            clampPan()
            needsDisplay = true
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isPanning = false
        super.mouseUp(with: event)
    }

    // MARK: - Scroll to pan when zoomed

    override func scrollWheel(with event: NSEvent) {
        if isZoomed {
            panOffset.x += event.scrollingDeltaX
            panOffset.y -= event.scrollingDeltaY  // Cocoa Y is flipped vs scroll direction
            clampPan()
            needsDisplay = true
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - Image Viewer Panel

/// The image IS the window. Rounded corners clip the image pixels directly.
/// System shadow + hairline border for native feel. Close button on hover.
/// Resizable with aspect ratio locked. Draggable from interior.
/// Pinch-to-zoom + drag-to-pan when zoomed. Arrow keys navigate between images.
class ImageViewerPanel: GlimpsePanel {
    /// Reference to an image — either a file path or a data URL to decode
    enum ImageRef {
        case file(String)
        case dataUrl(String)
    }

    private var imageContentView: ImageContentView!
    private let closeButton = NSButton()
    private let counterLabel = NSTextField(labelWithString: "")
    private var counterContainer: NSView?
    private let ctaBar = NSView()
    private var scrollToButton = NSButton()
    private var viewInBoardButton = NSButton()

    /// Callbacks for CTA actions (wired by AppDelegate)
    var onScrollToImage: ((Int) -> Void)?
    var onViewInBoard: ((String?) -> Void)?

    /// All images in the current thread for arrow-key navigation
    private var imageList: [ImageRef] = []
    private var currentImageIndex: Int = 0
    /// Message indices parallel to imageList — maps image index → message index in thread
    var messageIndices: [Int] = []

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
        imageContentView.onZoomingChanged = { [weak self] zooming in
            guard let self else { return }
            let visible: CGFloat = self.isMouseInside ? 1 : 0
            self.closeButton.alphaValue = zooming ? 0 : visible
            self.counterContainer?.alphaValue = zooming ? 0 : (self.imageList.count > 1 ? visible : 0)
            self.ctaBar.alphaValue = zooming ? 0 : visible
        }
        contentView = imageContentView

        // Close button — frosted pill with white X, visible over any image content
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 8
        closeButton.layer?.backgroundColor = NSColor(red: 0.18, green: 0.17, blue: 0.22, alpha: 0.65).cgColor
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: NSColor(red: 0.95, green: 0.94, blue: 1.0, alpha: 0.92),
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
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

        // Brand-tinted overlay colors
        // Brand-tinted grey — warm enough to feel intentional, light enough to not feel like a black slab
        let overlayBg = NSColor(red: 0.18, green: 0.17, blue: 0.22, alpha: 0.65)
        let overlayText = NSColor(red: 0.95, green: 0.94, blue: 1.0, alpha: 0.92)

        // Counter — "1 of 5", bottom-right (container for vertical centering)
        let counterBg = NSView()
        counterBg.translatesAutoresizingMaskIntoConstraints = false
        counterBg.wantsLayer = true
        counterBg.layer?.cornerRadius = 8
        counterBg.layer?.backgroundColor = overlayBg.cgColor
        counterBg.alphaValue = 0
        imageContentView.addSubview(counterBg)
        self.counterContainer = counterBg

        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        counterLabel.isBezeled = false
        counterLabel.isEditable = false
        counterLabel.drawsBackground = false
        counterLabel.alignment = .center
        counterLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        counterLabel.textColor = overlayText
        counterBg.addSubview(counterLabel)

        NSLayoutConstraint.activate([
            counterBg.trailingAnchor.constraint(equalTo: imageContentView.trailingAnchor, constant: -8),
            counterBg.bottomAnchor.constraint(equalTo: imageContentView.bottomAnchor, constant: -8),
            counterBg.heightAnchor.constraint(equalToConstant: 22),
            counterBg.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            counterLabel.centerXAnchor.constraint(equalTo: counterBg.centerXAnchor),
            counterLabel.centerYAnchor.constraint(equalTo: counterBg.centerYAnchor),
            counterLabel.leadingAnchor.constraint(greaterThanOrEqualTo: counterBg.leadingAnchor, constant: 8),
            counterLabel.trailingAnchor.constraint(lessThanOrEqualTo: counterBg.trailingAnchor, constant: -8),
        ])

        // CTA bar — bottom-left
        ctaBar.translatesAutoresizingMaskIntoConstraints = false
        ctaBar.wantsLayer = true
        ctaBar.alphaValue = 0
        imageContentView.addSubview(ctaBar)
        NSLayoutConstraint.activate([
            ctaBar.leadingAnchor.constraint(equalTo: imageContentView.leadingAnchor, constant: 8),
            ctaBar.bottomAnchor.constraint(equalTo: imageContentView.bottomAnchor, constant: -8),
            ctaBar.heightAnchor.constraint(equalToConstant: 24),
        ])

        func configureCtaButton(_ btn: NSButton, title: String, accessibilityLabel: String, action: Selector) {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 8
            btn.layer?.backgroundColor = overlayBg.cgColor
            btn.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: overlayText,
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                ]
            )
            btn.target = self
            btn.action = action
            btn.setAccessibilityLabel(accessibilityLabel)
            btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }

        configureCtaButton(scrollToButton, title: " Find in chat ", accessibilityLabel: "Find this image in chat", action: #selector(handleScrollTo))
        configureCtaButton(viewInBoardButton, title: " All images ", accessibilityLabel: "View in image gallery", action: #selector(handleViewInBoard))

        let ctaStack = NSStackView(views: [scrollToButton, viewInBoardButton])
        ctaStack.translatesAutoresizingMaskIntoConstraints = false
        ctaStack.orientation = .horizontal
        ctaStack.spacing = 6
        ctaBar.addSubview(ctaStack)
        NSLayoutConstraint.activate([
            ctaStack.leadingAnchor.constraint(equalTo: ctaBar.leadingAnchor),
            ctaStack.trailingAnchor.constraint(equalTo: ctaBar.trailingAnchor),
            ctaStack.topAnchor.constraint(equalTo: ctaBar.topAnchor),
            ctaStack.bottomAnchor.constraint(equalTo: ctaBar.bottomAnchor),
        ])

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        imageContentView.addTrackingArea(trackingArea)
    }

    @objc private func handleScrollTo() {
        let msgIndex = currentImageIndex < messageIndices.count ? messageIndices[currentImageIndex] : currentImageIndex
        onScrollToImage?(msgIndex)
        closePanel()
    }

    @objc private func handleViewInBoard() {
        if !imageList.isEmpty, case .file(let path) = imageList[currentImageIndex] {
            onViewInBoard?(path)
        } else {
            onViewInBoard?(nil)
        }
        closePanel()
    }

    private func updateOverlayState() {
        let hasMultiple = imageList.count > 1
        if hasMultiple {
            counterLabel.stringValue = "\(currentImageIndex + 1) of \(imageList.count)"
            counterContainer?.isHidden = false
        } else {
            counterContainer?.isHidden = true
        }
        // Hide "All images" for unsaved data URL images
        if !imageList.isEmpty, case .dataUrl = imageList[currentImageIndex] {
            viewInBoardButton.isHidden = true
        } else {
            viewInBoardButton.isHidden = false
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 1
            if imageList.count > 1 { counterContainer?.animator().alphaValue = 1 }
            ctaBar.animator().alphaValue = 1
        }
        closeButton.layer?.backgroundColor = NSColor(red: 0.18, green: 0.17, blue: 0.22, alpha: 0.78).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            closeButton.animator().alphaValue = 0
            counterContainer?.animator().alphaValue = 0
            ctaBar.animator().alphaValue = 0
        }
        closeButton.layer?.backgroundColor = NSColor(red: 0.18, green: 0.17, blue: 0.22, alpha: 0.65).cgColor
    }

    /// Flash overlays briefly so users know controls exist, then fade out
    private func flashCloseButton() {
        closeButton.alphaValue = 1
        if imageList.count > 1 { counterContainer?.alphaValue = 1 }
        ctaBar.alphaValue = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.isMouseInside else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.closeButton.animator().alphaValue = 0
                self.counterContainer?.animator().alphaValue = 0
                self.ctaBar.animator().alphaValue = 0
            }
        }
    }

    func setImageList(_ list: [ImageRef], currentIndex: Int) {
        imageList = list
        currentImageIndex = max(0, min(currentIndex, list.count - 1))
    }

    @discardableResult
    func showImage(at path: String, animate: Bool = false) -> Bool {
        guard let image = NSImage(contentsOfFile: path) else {
            NSLog("[ImageViewer] Failed to load image: \(path)")
            return false
        }
        imageContentView.image = image
        imageContentView.resetZoom()
        resizeToFitImage(image, animate: animate)
        imageContentView.needsDisplay = true
        updateOverlayState()
        flashCloseButton()
        return true
    }

    /// Navigate to an image by index in the image list
    private func navigateToImage(at index: Int) {
        guard !imageList.isEmpty else { return }
        let newIndex = max(0, min(index, imageList.count - 1))
        guard newIndex != currentImageIndex else { return }
        currentImageIndex = newIndex
        imageContentView.resetZoom()

        switch imageList[newIndex] {
        case .file(let path):
            showImage(at: path, animate: true)
        case .dataUrl(let dataUrl):
            showImageFromDataUrl(dataUrl, animate: true)
        }
    }

    /// Load image from data URL (for navigation — no temp file needed, just decode to NSImage)
    private func showImageFromDataUrl(_ dataUrl: String, animate: Bool = false) {
        guard let commaIndex = dataUrl.firstIndex(of: ",") else { return }
        let base64 = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64),
              let image = NSImage(data: data) else {
            NSLog("[ImageViewer] Failed to decode data URL")
            return
        }
        imageContentView.image = image
        imageContentView.resetZoom()
        resizeToFitImage(image, animate: animate)
        imageContentView.needsDisplay = true
        updateOverlayState()
        flashCloseButton()
    }

    private func resizeToFitImage(_ image: NSImage, animate: Bool = false) {
        // Convert pixel dimensions to points using screen backing scale.
        // Default to 1.0 (non-Retina) so Intel Macs show images at natural size.
        let backingScale = NSScreen.main?.backingScaleFactor ?? 1.0
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

        // Preserve center point so window doesn't jump when navigating between images
        let oldCenter = NSPoint(x: frame.midX, y: frame.midY)
        var newX = oldCenter.x - w / 2
        var newY = oldCenter.y - h / 2

        // Clamp to screen bounds
        if let sf = screen?.frame ?? NSScreen.main?.frame {
            newX = max(sf.minX + 8, min(newX, sf.maxX - w - 8))
            newY = max(sf.minY + 8, min(newY, sf.maxY - h - 8))
        }

        let targetFrame = NSRect(x: newX, y: newY, width: w, height: h)

        if animate && abs(frame.width - w) + abs(frame.height - h) > 2 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(targetFrame, display: true)
            }
        } else {
            setFrame(targetFrame, display: true)
        }

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
        closeButton.layer?.cornerRadius = max(8 * scaleFactor, 3)

        let fontSize = max(12 * scaleFactor, 7)
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: NSColor(white: 1, alpha: 0.9),
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
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

        // Intel shadow fix: toggle hasShadow + invalidate + frame nudge at alpha=0,
        // then reveal after 200ms so Intel's compositor processes the shadow.
        // On Apple Silicon this is a no-op (shadow renders immediately).
        hasShadow = false
        hasShadow = true
        invalidateShadow()
        display()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let f = self.frame
            self.setFrame(NSRect(origin: f.origin, size: NSSize(width: f.width, height: f.height + 1)), display: true)
            self.invalidateShadow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setFrame(f, display: true)
                self.invalidateShadow()
            }
        }

        // Reveal after 200ms (Intel shadow needs time; Apple Silicon is instant)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.alphaValue = 1
            self.invalidateShadow()
        }

        flashCloseButton()
    }

    /// Track whether mouse is inside to avoid fading out during hover
    private var isMouseInside = false

    @objc private func closePanel() {
        orderOut(nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC
            closePanel()
        case 123: // Left arrow
            navigateToImage(at: currentImageIndex - 1)
        case 124: // Right arrow
            navigateToImage(at: currentImageIndex + 1)
        default:
            super.keyDown(with: event)
        }
    }
}
