import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var chatPanel: GlimpsePanel?
    var chatWebView: WKWebView?
    var ipcBridge = IPCBridge()
    var chatReady = false
    var isPinned = false

    // Overlay (screenshot)
    var overlayPanel: GlimpsePanel?
    var overlayWebView: WKWebView?
    var overlayIPC = IPCBridge()
    var overlayReady = false
    var pendingCaptureResult: ScreenCapture.CaptureResult?

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

        // First-launch: show welcome flow; else prewarm chat immediately
        let hasCompletedWelcome = UserDefaults.standard.bool(forKey: "hasCompletedWelcome")
        isOnboarding = !hasCompletedWelcome
        if isOnboarding {
            showWelcome()
            // Prewarm chat silently so it's ready the moment onboarding completes
            prewarmChat()
        } else {
            prewarmChat()
        }
        prewarmOverlay()
    }

    // MARK: - Welcome Window

    func showWelcome() {
        let panel = GlimpsePanel(size: NSSize(width: 440, height: 580))
        let webView = createWebView(in: panel, bridge: welcomeIPC, route: "#welcome")
        welcomeIPC.webView = webView

        // Center on main screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.frame
        panel.setFrameOrigin(NSPoint(x: sf.midX - 220, y: sf.midY - 290))
        panel.level = .floating

        self.welcomePanel = panel
        self.welcomeWebView = webView

        panel.showAndFocus()
        updateVisibleWindowFlag()
        NSLog("[App] Welcome window shown")
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
        let cssX = f("x"); let cssY = f("y"); let cssW = f("w"); let cssH = f("h")

        // Convert CSS viewport (top-left origin) → Cocoa screen (bottom-left origin)
        let refLeft   = src.origin.x + cssX
        let refRight  = src.origin.x + cssX + cssW
        let refTop    = src.origin.y + src.height - cssY          // Cocoa y of CSS top edge
        _ = src.origin.y + src.height - cssY - cssH   // refBottom (unused — kept for reference)

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

    @objc func handleProvidersChanged() {
        // Notify all open WebViews so provider dropdowns refresh
        ipcBridge.emit("providers-changed")
        overlayIPC.emit("providers-changed")
    }

    // MARK: - Chat Panel

    func prewarmChat() {
        let panel = GlimpsePanel(size: NSSize(width: 432, height: 412))
        let webView = createWebView(
            in: panel,
            bridge: ipcBridge,
            route: "#chat-only"
        )

        ipcBridge.webView = webView
        panel.orderOut(nil)

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
            if let panel = chatPanel, !panel.isVisible {
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

        // Center on cursor's screen
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen = screen {
            let frame = screen.visibleFrame
            let panelSize = panel.frame.size
            let x = frame.midX - panelSize.width / 2
            let y = frame.midY - panelSize.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Show with CanJoinAllSpaces for initial visibility on any Space
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Reset frontend state BEFORE showing — clear stale screenshot, pin, and
        // text-context from previous session. JS runs on hidden WebView so React
        // updates DOM before window is visible. No flash.
        ipcBridge.emit("pin-state", data: isPinned)
        ipcBridge.emit("clear-screenshot")
        ipcBridge.emit("clear-text-context")

        // Floating only when pinned or on fullscreen (fullscreen needs floating to stay above)
        panel.level = (isPinned || isFullscreen) ? .floating : .normal

        if isFullscreen {
            panel.showOnFullscreen()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
            if let cv = panel.contentView { panel.makeFirstResponder(cv) }
        } else {
            panel.showAndFocus()
        }
        updateVisibleWindowFlag()
        NSLog("[App] Chat shown (fullscreen=\(isFullscreen), pinned=\(isPinned))")

        // After 200ms, lock to current Space (stop following across desktops)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak panel] in
            guard let panel, panel.isVisible else { return }
            panel.collectionBehavior = [.fullScreenAuxiliary]
            NSLog("[App] Chat locked to current Space")
        }
    }

    func hideChat() {
        if settingsPanel?.isVisible == true { hideSettings() }
        chatPanel?.orderOut(nil)
        isPinned = false  // Reset pin state so next session starts in sync with frontend
        updateVisibleWindowFlag()
        restoreActivationPolicyIfNeeded()
        NSLog("[App] Chat hidden")
    }

    func togglePin() {
        isPinned.toggle()
        NSLog("[App] Pin toggled: \(isPinned)")
        if let panel = chatPanel {
            panel.level = isPinned ? .floating : .normal
        }
        // Notify frontend
        ipcBridge.emit("pin-state", data: isPinned)
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
        // Reset BEFORE orderOut — JS won't execute on hidden WebViews
        overlayIPC.emit("reset-overlay")
        overlayPanel?.orderOut(nil)
        updateVisibleWindowFlag()
        restoreActivationPolicyIfNeeded()
        NSLog("[App] Overlay hidden")
    }

    /// Update ShortcutManager's flag so ESC is consumed only when we have visible windows.
    private func updateVisibleWindowFlag() {
        shortcutManager.hasVisibleWindow =
            (chatPanel?.isVisible == true) || (overlayPanel?.isVisible == true) ||
            (welcomePanel?.isVisible == true) || (settingsPanel?.isVisible == true)
    }

    /// Restore Regular activation policy after showing windows on fullscreen Spaces.
    /// Uses hide-then-restore pattern to avoid Space switch.
    private func restoreActivationPolicyIfNeeded() {
        guard NSApp.activationPolicy() == .accessory else { return }
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func emitCaptureToOverlay(_ result: ScreenCapture.CaptureResult) {
        overlayIPC.emit("screen-captured", data: [
            "dataUrl": result.dataUrl,
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
        // During onboarding: intercept — reopen/focus welcome and emit shortcut-tried
        if isOnboarding {
            welcomeIPC.emit("shortcut-tried", data: "chat")
            if welcomePanel?.isVisible != true { showWelcome() }
            return
        }

        // If overlay visible, dismiss it and switch to chat.
        // (text grab not attempted when switching from overlay)
        // Reset BEFORE orderOut so JS executes while WebView is still visible.
        if let panel = overlayPanel, panel.isVisible {
            overlayIPC.emit("reset-overlay")
            panel.orderOut(nil)
            updateVisibleWindowFlag()
            showChat()
            return
        }
        if let panel = chatPanel, panel.isVisible {
            hideChat()
            return
        }

        // Open chat — grab selected text first if Accessibility is granted.
        // CGEvent Cmd+C is sent while the source app still has focus (~10ms).
        // showChat() is called after grab completes on main thread.
        if AXIsProcessTrusted() {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let text = self?.textGrabber.grabSelectedTextSync()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.showChat()
                    if let text, !text.isEmpty {
                        // Short delay: chat WebView must be visible before receiving event
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.ipcBridge.emit("text-context", data: text)
                        }
                    }
                }
            }
        } else {
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

        // Toggle: if overlay visible, hide it
        if let panel = overlayPanel, panel.isVisible {
            hideOverlay()
            return
        }

        // Hide chat before capture so it doesn't appear in the screenshot.
        // Just orderOut — don't call hideChat() which does NSApp.hide (causes flash).
        let chatWasVisible = chatPanel?.isVisible == true
        if chatWasVisible {
            chatPanel?.orderOut(nil)
            isPinned = false
        }

        let isFullscreen = SpaceDetector.isFullscreenSpace()

        // Always destroy and recreate overlay for guaranteed clean state.
        // Reusing the WebView causes stale React state (accumulated dark masks,
        // old screenshots) because emit("reset-overlay") is async and can't
        // reliably clear state before the window becomes visible.
        overlayPanel?.orderOut(nil)
        overlayPanel = nil
        overlayWebView = nil
        overlayReady = false
        if isFullscreen {
            NSApp.setActivationPolicy(.accessory)
        }
        prewarmOverlay()

        // Capture in parallel with WebView loading.
        // If chat was visible, wait 200ms for compositor to remove it.
        let compositorDelay = chatWasVisible ? 0.2 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + compositorDelay) { [weak self] in
            self?.performCapture()
        }
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
        if let panel = overlayPanel,  panel.isVisible { hideOverlay();  return }
        if let panel = chatPanel,     panel.isVisible { hideChat();     return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
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

            // 3. After React renders (~150ms), reveal chat + hide overlay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, let panel = self.chatPanel else { return }

                // Atomic visual swap: chat becomes visible, overlay hides
                panel.alphaValue = 1
                self.overlayPanel?.orderOut(nil)
                self.overlayIPC.emit("reset-overlay")

                // Restore to floating level
                panel.level = .floating
                if !isFullscreen {
                    NSApp.activate(ignoringOtherApps: true)
                }

                // Lock to current Space after swap
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak panel] in
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
            // Show overlay now that WebView is loaded, then emit data
            showOverlay()
            emitCaptureToOverlay(result)
        }
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

    @objc func handleResizeChatWindow(_ notification: Notification) {
        guard let panel = chatPanel,
              let size = notification.userInfo,
              let width = size["width"] as? CGFloat ?? (size["width"] as? Int).map({ CGFloat($0) }),
              let height = size["height"] as? CGFloat ?? (size["height"] as? Int).map({ CGFloat($0) })
        else { return }

        let currentFrame = panel.frame
        // Grow upward (keep bottom-left corner, adjust origin.y)
        let dy = height - currentFrame.height
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y - dy,
            width: width,
            height: height
        )
        panel.setFrame(newFrame, display: true, animate: true)
        NSLog("[App] Chat resized to \(Int(width))×\(Int(height))")
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
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
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

        if let distURL = findDistURL() {
            let indexURL = distURL.appendingPathComponent("index.html")
            webView.loadFileURL(indexURL, allowingReadAccessTo: distURL)
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
}

// MARK: - WKNavigationDelegate
extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("[App] WebView loaded: \(webView.url?.absoluteString ?? "nil")")
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
