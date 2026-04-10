# Phase 0 Learnings — What Worked, What Didn't, What to Fix

## What Worked

1. **Real NSPanel with canBecomeKey=YES** — Keyboard input works. This was the Tauri blocker. The key is `init(contentRect:styleMask:backing:defer:)` creating a proper NSPanel, not `object_setClass` swizzling.

2. **WKScriptMessageHandler IPC** — JS → Swift → JS callback round-trip works. `window.electronAPI` interface preserved, React components unchanged.

3. **Route injection via WKUserScript** — Setting `window._glimpseRoute` at `.atDocumentStart` before React renders. Clean solution for hash-based routing with `loadFileURL`.

4. **Swift Package Manager** — Fast iteration (build in <1s). No Xcode project needed for now.

## What Failed & Why

1. **Bare binary can't show windows** — Running `.build/debug/Glimpse` directly from terminal doesn't display GUI windows. Must run as `.app` bundle (even minimal). macOS requires proper app bundle identity for window server access.

2. **Offscreen prewarm crashes WebKit** — Positioning panel at (-9999, -9999) then moving it caused `RemoteLayerTreePropertyApplier` crash. WebKit's layer tree update has strict main-thread assertions on macOS 26.x (Tahoe). Fix: show at normal position from the start, or use `orderOut` instead of offscreen positioning.

3. **NSPanel with NonactivatingPanel not visible** — `NonactivatingPanel` style mask makes the panel invisible when app isn't "activated." Need `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront` + possibly higher window level. We temporarily used `.titled` style mask instead. **Must revisit for fullscreen support.**

4. **`Task { @MainActor in }` crashes WebKit** — Swift structured concurrency's main actor isolation conflicts with WebKit's internal threading. WebKit callbacks that trigger layer updates must use `DispatchQueue.main.async`, NOT `Task { @MainActor in }`.

5. **`JSONSerialization` rejects primitive top-level values** — `true`, `42`, `"hello"` are not valid JSON top-level objects in Apple's implementation. Must handle Bool/Int/Double/String specially in `jsonString()`.

6. **`loadFileURL` ignores hash fragment** — `loadFileURL(url.appendingPathComponent("#chat-only"))` doesn't work. Hash must be injected via JavaScript or WKUserScript at document-start.

7. **Double `loadFileURL` call** — Calling it twice (once with hash, once without) causes the second to overwrite the first. Only call once, use JS to set hash.

## Code Quality Issues to Fix

### 1. GlimpsePanel style mask is TEMP
```swift
styleMask: [.resizable, .titled], // TEMP
```
Must switch to `[.nonactivatingPanel, .resizable, .borderless]` for production. The `.titled` bar (red/yellow/green buttons) must go. But `.nonactivatingPanel` caused invisible window — need to investigate further before changing.

**Risk**: Removing `.titled` might make the panel invisible again. Need to test with `NSApp.activate` + `makeKeyAndOrderFront` + proper window level.

### 2. Background color is TEMP
```swift
backgroundColor = NSColor.white.withAlphaComponent(0.95) // TEMP
```
Must change to `.clear` with `isOpaque = false` + WebView `drawsBackground = false` for transparent rounded corners (matching Tauri's inner wrapper pattern).

### 3. `prewarmChat` shows window immediately
Currently no prewarm/hide cycle — window shows at startup. Phase 1 needs:
1. Create panel + WebView offscreen or hidden
2. Wait for `chatReady` signal
3. Hide panel
4. Show on Cmd+Shift+X

The offscreen approach crashed (learning #2). Alternative: create with `orderOut` (hidden), wait for ready, then `makeKeyAndOrderFront` when needed.

### 4. `showChat` has redundant calls
```swift
panel.setIsVisible(true)
panel.level = .statusBar
panel.orderFrontRegardless()
panel.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
```
This is a shotgun approach from debugging. Should be simplified to just `makeKeyAndOrderFront` + `activate`. The `statusBar` level and `orderFrontRegardless` may cause issues.

### 5. `findDistURL` uses fragile path walking
```swift
let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
// Go up from .build/debug/Glimpse to project root
```
Works for SPM dev mode but breaks if directory structure changes. Should prioritize Bundle.main lookup and have a clear error if dist not found.

### 6. IPCBridge notification pattern
```swift
NotificationCenter.default.post(name: .closeChatWindow, object: nil)
```
Using NotificationCenter to communicate between IPCBridge and AppDelegate works but is loosely coupled. Consider a delegate pattern or direct reference for type safety.

### 7. `jsonString` is brittle
The String serialization hack (wrap in array, strip brackets) is fragile:
```swift
if let data = try? JSONSerialization.data(withJSONObject: [s]),
   let str = String(data: data, encoding: .utf8) {
    return String(str.dropFirst().dropLast())
}
```
Should use proper JSON encoding (e.g., `Codable` or a JSON library) instead of manual string manipulation.

### 8. Memory management: WKScriptMessageHandler retain cycle
```swift
userContent.add(ipcBridge, name: "glimpse")
```
`WKUserContentController` strongly retains its message handlers. If `ipcBridge` holds a strong ref to `webView`, and `webView` is owned by `panel`, there's a potential retain cycle. Currently `ipcBridge.webView` is `weak`, so it's fine — but document this.

### 9. No error handling for frontend load failure
If `dist/index.html` fails to load (missing, corrupted), the user sees a blank window with no feedback. Should detect and show a meaningful error.

## Architecture Decisions Confirmed

1. **Swift Package Manager > Xcode project** for now — faster iteration, simpler structure. Can migrate to Xcode project later if needed for signing/capabilities.

2. **`window.electronAPI` interface preserved** — React components need zero changes. This is the correct abstraction boundary.

3. **WKUserScript at `.atDocumentStart`** — Correct injection point for shim + route. Guaranteed to run before page scripts.

4. **`DispatchQueue.main.async` over Swift concurrency** — For WebKit interactions, GCD is safer than structured concurrency on macOS 26.x.

## Next Steps (Phase 1 priorities)

1. Fix window style: borderless + transparent (no title bar)
2. Implement prewarm → hide → show cycle (without offscreen crash)
3. Fullscreen Space test with `.nonactivatingPanel`
4. Implement AI API calls (URLSession)
5. Thread persistence
6. Global shortcut (CGEventTap)
