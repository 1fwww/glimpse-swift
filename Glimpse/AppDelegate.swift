import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var chatPanel: GlimpsePanel?
    var chatWebView: WKWebView?
    var ipcBridge = IPCBridge()
    var chatReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[App] Starting Glimpse (Swift)")

        // Listen for chat events
        NotificationCenter.default.addObserver(self, selector: #selector(handleCloseChatWindow), name: .closeChatWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleChatReady), name: .chatReady, object: nil)

        // Pre-warm chat panel on main thread (WKWebView requires main thread)
        DispatchQueue.main.async { [weak self] in
            self?.prewarmChat()
        }
    }

    // MARK: - Chat Panel

    func prewarmChat() {
        let panel = GlimpsePanel(size: NSSize(width: 432, height: 412))

        // Create WKWebView with IPC bridge
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled") // DevTools
        // Allow file access for ES modules (type="module" scripts need this)
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let userContent = config.userContentController

        // Register IPC bridge
        userContent.add(ipcBridge, name: "glimpse")

        // Set route before any scripts run
        let routeScript = WKUserScript(source: "window._glimpseRoute = '#chat-only';", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userContent.addUserScript(routeScript)

        // Inject swift-shim.js before any page scripts run
        if let shimURL = Bundle.main.url(forResource: "swift-shim", withExtension: "js", subdirectory: "Glimpse"),
           let shimCode = try? String(contentsOf: shimURL) {
            let script = WKUserScript(source: shimCode, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            userContent.addUserScript(script)
        } else {
            // Fallback: try relative path in dev
            let devPath = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("swift-shim.js")
            if let shimCode = try? String(contentsOf: devPath) {
                let script = WKUserScript(source: shimCode, injectionTime: .atDocumentStart, forMainFrameOnly: true)
                userContent.addUserScript(script)
                NSLog("[App] Loaded shim from dev path")
            } else {
                NSLog("[App] WARNING: swift-shim.js not found!")
            }
        }

        let webView = WKWebView(frame: panel.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]

        ipcBridge.webView = webView
        panel.contentView = webView

        // Load the built React frontend
        let distURL = findDistURL()
        if let indexURL = distURL?.appendingPathComponent("index.html") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: distURL!)
            // Set hash after page loads (WKWebView loadFileURL ignores fragment)
            webView.navigationDelegate = self
            NSLog("[App] Loading frontend from: \(indexURL.path)")
        } else {
            NSLog("[App] ERROR: dist/index.html not found!")
        }

        // Show at screen center directly (no offscreen prewarm for Phase 0)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 216, y: frame.midY - 206))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.chatPanel = panel
        self.chatWebView = webView

        NSLog("[App] Chat panel pre-warmed")
    }

    func showChat() {
        guard let panel = chatPanel else {
            NSLog("[App] showChat: no panel!")
            return
        }

        // Position at screen center
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 216
            let y = frame.midY - 206
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            NSLog("[App] Positioning panel at (\(x), \(y)), screen: \(frame)")
        }

        panel.setIsVisible(true)
        panel.level = .statusBar // higher than floating, below screen saver
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSLog("[App] Chat panel shown, isVisible=\(panel.isVisible), frame=\(panel.frame)")
    }

    @objc func handleCloseChatWindow() {
        // TEMP: disabled for Phase 0 testing
        NSLog("[App] Close requested (ignored for testing)")
    }

    @objc func handleChatReady() {
        chatReady = true
        NSLog("[App] Chat ready")
    }

    // MARK: - Find Frontend

    func findDistURL() -> URL? {
        // Check bundle resources first
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist") {
            return url.deletingLastPathComponent()
        }
        // Dev mode: look relative to executable
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        // Go up from .build/debug/Glimpse to project root
        var projectRoot = execURL.deletingLastPathComponent() // debug/
            .deletingLastPathComponent() // .build/
            .deletingLastPathComponent() // project root
        let devDist = projectRoot.appendingPathComponent("dist")
        if FileManager.default.fileExists(atPath: devDist.appendingPathComponent("index.html").path) {
            return devDist
        }
        return nil
    }

}

// MARK: - WKNavigationDelegate
extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("[App] WebView finished loading, URL: \(webView.url?.absoluteString ?? "nil")")
        // Diagnose: check if React rendered and report errors
        webView.evaluateJavaScript("""
            (function() {
                var root = document.getElementById('root');
                var hasContent = root ? root.innerHTML.length : 0;
                var hash = location.hash;
                var hasAPI = !!window.electronAPI;
                return JSON.stringify({hash: hash, rootContent: hasContent, hasAPI: hasAPI, bodyHTML: document.body.innerHTML.substring(0, 200)});
            })()
        """) { result, error in
            if let result { NSLog("[App] Diagnose: \(result)") }
            if let error { NSLog("[App] Diagnose error: \(error)") }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[App] WebView navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[App] WebView provisional navigation failed: \(error)")
    }
}

extension AppDelegate {
    // MARK: - App Lifecycle

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showChat()
        }
        return true
    }
}
