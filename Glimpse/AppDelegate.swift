import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Timing Constants (hard-won values — see CLAUDE.md before changing)
    /// After Space switch, window positions need time to settle before capture
    private static let spaceSettleDelay: TimeInterval = 0.3
    /// Chat idle longer than this triggers a fresh thread on next open
    private static let chatStaleThreshold: TimeInterval = 5 * 60
    /// Delay before locking chat to current Space (canJoinAllSpaces → fullScreenAuxiliary)
    private static let spaceLockDelay: TimeInterval = 0.2
    /// Delay to restore activation policy after hiding (avoids Space switch)
    private static let activationPolicyRestoreDelay: TimeInterval = 0.1
    /// Safety timeout for overlayRendered callback from React
    private static let overlayRenderedTimeout: TimeInterval = 0.5
    /// Delay for React to render before dismissing frozen screen
    private static let frozenScreenDismissDelay: TimeInterval = 0.05
    /// Delay for thread data emit before pin swap
    private static let pinThreadEmitDelay: TimeInterval = 0.15
    /// Pin animation total duration
    private static let pinAnimationDuration: TimeInterval = 0.4
    /// Frame rate for custom Timer-based animations
    private static let animationFrameInterval: TimeInterval = 1.0 / 120

    var chatPanel: GlimpsePanel?
    var chatWebView: WKWebView?
    var ipcBridge = IPCBridge()
    var chatReady = false
    var isPinned = false
    var isChatShowing = false
    var pendingTextContext: String?
    var lastChatDismissTime: Date = .distantPast
    var lastChatSize: NSSize?
    var lastChatWasNewThread = true

    // Overlay (screenshot)
    var overlayPanel: GlimpsePanel?
    var overlayWebView: WKWebView?
    var overlayIPC: IPCBridge = { let b = IPCBridge(); b.bridgeId = "overlay"; return b }()
    var overlayReady = false
    var pendingCaptureResult: ScreenCapture.CaptureResult?
    var pendingSelection: [String: Any]?
    var frozenScreenWindow: NSWindow?
    var nativeSelectionOverlay: NativeSelectionOverlay?
    var lastSpaceChangeTime: Date = .distantPast
    var screenshotDeferPending = false
    var lastOverlayDismissTime: Date = .distantPast
    var overlayKeepThread = false
    var overlayWasNewThread = true
    private var spaceChangeSettleTime: TimeInterval { Self.spaceSettleDelay }

    // Welcome / onboarding
    var welcomePanel: GlimpsePanel?
    var welcomeWebView: WKWebView?
    var welcomeIPC = IPCBridge()
    /// True from first launch until `welcome_done` fires. Shortcuts reopen welcome instead of chat/overlay.
    var isOnboarding = false

    // Settings window
    var settingsPanel: GlimpsePanel?
    var settingsWebView: WKWebView?
    var settingsIPC = IPCBridge()

    static let screensaverLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))

    let settingsStore = SettingsStore()
    lazy var threadStore = ThreadStore(appSupportDir: settingsStore.appSupportDir)
    let aiService = AIService()
    let shortcutManager = ShortcutManager()
    let trayManager = TrayManager()
    let textGrabber = TextGrabber()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[App] Starting Glimpse (Swift)")
        registerBundledFonts()

        // Wire up stores
        ipcBridge.settingsStore = settingsStore
        ipcBridge.threadStore = threadStore
        ipcBridge.aiService = aiService

        overlayIPC.settingsStore = settingsStore
        overlayIPC.threadStore = threadStore
        overlayIPC.aiService = aiService

        welcomeIPC.settingsStore = settingsStore
        welcomeIPC.threadStore = threadStore
        welcomeIPC.aiService = aiService

        settingsIPC.settingsStore = settingsStore
        settingsIPC.threadStore = threadStore
        settingsIPC.aiService = aiService

        // Notifications
        setupMainMenu()

        NotificationCenter.default.addObserver(self, selector: #selector(handleCloseChatWindow), name: .closeChatWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChatReady), name: .chatReady, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleResizeChatWindow(_:)), name: .resizeChatWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTogglePin), name: .togglePin, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePinChat(_:)), name: .pinChat, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCloseOverlay), name: .closeOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOverlayReady), name: .overlayReady, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOverlayRendered), name: .overlayRendered, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLowerOverlay), name: .lowerOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRestoreOverlay), name: .restoreOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleInputFocus), name: .inputFocus, object: nil)

        // Global shortcuts
        shortcutManager.onChatShortcut = { [weak self] in self?.handleChatShortcut() }
        shortcutManager.onScreenshotShortcut = { [weak self] in self?.handleScreenshotShortcut() }
        shortcutManager.onEscape = { [weak self] in self?.handleEscape() }
        shortcutManager.start()

        // Tray icon
        trayManager.setup(threadStore: threadStore)
        trayManager.onScreenshot = { [weak self] in self?.handleScreenshotShortcut() }
        trayManager.onChat = { [weak self] in self?.handleChatShortcut() }
        trayManager.onSettings = { [weak self] in self?.showSettings() }
        trayManager.onOpenThread = { [weak self] threadId in self?.openThreadInChat(threadId) }

        NotificationCenter.default.addObserver(self, selector: #selector(handleRefreshTrayMenu), name: .refreshTrayMenu, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCloseWelcome), name: .closeWelcome, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWelcomeDone), name: .welcomeDone, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleSettings), name: .toggleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCloseSettings), name: .closeSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleProvidersChanged), name: .providersChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNewThreadCreated), name: .newThreadCreated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleConversationStarted), name: .chatConversationStarted, object: nil)

        // Track Space changes so screenshot shortcut can wait for transitions to settle
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )

        // First-launch: show welcome flow; else prewarm chat immediately
        let hasCompletedWelcome = UserDefaults.standard.bool(forKey: "hasCompletedWelcome")
        isOnboarding = !hasCompletedWelcome
        if isOnboarding {
            // Show dock icon during onboarding so the welcome window is discoverable
            NSApp.setActivationPolicy(.regular)
            showWelcome()
            // Prewarm chat silently so it's ready the moment onboarding completes
            prewarmChat()
        } else {
            // After onboarding: tray-only, no dock icon
            NSApp.setActivationPolicy(.accessory)
            prewarmChat()
        }
        prewarmOverlay()
    }

    // MARK: - Welcome Window

    func showWelcome() {
        // If already showing, just focus
        if let panel = welcomePanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = GlimpsePanel(size: NSSize(width: 440, height: 580))
        let webView = createWebView(in: panel, bridge: welcomeIPC, route: "#welcome")
        welcomeIPC.webView = webView

        // Match chat panel styling: shadow + rounded corners
        panel.hasShadow = true
        webView.layer?.cornerRadius = 20

        // Center on main screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.frame
        panel.setFrameOrigin(NSPoint(x: sf.midX - 220, y: sf.midY - 290))
        // Use .normal so system permission dialogs appear above the welcome window
        panel.level = .normal
        // isMovableByWindowBackground is set for discovery, but actual drag is handled
        // by swift-shim.js universal drag → _start_drag IPC → GlimpseWebView.startWindowDrag()
        // (NSEvent local monitor fallback when CGEventTap isn't installed yet)
        panel.isMovableByWindowBackground = true

        self.welcomePanel = panel
        self.welcomeWebView = webView

        // Show at alpha=0, reveal after WebView loads (prevents blank first frame)
        panel.alphaValue = 0
        panel.showAndFocus()
        updateVisibleWindowFlag()
        NSLog("[App] Welcome window shown (waiting for load)")
    }

    func hideWelcome() {
        if settingsPanel?.isVisible == true { hideSettings() }
        welcomePanel?.orderOut(nil)
        welcomePanel = nil
        welcomeWebView = nil
        updateVisibleWindowFlag()
        NSLog("[App] Welcome window closed")
    }

    @objc func handleCloseWelcome() {
        // User dismissed mid-flow — stay in onboarding mode.
        // Next shortcut will reopen welcome at the saved step (React localStorage).
        hideWelcome()
        NSLog("[App] Welcome dismissed mid-flow — onboarding continues")
    }

    @objc func handleWelcomeDone() {
        UserDefaults.standard.set(true, forKey: "hasCompletedWelcome")
        isOnboarding = false
        hideWelcome()
        // Switch to tray-only mode — remove dock icon
        NSApp.setActivationPolicy(.accessory)
        // Install event tap if accessibility was granted during welcome.
        // macOS may need a moment after granting accessibility before the tap works,
        // so retry a few times with short delays.
        shortcutManager.installEventTap()
        for delay in [0.5, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.shortcutManager.installEventTap()
            }
        }
        // Chat was prewarmed at launch — it's ready, just don't auto-show it.
        // User will trigger it via shortcut or tray.
        NSLog("[App] Welcome completed — onboarding done")
    }

    // MARK: - Settings Window

    func showSettings(panelBounds: [String: Any]? = nil) {
        if let panel = settingsPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let settingsSize = NSSize(width: 480, height: 540)
        let panel = GlimpsePanel(size: settingsSize)
        panel.hasShadow = true
        let webView = createWebView(in: panel, bridge: settingsIPC, route: "#settings")
        settingsIPC.webView = webView

        // If overlay is open, settings must float above it (screensaverLevel + 1)
        let fromOverlay = overlayPanel?.isVisible == true
        panel.level = fromOverlay
            ? NSWindow.Level(rawValue: Self.screensaverLevel.rawValue + 1)
            : .floating

        panel.setFrameOrigin(settingsOrigin(size: settingsSize, panelBounds: panelBounds, fromOverlay: fromOverlay))

        self.settingsPanel = panel
        self.settingsWebView = webView

        if fromOverlay {
            // Don't activate app — avoids Space switch; settings is already above overlay
            panel.orderFrontRegardless()
            panel.makeKey()
        } else {
            panel.showAndFocus()
        }
        updateVisibleWindowFlag()
        NSLog("[App] Settings shown (fromOverlay=\(fromOverlay))")
    }

    /// Position settings window adjacent to its caller, avoiding overlap.
    private func settingsOrigin(size: NSSize, panelBounds: [String: Any]?, fromOverlay: Bool) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.frame
        let fallback = NSPoint(x: sf.midX - size.width / 2, y: sf.midY - size.height / 2)

        // Source window frame in Cocoa coords (bottom-left origin)
        let sourceFrame: NSRect?
        if fromOverlay { sourceFrame = overlayPanel?.frame }
        else            { sourceFrame = chatPanel?.frame }

        guard let src = sourceFrame, let bounds = panelBounds else { return fallback }

        func f(_ k: String) -> CGFloat { (bounds[k] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0 }
        let cssX = f("x"); let cssY = f("y"); let cssW = f("w")

        // Convert CSS viewport (top-left origin) → Cocoa screen (bottom-left origin)
        let refLeft   = src.origin.x + cssX
        let refRight  = src.origin.x + cssX + cssW
        let refTop    = src.origin.y + src.height - cssY          // Cocoa y of CSS top edge

        // Prefer right side; fall back to left; then center
        var x = refRight + 8
        if x + size.width > sf.maxX { x = refLeft - size.width - 8 }
        if x < sf.minX              { x = sf.midX - size.width / 2 }

        // Align tops, then clamp vertically
        var y = refTop - size.height
        y = max(sf.minY + 8, min(y, sf.maxY - size.height - 8))

        return NSPoint(x: x, y: y)
    }

    func hideSettings() {
        settingsPanel?.orderOut(nil)
        settingsPanel = nil
        settingsWebView = nil
        updateVisibleWindowFlag()
        NSLog("[App] Settings closed")
    }

    @objc func handleToggleSettings(_ notification: Notification) {
        if let panel = settingsPanel, panel.isVisible {
            hideSettings()
        } else {
            let bounds = notification.userInfo?["panelBounds"] as? [String: Any]
            showSettings(panelBounds: bounds)
        }
    }

    @objc func handleCloseSettings() {
        hideSettings()
    }

    @objc func handleSpaceChange() {
        lastSpaceChangeTime = Date()
        NSLog("[App] Space changed at \(lastSpaceChangeTime)")
    }

    @objc func handleNewThreadCreated(_ notification: Notification) {
        let source = notification.userInfo?["source"] as? String ?? "main"
        if source == "overlay" {
            overlayWasNewThread = true
        } else {
            lastChatWasNewThread = true
        }
    }

    @objc func handleConversationStarted(_ notification: Notification) {
        let source = notification.userInfo?["source"] as? String ?? "main"
        if source == "overlay" {
            overlayWasNewThread = false
        } else {
            lastChatWasNewThread = false
        }
    }

    @objc func handleProvidersChanged() {
        // Notify all open WebViews so provider dropdowns refresh
        ipcBridge.emit("providers-changed")
        overlayIPC.emit("providers-changed")
    }

    // MARK: - Chat Panel

    func prewarmChat() {
        let panel = GlimpsePanel(size: NSSize(width: 380, height: 412))
        let webView = createWebView(
            in: panel,
            bridge: ipcBridge,
            route: "#chat-only"
        )

        ipcBridge.webView = webView
        panel.orderOut(nil)

        // Chat-specific styling: shadow + rounded corners (not for overlay).
        // cornerRadius 20 matches CSS .chat-only-inner.pinned (20px).
        // masksToBounds OFF so CSS outer box-shadow (brand glow) renders.
        panel.hasShadow = true
        webView.layer?.cornerRadius = 20

        self.chatPanel = panel
        self.chatWebView = webView
        NSLog("[App] Chat panel pre-warmed (hidden)")
    }

    private var isRecreatingForFullscreen = false
    private var onChatReadyAction: (() -> Void)? = nil  // custom action when chat WebView loads (for pin swap)

    func showChat() {
        let isFullscreen = SpaceDetector.isFullscreenSpace()

        // Fullscreen path: hidden windows are bound to their original Space.
        // Must destroy and recreate to associate with current fullscreen Space.
        // Also need Accessory policy so macOS doesn't switch Spaces when we show.
        if isFullscreen && !isRecreatingForFullscreen {
            if let panel = chatPanel, !isChatShowing {
                NSLog("[App] Fullscreen detected — recreating chat panel")
                panel.orderOut(nil)
                chatPanel = nil
                chatWebView = nil
                chatReady = false

                // Switch to Accessory policy — required for fullscreen Space windows
                NSApp.setActivationPolicy(.accessory)

                isRecreatingForFullscreen = true
                prewarmChat()
                // handleChatReady → showChat will be called again with isRecreatingForFullscreen=true
                return
            }
        }

        guard let panel = chatPanel else { return }
        isRecreatingForFullscreen = false

        // Position centered on cursor, clamped to screen bounds
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen = screen {
            let visible = screen.visibleFrame
            let panelSize = panel.frame.size
            let margin: CGFloat = 12

            // Center on cursor
            var x = mouseLocation.x - panelSize.width / 2
            var y = mouseLocation.y - panelSize.height / 2

            // Clamp to screen bounds with margin
            x = max(visible.minX + margin, min(x, visible.maxX - panelSize.width - margin))
            y = max(visible.minY + margin, min(y, visible.maxY - panelSize.height - margin))

            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Show with CanJoinAllSpaces for initial visibility on any Space
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Lightweight state resets (no React re-render)
        ipcBridge.emit("pin-state", data: isPinned)
        ipcBridge.emit("clear-screenshot")
        ipcBridge.emit("clear-text-context")

        // Decide chat size from Swift — avoids heavy JS check-size round-trip.
        // WebView still has previous React state (messages, thread), so within
        // 5 minutes we just restore the saved size. Beyond 5 min, reset to compact
        // and tell JS to start a new thread (lightweight, no message re-render).
        let isStale = Date().timeIntervalSince(lastChatDismissTime) >= Self.chatStaleThreshold
        let compactSize = NSSize(width: 380, height: 412)
        if isStale {
            // Stale — compact size, new thread
            panel.setFrame(NSRect(origin: panel.frame.origin, size: compactSize), display: false)
            ipcBridge.emit("start-new-thread")
            lastChatWasNewThread = true
        } else if lastChatWasNewThread {
            // Recent but was a new/empty thread — compact, fresh start
            panel.setFrame(NSRect(origin: panel.frame.origin, size: compactSize), display: false)
            ipcBridge.emit("start-new-thread")
        } else if let savedSize = lastChatSize {
            // Recent with conversation — restore saved size
            panel.setFrame(NSRect(origin: panel.frame.origin, size: savedSize), display: false)
        }

        // Floating only when pinned or on fullscreen (fullscreen needs floating to stay above)
        panel.level = (isPinned || isFullscreen) ? .floating : .normal

        // Emit text-context — queued via main.async like the other emits
        if let text = pendingTextContext {
            pendingTextContext = nil
            ipcBridge.emit("text-context", data: text)
        }

        // Show at alpha=0 — invisible but in compositor, WebKit paints.
        panel.alphaValue = 0

        if isFullscreen {
            panel.showOnFullscreen()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
            if let cv = panel.contentView { panel.makeFirstResponder(cv) }
        } else {
            panel.showAndFocus()
        }
        isChatShowing = true
        updateVisibleWindowFlag()

        // Reveal after emits have been dispatched. All emits use
        // DispatchQueue.main.async, so they run BEFORE this block (FIFO).
        // By the time alpha=1, evaluateJavaScript for text-context has been
        // called — React setState is synchronous within that JS execution,
        // so the DOM update completes before the next paint.
        DispatchQueue.main.async {
            panel.alphaValue = 1
        }
        NSLog("[App] Chat shown (fullscreen=\(isFullscreen), pinned=\(isPinned))")

        // After 200ms, lock to current Space (stop following across desktops)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.spaceLockDelay) { [weak self, weak panel] in
            guard let self, let panel, self.isChatShowing else { return }
            panel.collectionBehavior = [.fullScreenAuxiliary]
            NSLog("[App] Chat locked to current Space")
        }
    }

    func hideChat() {
        if settingsPanel?.isVisible == true { hideSettings() }
        guard let panel = chatPanel else { return }

        // Remember state for next showChat — avoids heavy JS work on re-show
        lastChatDismissTime = Date()
        lastChatSize = panel.frame.size

        // Clear transient state while WebView is still visible — by the next
        // showChat(), React will have already processed these, no stale flash.
        ipcBridge.emit("clear-text-context")
        ipcBridge.emit("clear-screenshot")

        // Fade out (80ms, ease-in) — keep window in compositor tree at alpha=0
        // instead of orderOut, so the backing store (IOSurface) stays in GPU memory.
        // Re-showing is then a pure alpha change with no compositor re-acquisition stall.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Move off-screen so invisible window doesn't intercept mouse events
            panel.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            self?.isChatShowing = false
            self?.isPinned = false
            self?.updateVisibleWindowFlag()
            self?.restoreActivationPolicyIfNeeded()
            NSApp.hide(nil)
            NSLog("[App] Chat hidden")
        })
    }

    func togglePin() {
        isPinned.toggle()
        NSLog("[App] Pin toggled: \(isPinned)")
        guard let panel = chatPanel else { return }
        panel.level = isPinned ? .floating : .normal
        ipcBridge.emit("pin-state", data: isPinned)

        // Lift/sink animation (350ms ease-out quintic)
        let liftAmount: CGFloat = isPinned ? 12 : -12
        let startY = panel.frame.origin.y
        let startTime = CACurrentMediaTime()
        let duration = 0.35
        Timer.scheduledTimer(withTimeInterval: Self.animationFrameInterval, repeats: true) { timer in
            let t = min((CACurrentMediaTime() - startTime) / duration, 1.0)
            let ease = 1.0 - pow(1.0 - t, 5)
            panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x, y: startY + liftAmount * ease))
            if t >= 1.0 { timer.invalidate() }
        }
    }

    // MARK: - Overlay Panel

    func prewarmOverlay() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let panel = GlimpsePanel(size: screen.frame.size)
        panel.level = Self.screensaverLevel
        panel.styleMask = [.borderless]

        let webView = createWebView(
            in: panel,
            bridge: overlayIPC,
            route: nil  // default route = overlay
        )

        overlayIPC.webView = webView
        panel.orderOut(nil)

        self.overlayPanel = panel
        self.overlayWebView = webView
        self.overlayReady = false
        NSLog("[App] Overlay panel pre-warmed (hidden)")
    }

    func showOverlay() {
        guard let panel = overlayPanel else { return }

        // Size to cursor's screen
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first!
        panel.setFrame(screen.frame, display: true)

        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = Self.screensaverLevel

        let isFullscreen = SpaceDetector.isFullscreenSpace()
        if isFullscreen {
            panel.showOnFullscreen()
            // Activate so mouse events reach WebView immediately (same fix as chat)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
            if let cv = panel.contentView { panel.makeFirstResponder(cv) }
        } else {
            panel.showAndFocus()
        }
        updateVisibleWindowFlag()
        NSLog("[App] Overlay shown (fullscreen=\(isFullscreen))")
    }

    func hideOverlay() {
        if settingsPanel?.isVisible == true { hideSettings() }
        dismissFrozenScreen()
        lastOverlayDismissTime = Date()
        overlayPanel?.orderOut(nil)
        updateVisibleWindowFlag()
        restoreActivationPolicyIfNeeded()
        NSLog("[App] Overlay hidden")
    }

    /// Update ShortcutManager's flag so ESC is consumed only when we have visible windows.
    private func updateVisibleWindowFlag() {
        shortcutManager.hasVisibleWindow =
            isChatShowing || (overlayPanel?.isVisible == true) ||
            (welcomePanel?.isVisible == true) || (settingsPanel?.isVisible == true) ||
            (frozenScreenWindow?.isVisible == true) || (nativeSelectionOverlay != nil)
    }

    /// Restore activation policy after fullscreen Space operations.
    /// Fullscreen path sets .accessory to avoid Space switch; this restores normal state.
    /// During onboarding we stay .regular (dock icon visible); after onboarding we go .accessory (tray only).
    private func restoreActivationPolicyIfNeeded() {
        guard NSApp.activationPolicy() == .accessory else { return }
        if isOnboarding {
            NSApp.hide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationPolicyRestoreDelay) {
                NSApp.setActivationPolicy(.regular)
            }
        }
        // After onboarding: already .accessory, nothing to do — stay tray-only
    }

    func emitCaptureToOverlay(_ result: ScreenCapture.CaptureResult) {
        overlayIPC.emit("screen-captured", data: [
            "imageURL": result.imageURL,
            "windowBounds": result.windowBounds,
            "displayInfo": result.displayInfo,
            "offset": result.offset,
            "cursorX": result.cursorX,
            "cursorY": result.cursorY
        ])
        NSLog("[App] Emitted screen-captured to overlay (cursor: \(result.cursorX),\(result.cursorY))")
    }

    // MARK: - Shortcut Handlers

    func handleChatShortcut() {
        // No Space-change defer for chat (unlike screenshot which needs accurate
        // window bounds). With always-open behavior, worst case is 2 presses:
        // first hides old + show may fail, second succeeds.

        // During onboarding: intercept — reopen/focus welcome and emit shortcut-tried
        if isOnboarding {
            welcomeIPC.emit("shortcut-tried", data: "chat")
            if welcomePanel?.isVisible != true { showWelcome() }
            return
        }

        // If any overlay is active (native selection or WebView), dismiss and switch to chat.
        if nativeSelectionOverlay != nil {
            dismissNativeSelection()
            pendingTextContext = nil
            showChat()
            return
        }
        if let panel = overlayPanel, panel.isVisible {
            overlayIPC.emit("reset-overlay")
            panel.orderOut(nil)
            updateVisibleWindowFlag()
            pendingTextContext = nil
            showChat()
            return
        }
        // If chat is showing, either refocus or re-quote.
        if let panel = chatPanel, isChatShowing {
            if panel.isKeyWindow {
                panel.makeKey()
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            // Chat visible but not key — user is in another app and wants to re-quote.
            // Synchronous hide (no fade) to avoid race: hideChat's async completion
            // would orderOut the panel AFTER showChat re-shows it.
            lastChatDismissTime = Date()
            lastChatSize = panel.frame.size
            ipcBridge.emit("clear-text-context")
            ipcBridge.emit("clear-screenshot")
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            isChatShowing = false
            isPinned = false
            updateVisibleWindowFlag()
        }

        // Grab selected text BEFORE showing chat (source app still has focus).
        // 1. Try AX API on main thread (instant, no beep) — works for most apps.
        // 2. If AX fails (e.g., Chrome), fall back to Cmd+C on background thread.
        //    Only fall back when AX FAILED, not when AX succeeded with empty text.
        if AXIsProcessTrusted() {
            switch textGrabber.grabViaAccessibility() {
            case .success(let text) where !text.isEmpty:
                pendingTextContext = text
                showChat()
            case .success, .noSelection:
                // AX reached the app, nothing selected — no Cmd+C, no beep
                pendingTextContext = nil
                showChat()
            case .appFailed:
                // AX couldn't reach app (e.g., Chrome) — Cmd+C fallback on background.
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let text = self?.textGrabber.grabViaCmdC()
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.pendingTextContext = (text?.isEmpty == false) ? text : nil
                        self.showChat()
                    }
                }
            }
        } else {
            pendingTextContext = nil
            showChat()
        }
    }

    func handleScreenshotShortcut() {
        NSLog("[App] Screenshot shortcut triggered")
        // During onboarding: intercept — reopen/focus welcome and emit shortcut-tried
        if isOnboarding {
            welcomeIPC.emit("shortcut-tried", data: "screenshot")
            if welcomePanel?.isVisible != true { showWelcome() }
            return
        }

        // If a Space transition happened recently, defer screenshot until
        // window positions have fully settled. Only one deferred retry at a time.
        let timeSinceSpaceChange = Date().timeIntervalSince(lastSpaceChangeTime)
        if timeSinceSpaceChange < spaceChangeSettleTime {
            if !screenshotDeferPending {
                screenshotDeferPending = true
                let remaining = spaceChangeSettleTime - timeSinceSpaceChange
                NSLog("[App] Space changed \(Int(timeSinceSpaceChange * 1000))ms ago — deferring by \(Int(remaining * 1000))ms")
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    self?.screenshotDeferPending = false
                    self?.handleScreenshotShortcut()
                }
            }
            return
        }

        // Toggle: if overlay visible, hide it
        if let panel = overlayPanel, panel.isVisible {
            hideOverlay()
            return
        }
        // Dismiss if native selection is active (toggle)
        if nativeSelectionOverlay != nil {
            dismissNativeSelection()
            return
        }

        // Hide chat before capture so it doesn't appear in the screenshot.
        let chatWasVisible = isChatShowing
        if chatWasVisible {
            chatPanel?.orderOut(nil)
            isPinned = false
        }

        let isFullscreen = SpaceDetector.isFullscreenSpace()

        // Prewarm WebView overlay in parallel (for post-selection annotations/chat)
        let overlayStale = Date().timeIntervalSince(lastOverlayDismissTime) >= Self.chatStaleThreshold
        overlayKeepThread = !overlayStale
        if overlayReady && !isFullscreen {
            overlayIPC.emit(overlayStale ? "reset-overlay" : "reset-overlay-keep-thread")
            overlayPanel?.orderOut(nil)
        } else {
            overlayPanel?.orderOut(nil)
            overlayPanel = nil
            overlayWebView = nil
            overlayReady = false
            if isFullscreen {
                NSApp.setActivationPolicy(.accessory)
            }
            prewarmOverlay()
        }

        // ── NATIVE SELECTION OVERLAY ──
        // Show native CAShapeLayer overlay for selection (zero WebKit overhead).
        // After selection completes, capture screen + hand off to WebView overlay.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first!

        // Get window bounds for hover/snap (same logic as ScreenCapture)
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgOriginX = screen.frame.origin.x
        let cgOriginY = mainHeight - screen.frame.origin.y - screen.frame.height
        let screenRect = CGRect(x: cgOriginX, y: cgOriginY, width: screen.frame.width, height: screen.frame.height)
        let windowBounds = ScreenCapture.getWindowBounds(on: screenRect)

        nativeSelectionOverlay = NativeSelectionOverlay.show(
            on: screen,
            windowBounds: windowBounds,
            completion: { [weak self] rect, bounds in
                self?.handleNativeSelectionComplete(rect, windowBounds: bounds)
            },
            dismiss: { [weak self] in
                self?.dismissNativeSelection()
            }
        )
        updateVisibleWindowFlag()
    }

    private func handleNativeSelectionComplete(_ selectionRect: CGRect, windowBounds: [[String: Any]]) {
        // Keep native overlay visible during capture — capture BELOW it so it doesn't
        // appear in the screenshot. This eliminates the flash during handoff.
        let nativeWindowID = CGWindowID(nativeSelectionOverlay?.overlayWindow?.windowNumber ?? 0)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Capture below the native overlay (excludes it from the screenshot)
            guard let result = ScreenCapture.capture(belowWindowID: nativeWindowID) else {
                NSLog("[App] Capture FAILED after native selection")
                return
            }
            NSLog("[App] Capture OK after native selection: \(result.windowBounds.count) windows")

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                let selectionData: [String: Any] = [
                    "x": Int(selectionRect.origin.x),
                    "y": Int(selectionRect.origin.y),
                    "w": Int(selectionRect.width),
                    "h": Int(selectionRect.height)
                ]

                if self.overlayReady {
                    // Emit data to HIDDEN WebView — JS executes on ordered-out windows.
                    // React renders invisibly while native overlay stays visible.
                    // React signals overlay_rendered → handleOverlayRendered does
                    // atomic swap: show WebView + dismiss native in same run loop.
                    self.overlayIPC.emit("screen-captured", data: [
                        "imageURL": result.imageURL,
                        "windowBounds": result.windowBounds,
                        "displayInfo": result.displayInfo,
                        "offset": result.offset,
                        "cursorX": result.cursorX,
                        "cursorY": result.cursorY,
                        "selection": selectionData,
                        "keepThread": self.overlayKeepThread,
                        "wasNewThread": self.overlayWasNewThread
                    ])
                    // Do NOT show overlay here — wait for overlayRendered callback.
                    // Safety timeout: if callback never fires, swap after 500ms anyway.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.overlayRenderedTimeout) { [weak self] in
                        guard let self, self.nativeSelectionOverlay != nil else { return }
                        NSLog("[App] overlayRendered safety timeout — forcing swap")
                        self.handleOverlayRendered()
                    }
                } else {
                    self.pendingCaptureResult = result
                    self.pendingSelection = selectionData
                }
            }
        }
    }

    private func dismissNativeSelection() {
        nativeSelectionOverlay?.dismiss()
        nativeSelectionOverlay = nil
        updateVisibleWindowFlag()
        restoreActivationPolicyIfNeeded()
    }

    /// Show a native frozen-screen window instantly using CGDisplayCreateImage.
    /// This reads the display framebuffer directly (~1-5ms) and shows an NSWindow
    /// with the snapshot, giving the user immediate visual feedback while the real
    /// capture + WebView loading happens behind it.
    private func showFrozenScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first!

        // Get display ID for CGDisplayCreateImage
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let cgImage = CGDisplayCreateImage(screenNumber) else {
            NSLog("[App] Frozen screen: CGDisplayCreateImage failed")
            return
        }

        let image = NSImage(cgImage: cgImage, size: screen.frame.size)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = Self.screensaverLevel
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = imageView
        window.orderFrontRegardless()

        frozenScreenWindow = window
        NSLog("[App] Frozen screen shown")
    }

    /// Dismiss the frozen screen window (called when overlay WebView is ready).
    private func dismissFrozenScreen() {
        guard frozenScreenWindow != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frozenScreenWindow?.orderOut(nil)
        frozenScreenWindow = nil
        CATransaction.commit()
        NSLog("[App] Frozen screen dismissed")
    }

    private func performCapture() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let result = ScreenCapture.capture() else {
                NSLog("[App] Capture FAILED")
                return
            }
            NSLog("[App] Capture OK: \(result.windowBounds.count) windows, \(result.displayInfo)")

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.overlayReady {
                    // WebView already loaded — show overlay and emit data
                    if self.overlayPanel?.isVisible != true {
                        self.showOverlay()
                    }
                    self.emitCaptureToOverlay(result)
                    // Delay frozen screen dismissal to let React render the new image.
                    // evaluateJavaScript is async — React needs ~1-2 frames to process.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.frozenScreenDismissDelay) { [weak self] in
                        self?.dismissFrozenScreen()
                    }
                } else {
                    // WebView still loading — store for handleOverlayReady
                    self.pendingCaptureResult = result
                }
            }
        }
    }

    func handleEscape() {
        // Settings always closes first (ESC highest priority)
        if let panel = settingsPanel, panel.isVisible { hideSettings(); return }
        // Native selection in progress, ESC cancels it
        if nativeSelectionOverlay != nil { dismissNativeSelection(); return }
        // Frozen screen = screenshot in progress, ESC cancels it
        if frozenScreenWindow != nil { dismissFrozenScreen(); return }
        if let panel = overlayPanel,  panel.isVisible { hideOverlay();  return }
        if isChatShowing { hideChat(); return }
        if let panel = welcomePanel,  panel.isVisible { hideWelcome() }
    }

    // MARK: - Notification Handlers

    @objc func handleTogglePin() {
        togglePin()
    }

    @objc func handleCloseChatWindow() {
        hideChat()
    }

    @objc func handleCloseOverlay() {
        hideOverlay()
    }

    @objc func handleRefreshTrayMenu() {
        trayManager.refreshMenu()
    }

    func openThreadInChat(_ threadId: String) {
        // Load thread data from store
        let threads = threadStore.getThreads()
        guard let thread = threads.first(where: { $0["id"] as? String == threadId }) else {
            NSLog("[App] Thread \(threadId) not found")
            return
        }
        showChat()
        // Emit thread data after chat is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pinThreadEmitDelay) { [weak self] in
            self?.ipcBridge.emit("load-thread-data", data: thread)
        }
    }

    @objc func handleChatReady() {
        chatReady = true
        NSLog("[App] Chat ready")
        // If a custom action is pending (e.g. pin swap), run it instead of showChat
        if let action = onChatReadyAction {
            onChatReadyAction = nil
            isRecreatingForFullscreen = false
            action()
        } else if !isOnboarding {
            // Don't auto-show during onboarding — user triggers via shortcut
            showChat()
        }
    }

    @objc func handlePinChat(_ notification: Notification) {
        let threadData = notification.userInfo?["threadData"] as? [String: Any]
        let bounds = notification.userInfo?["bounds"] as? [String: Any]

        // Capture overlay frame before any changes
        let overlayFrame = overlayPanel?.frame
        NSLog("[App] Pin chat: overlayFrame=\(overlayFrame.map { "\($0)" } ?? "nil"), hasBounds=\(bounds != nil)")

        // Compute target chat frame from overlay chat panel bounds.
        // bounds: CSS viewport coords (top-left origin, relative to overlay).
        // JSON numbers arrive as NSNumber.
        var pinFrame: NSRect? = nil
        if let bounds = bounds, let overlayFrame = overlayFrame, overlayFrame.height > 0 {
            func f(_ key: String) -> CGFloat {
                (bounds[key] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
            }
            let bx = f("x"); let by = f("y")
            let bw = f("width"); let bh = f("height")
            let screenX = overlayFrame.origin.x + bx
            // CSS y=0 is top of screen; Cocoa y=0 is bottom
            let screenY = overlayFrame.origin.y + overlayFrame.height - by - bh
            pinFrame = NSRect(x: screenX, y: screenY, width: bw, height: bh)
            NSLog("[App] Pin frame: CSS(\(bx),\(by),\(bw),\(bh)) → screen(\(screenX),\(screenY))")
        }

        isPinned = true

        let isFullscreen = SpaceDetector.isFullscreenSpace()

        // ── Seamless pin transition ──
        // Strategy: show chat at alpha=0 (invisible but WebKit paints), emit thread
        // data so React renders, then after ~150ms make chat visible + hide overlay.
        // During the wait, overlay stays fully visible — user sees no gap.

        // Closure: given a ready panel, pre-load content at alpha=0, then swap
        let prepareAndSwap: (GlimpsePanel) -> Void = { [weak self] panel in
            guard let self else { return }

            // 1. Emit thread data + pin state to chat (JS runs even at alpha=0)
            if let threadData = threadData {
                self.ipcBridge.emit("load-thread-data", data: threadData)
            }
            self.ipcBridge.emit("pin-state", data: true)

            // 2. Show chat at alpha=0 above overlay (invisible, but WebKit paints)
            panel.alphaValue = 0
            if let frame = pinFrame {
                panel.setFrame(frame, display: false)
            }
            panel.level = Self.screensaverLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if isFullscreen {
                panel.showOnFullscreen()
            } else {
                panel.orderFrontRegardless()
            }
            panel.makeKey()

            // 3. After React renders (~150ms), reveal chat + fade overlay
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pinThreadEmitDelay) { [weak self] in
                guard let self, let panel = self.chatPanel else { return }

                // Show chat
                panel.alphaValue = 1
                panel.level = .floating
                self.isChatShowing = true
                self.updateVisibleWindowFlag()
                if !isFullscreen {
                    NSApp.activate(ignoringOtherApps: true)
                }

                // Fade overlay out (250ms) while CSS transitions run
                let overlayPanel = self.overlayPanel
                let fadeStart = CACurrentMediaTime()
                let fadeDuration = 0.25
                Timer.scheduledTimer(withTimeInterval: Self.animationFrameInterval, repeats: true) { [weak self] timer in
                    let t = min((CACurrentMediaTime() - fadeStart) / fadeDuration, 1.0)
                    overlayPanel?.alphaValue = CGFloat(1.0 - t)
                    if t >= 1.0 {
                        timer.invalidate()
                        overlayPanel?.orderOut(nil)
                        overlayPanel?.alphaValue = 1  // reset for next use
                        self?.overlayIPC.emit("reset-overlay")
                    }
                }

                // Lift animation (300ms ease-out quintic)
                let liftStart = CACurrentMediaTime()
                let liftDuration = 0.3
                let liftAmount: CGFloat = 12
                let startY = panel.frame.origin.y
                Timer.scheduledTimer(withTimeInterval: Self.animationFrameInterval, repeats: true) { timer in
                    let t = min((CACurrentMediaTime() - liftStart) / liftDuration, 1.0)
                    let ease = 1.0 - pow(1.0 - t, 5)
                    panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x, y: startY + liftAmount * ease))
                    if t >= 1.0 { timer.invalidate() }
                }

                // Lock to current Space after transition
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.pinAnimationDuration) { [weak panel] in
                    guard let panel, panel.isVisible else { return }
                    panel.collectionBehavior = [.fullScreenAuxiliary]
                }
            }
        }

        if !isFullscreen, let panel = chatPanel {
            // ── Non-fullscreen: panel already exists, swap immediately ──
            prepareAndSwap(panel)

        } else {
            // ── Fullscreen: must recreate panel for Space association ──
            // Keep overlay visible until new WebView is loaded + content rendered.
            chatPanel?.orderOut(nil)
            chatPanel = nil
            chatWebView = nil
            chatReady = false
            NSApp.setActivationPolicy(.accessory)
            isRecreatingForFullscreen = true

            onChatReadyAction = { [weak self] in
                guard let self, let panel = self.chatPanel else { return }
                prepareAndSwap(panel)
            }

            prewarmChat()
        }
    }

    @objc func handleOverlayReady() {
        overlayReady = true
        NSLog("[App] Overlay ready")
        if let result = pendingCaptureResult {
            pendingCaptureResult = nil
            // Emit data then show WebView BEHIND native overlay for painting.
            if let sel = pendingSelection {
                pendingSelection = nil
                overlayIPC.emit("screen-captured", data: [
                    "imageURL": result.imageURL,
                    "windowBounds": result.windowBounds,
                    "displayInfo": result.displayInfo,
                    "offset": result.offset,
                    "cursorX": result.cursorX,
                    "cursorY": result.cursorY,
                    "selection": sel
                ])
            } else {
                emitCaptureToOverlay(result)
            }
            // Do NOT show overlay here — wait for overlayRendered callback.
            // Safety timeout for fullscreen path too.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.overlayRenderedTimeout) { [weak self] in
                guard let self, self.nativeSelectionOverlay != nil else { return }
                NSLog("[App] overlayRendered safety timeout (fullscreen) — forcing swap")
                self.handleOverlayRendered()
            }
        }
    }

    @objc func handleOverlayRendered() {
        // Idempotent — may fire multiple times (image onload + safety timeout)
        guard nativeSelectionOverlay != nil || frozenScreenWindow != nil else { return }

        dismissFrozenScreen()

        // React has rendered + image decoded. Atomic swap:
        // show WebView overlay + dismiss native in one run loop iteration.
        showOverlay()
        nativeSelectionOverlay?.dismiss()
        nativeSelectionOverlay = nil
        updateVisibleWindowFlag()
        NSLog("[App] Overlay rendered — atomic swap complete")
    }

    @objc func handleLowerOverlay() {
        overlayPanel?.level = .normal
        NSLog("[App] Overlay lowered")
    }

    @objc func handleRestoreOverlay() {
        overlayPanel?.level = Self.screensaverLevel
        NSLog("[App] Overlay restored")
    }

    @objc func handleInputFocus() {
        overlayPanel?.makeKey()
    }

    private var resizeTimer: Timer?

    @objc func handleResizeChatWindow(_ notification: Notification) {
        guard let panel = chatPanel,
              let size = notification.userInfo,
              let width = size["width"] as? CGFloat ?? (size["width"] as? Int).map({ CGFloat($0) }),
              let height = size["height"] as? CGFloat ?? (size["height"] as? Int).map({ CGFloat($0) })
        else { return }

        let currentFrame = panel.frame

        // Clamp to screen
        var clampedHeight = height
        var clampedWidth = width
        if let screen = panel.screen {
            let visible = screen.visibleFrame
            clampedHeight = min(height, visible.height * 0.75)
            clampedWidth = min(width, visible.width)
        }

        // Smart anchor: choose bottom-anchor (grow up) or top-anchor (grow down)
        // based on available space. Whichever direction has more room wins.
        let dy = clampedHeight - currentFrame.height
        var targetY = currentFrame.origin.y
        if let screen = panel.screen {
            let visible = screen.visibleFrame
            let roomAbove = visible.maxY - currentFrame.maxY
            let roomBelow = currentFrame.origin.y - visible.minY

            if roomAbove >= dy {
                // Enough space above — bottom-anchor (grow upward, input stays)
                targetY = currentFrame.origin.y
                clampedHeight = min(clampedHeight, currentFrame.origin.y + clampedHeight <= visible.maxY
                    ? clampedHeight : visible.maxY - currentFrame.origin.y)
            } else if roomBelow >= dy {
                // Not enough above but enough below — top-anchor (grow downward)
                targetY = currentFrame.origin.y - dy
                targetY = max(targetY, visible.minY)
                clampedHeight = min(clampedHeight, currentFrame.maxY - visible.minY)
            } else {
                // Limited space both ways — grow toward whichever has more room
                if roomAbove >= roomBelow {
                    // Bottom-anchor, clamp to screen top
                    targetY = currentFrame.origin.y
                    clampedHeight = min(clampedHeight, visible.maxY - currentFrame.origin.y)
                } else {
                    // Top-anchor, clamp to screen bottom
                    targetY = max(currentFrame.origin.y - dy, visible.minY)
                    clampedHeight = min(clampedHeight, currentFrame.maxY - visible.minY)
                }
            }
        }

        let targetFrame = NSRect(
            x: currentFrame.origin.x,
            y: targetY,
            width: clampedWidth,
            height: clampedHeight
        )

        // No-op if already at target size — resolve immediately
        if abs(currentFrame.width - clampedWidth) < 1 && abs(currentFrame.height - clampedHeight) < 1 {
            chatWebView?.evaluateJavaScript("window._onResizeComplete && window._onResizeComplete()")
            return
        }

        // Check for instant (non-animated) resize — used when restoring existing chat
        // JS booleans arrive as NSNumber via WebKit IPC
        let animate: Bool = {
            if let b = size["animate"] as? Bool { return b }
            if let n = size["animate"] as? NSNumber { return n.boolValue }
            return true
        }()
        if !animate {
            panel.setFrame(targetFrame, display: true)
            NSLog("[App] Chat resized instantly to \(Int(clampedWidth))×\(Int(clampedHeight))")
            return
        }

        // Smooth resize animation (400ms, ease-out)
        // Slower = smaller per-frame displacement = WebKit's 1-3 frame lag less visible
        resizeTimer?.invalidate()
        let startFrame = currentFrame
        let startTime = CACurrentMediaTime()
        let duration = 0.4

        resizeTimer = Timer(timeInterval: Self.animationFrameInterval, repeats: true) { [weak self] timer in
            let elapsed = CACurrentMediaTime() - startTime
            let t = min(elapsed / duration, 1.0)

            // ease-out quintic: 1 - (1-t)^5
            // Aggressive deceleration — last 50% of time covers only ~3% of distance.
            // WebKit content lag becomes invisible at the tail where movement is minimal.
            let ease = 1.0 - t
            let progress = 1.0 - ease * ease * ease * ease * ease

            let x = startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * progress
            let y = startFrame.origin.y + (targetFrame.origin.y - startFrame.origin.y) * progress
            let w = startFrame.width + (targetFrame.width - startFrame.width) * progress
            let h = startFrame.height + (targetFrame.height - startFrame.height) * progress
            panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)

            if t >= 1.0 {
                timer.invalidate()
                self?.resizeTimer = nil
                panel.setFrame(targetFrame, display: true)
                // Notify JS that resize completed
                self?.chatWebView?.evaluateJavaScript("window._onResizeComplete && window._onResizeComplete()")
            }
        }
        RunLoop.main.add(resizeTimer!, forMode: .common)
        NSLog("[App] Chat resizing to \(Int(clampedWidth))×\(Int(clampedHeight))")
    }

    // MARK: - Menu

    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Glimpse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (required for Cmd+C/V/X/A in WKWebView)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        // Redo uses Cmd+Shift+Z in standard apps, but that's our screenshot shortcut.
        // Remove the key equivalent to prevent conflict/beep.
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "")
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Shortcut menu — hidden menu items that serve as fallback when CGEventTap
        // isn't available (no accessibility permission). Prevents system beep.
        let shortcutMenu = NSMenu(title: "Shortcuts")
        let chatItem = NSMenuItem(title: "Chat", action: #selector(menuChatShortcut), keyEquivalent: "x")
        chatItem.keyEquivalentModifierMask = [.command, .shift]
        shortcutMenu.addItem(chatItem)
        let screenshotItem = NSMenuItem(title: "Screenshot", action: #selector(menuScreenshotShortcut), keyEquivalent: "z")
        screenshotItem.keyEquivalentModifierMask = [.command, .shift]
        shortcutMenu.addItem(screenshotItem)
        let shortcutMenuItem = NSMenuItem()
        shortcutMenuItem.submenu = shortcutMenu
        mainMenu.addItem(shortcutMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func menuChatShortcut() {
        handleChatShortcut()
    }

    @objc func menuScreenshotShortcut() {
        handleScreenshotShortcut()
    }

    // MARK: - Bundled Fonts

    private func registerBundledFonts() {
        // Register Outfit variable font for native UI (toast, selection HUD)
        if let fontURL = Bundle.main.url(forResource: "Outfit-Variable", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
            NSLog("[App] Registered Outfit font")
        }
        #if DEBUG
        // Dev fallback
        let devPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("fonts/Outfit-Variable.ttf")
        if FileManager.default.fileExists(atPath: devPath.path) {
            CTFontManagerRegisterFontsForURL(devPath as CFURL, .process, nil)
            NSLog("[App] Registered Outfit font (dev path)")
        }
        #endif
    }

    // MARK: - Resource Loading

    /// Create a WKWebView wired to a panel with IPC bridge, shim, and optional route.
    func createWebView(in panel: GlimpsePanel, bridge: IPCBridge, route: String?) -> GlimpseWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let userContent = config.userContentController

        userContent.add(bridge, name: "glimpse")

        if let route = route {
            userContent.addUserScript(WKUserScript(
                source: "window._glimpseRoute = '\(route)';",
                injectionTime: .atDocumentStart, forMainFrameOnly: true
            ))
        }

        if let shimCode = loadShimJS() {
            userContent.addUserScript(WKUserScript(
                source: shimCode,
                injectionTime: .atDocumentStart, forMainFrameOnly: true
            ))
        }

        let webView = GlimpseWebView(frame: panel.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self

        panel.contentView = webView
        webView.wantsLayer = true

        if let distURL = findDistURL() {
            let indexURL = distURL.appendingPathComponent("index.html")
            // Allow read access to root so WebView can load file:// URLs for screenshots in /tmp
            webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } else {
            NSLog("[App] ERROR: dist/index.html not found!")
        }

        return webView
    }

    func loadShimJS() -> String? {
        // Bundle (production)
        if let url = Bundle.main.url(forResource: "swift-shim", withExtension: "js", subdirectory: "Glimpse"),
           let code = try? String(contentsOf: url, encoding: .utf8) {
            return code
        }
        #if DEBUG
        // Dev fallback: next to source file
        let devPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("swift-shim.js")
        if let code = try? String(contentsOf: devPath, encoding: .utf8) {
            NSLog("[App] Loaded shim from dev path")
            return code
        }
        #endif
        NSLog("[App] WARNING: swift-shim.js not found!")
        return nil
    }

    func findDistURL() -> URL? {
        // .app bundle
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist") {
            return url.deletingLastPathComponent()
        }
        #if DEBUG
        // SPM dev mode: relative to source file
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = sourceDir.deletingLastPathComponent()
        let devDist = projectRoot.appendingPathComponent("dist")
        if FileManager.default.fileExists(atPath: devDist.appendingPathComponent("index.html").path) {
            return devDist
        }
        // SPM dev mode: relative to executable
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let execRoot = execURL
            .deletingLastPathComponent()  // debug/
            .deletingLastPathComponent()  // .build/
            .deletingLastPathComponent()  // project root
        let execDist = execRoot.appendingPathComponent("dist")
        if FileManager.default.fileExists(atPath: execDist.appendingPathComponent("index.html").path) {
            return execDist
        }
        #endif
        return nil
    }

    // MARK: - App Lifecycle

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if isOnboarding { showWelcome() } else { showChat() }
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Try installing event tap on every activation — catches the case where
        // accessibility was granted in System Settings while app was running
        shortcutManager.installEventTap()
    }
}

// MARK: - WKNavigationDelegate
extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("[App] WebView loaded: \(webView.url?.absoluteString ?? "nil")")
        // Welcome WebView loaded — reveal window
        if webView === welcomeWebView {
            DispatchQueue.main.async { [weak self] in
                self?.welcomePanel?.alphaValue = 1
                NSLog("[App] Welcome revealed")
            }
        }
        // Overlay WebView ready — React renders on next frame
        if webView === overlayWebView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                self.overlayReady = true
                NSLog("[App] Overlay ready (didFinish + 100ms)")
                if let result = self.pendingCaptureResult {
                    self.pendingCaptureResult = nil
                    if self.overlayPanel?.isVisible != true {
                        self.showOverlay()
                    }
                    self.emitCaptureToOverlay(result)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[App] WebView load failed: \(error)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[App] WebView process terminated — reloading")
        webView.reload()
    }
}
