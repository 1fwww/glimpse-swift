# Glimpse (Swift) — Developer Guide

## Workflow Rules
- **Do NOT update GitHub releases** (push DMG, edit release notes, etc.) unless explicitly asked. Only commit and push code.

## Project Overview
macOS screenshot + AI chat tool. **Native Swift shell** + WKWebView loading React frontend. Same architecture as Raycast, Alfred, CleanShot X.

Migrated from Tauri v2 (2026-04-10) because Tauri's NSWindow abstraction cannot create NSPanel, which is required for floating windows on fullscreen Spaces with keyboard input. See `MIGRATION-PLAN.md` for full rationale.

- **React frontend**: 100% reused from Tauri, zero JSX/CSS changes
- **Swift backend**: Replaces Rust/Tauri completely
- **IPC**: WKScriptMessageHandler + evaluateJavaScript (replaces Tauri invoke/listen)

## Build & Run

### Development (debug, native arch only)
```bash
cd glimpse-swift
swift build

# Create .app bundle and launch
cp .build/debug/Glimpse .build/Glimpse.app/Contents/MacOS/Glimpse
cp Glimpse/swift-shim.js .build/Glimpse.app/Contents/Resources/Glimpse/swift-shim.js

# Launch with API key env vars (for invite code support)
GLIMPSE_ANTHROPIC_KEY="..." GLIMPSE_OPENAI_KEY="..." GLIMPSE_GEMINI_KEY="..." \
  .build/Glimpse.app/Contents/MacOS/Glimpse

# Or launch without env vars (user enters keys manually in UI)
open .build/Glimpse.app
# NOTE: `open` does NOT pass env vars — invite code won't work via `open`
```

### Production (universal binary + DMG)
```bash
./build.sh
# Output: .build/Glimpse.app (universal arm64+x86_64) + .build/Glimpse-0.2.0.dmg

# With code signing for distribution:
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh

# With notarization:
CODESIGN_IDENTITY="..." APPLE_TEAM_ID="..." APPLE_ID="..." APPLE_PASSWORD="..." ./build.sh
```

### Restart Protocol
```bash
pkill -f "[Gg]limpse"
```

### Frontend Build
The React frontend source lives in `../glimpse-tauri/src/` and builds to `dist/`. The Swift app loads `dist/index.html`.
```bash
# If frontend changes needed (rare — most work is Swift-side)
# IMPORTANT: edit files in glimpse-tauri/src/, NOT glimpse-swift/src/ — build runs from tauri dir
cd ../glimpse-tauri && npm run build && rm -rf ../glimpse-swift/dist && cp -r dist ../glimpse-swift/dist
```

**CRITICAL**: After `swift build`, you must also copy `dist/` into the app bundle. `swift build` does NOT do this automatically. Without this step, frontend changes won't take effect:
```bash
rm -rf .build/Glimpse.app/Contents/Resources/dist && cp -r dist .build/Glimpse.app/Contents/Resources/dist
```

### New User Test (Welcome Flow)
Simulates a fresh install to test the welcome/onboarding flow. Three things must be cleared:
1. **UserDefaults** (`hasCompletedWelcome` flag)
2. **WKWebView localStorage** (`welcome-step`, `welcome-session` — persists in WebKit cache)
3. **User data stays** — do NOT delete `~/Library/Application Support/glimpse/` (API keys needed)

```bash
pkill -f "[Gg]limpse"
defaults write com.yifuwu.glimpse hasCompletedWelcome -bool false
rm -rf ~/Library/WebKit/com.yifuwu.glimpse
rm -rf ~/Library/Caches/com.yifuwu.glimpse
.build/Glimpse.app/Contents/MacOS/Glimpse
```

To restore after testing:
```bash
defaults write com.yifuwu.glimpse hasCompletedWelcome -bool true
```

## Architecture

### File Structure
```
Glimpse/
├── main.swift                  # NSApplication run loop
├── AppDelegate.swift           # Lifecycle, shortcuts, window management, overlay
├── GlimpsePanel.swift          # NSPanel subclass — canBecomeKey, showAndFocus/showOnFullscreen
├── GlimpseWebView.swift        # WKWebView subclass — acceptsFirstMouse for click-through
├── NativeSelectionOverlay.swift # Native screenshot selection — Core Graphics, zero WebKit
├── IPCBridge.swift             # WKScriptMessageHandler — all JS↔Swift IPC
├── ScreenCapture.swift         # CGWindowListCreateImage + JPEG to /tmp + window bounds
├── AIService.swift             # URLSession calls to Claude/GPT/Gemini
├── ShortcutManager.swift       # CGEventTap — shortcuts + window drag
├── SpaceDetector.swift         # CGSSpaceGetType private API — fullscreen detection
├── SettingsStore.swift         # API keys + preferences + embedded keys for invite
├── ThreadStore.swift           # Thread JSON persistence, 100 max, auto-prune
├── TrayManager.swift           # NSStatusItem — tray icon + dynamic menu
├── ToastManager.swift          # Native toast notifications (Outfit font, cyan border)
├── TextGrabber.swift           # CGEvent Cmd+C simulation (~10ms)
├── EmbeddedKeys.swift          # API keys baked in by build.sh (empty in git)
└── swift-shim.js               # Drop-in replacement for tauri-shim.js
fonts/
└── Outfit-Variable.ttf         # Bundled font for native rendering (converted from woff2)
```

### IPC Pattern
JS calls `window.electronAPI.someMethod()` → `swift-shim.js` converts to `window.webkit.messageHandlers.glimpse.postMessage({command, args, callbackId})` → `IPCBridge.userContentController` dispatches → Swift resolves via `evaluateJavaScript("window._glimpseResolve(callbackId, result)")`.

**Sync commands** (threads, settings, window): handled in `handleCommandSync`, resolved immediately.
**Async commands** (AI calls, key validation): handled in `handleAsyncCommand` via `Task {}`, resolved when complete.

### Window Lifecycle
- **Chat panel**: Pre-warmed at startup (hidden via `orderOut`). On Cmd+Shift+X: show pre-warmed (instant). On close: hide (not destroy) for reuse.
- **Fullscreen path**: Hidden windows can't be shown on fullscreen Spaces (macOS binds them to original Space). Must destroy + recreate for fullscreen association.

### Data Directory
`~/Library/Application Support/glimpse/` — same path as Tauri for migration compatibility.
- `api-keys.json` — API keys (masked in UI, validated before save)
- `preferences.json` — user preferences
- `threads/` — chat thread JSON files (max 100, auto-pruned)

## Hard-Won Lessons (Swift + WKWebView)

### Window Dragging in WKWebView (4 failed approaches)
**Problem**: Borderless NSPanel with WKWebView needs custom drag implementation.

**Failed approaches**:
1. `-webkit-app-region: drag` CSS + `isMovableByWindowBackground` — WKWebView parses the CSS but does NOT bridge it to native dragging
2. `getComputedStyle(el).webkitAppRegion` in JS — returns `undefined` in WKWebView (Chromium-only property)
3. JS mousedown → IPC → `window.performDrag(with:)` — event is stale by the time IPC message arrives
4. `NSEvent.addLocalMonitorForEvents(.leftMouseDragged)` — WKWebView's WebContent process consumes mouse events before local monitors see them
5. Override `mouseDragged` in WKWebView subclass — internal WebKit views handle events, subclass overrides never fire

**Working solution**: MutationObserver + capture-phase mousedown + CGEventTap
1. JS: `MutationObserver` watches for `.chat-header` element, adds **capture-phase** mousedown listener
2. Capture phase fires BEFORE React's bubble-phase handler (which checks `__TAURI_INTERNALS__` and returns early)
3. JS sends `_start_drag` IPC to Swift
4. `ShortcutManager.startDrag()` records initial mouse position + window origin
5. CGEventTap handles `leftMouseDragged` at HID level — moves window by delta
6. CGEventTap handles `leftMouseUp` to stop dragging

**Why capture phase**: React's `handleHeaderMouseDown` in `ChatPanel.jsx` checks `window.__TAURI_INTERNALS__` for Tauri's `startDragging()` and **always returns early** when `chatFullSize=true`. Without Tauri internals, drag is silently skipped. Must intercept BEFORE React.

### Swift Concurrency + Main Thread Blocking
**CRITICAL**: `Task {}` inside `@MainActor` context (like AppDelegate, which conforms to NSApplicationDelegate) **inherits the main actor**. Any blocking call inside it (e.g., `Process.waitUntilExit()`) blocks the main run loop, which kills the CGEventTap callback (it runs on `CFRunLoopGetMain`).

**Rule**: Use `DispatchQueue.global().async` or `Task.detached` for any blocking I/O. Never use `Task {}` from AppDelegate methods.

### CGEventTap Key Repeat
CGEventTap with `.listenOnly` receives ALL keyDown events including key repeats. If you hold Cmd+Shift+X slightly, multiple events fire. Filter repeats:
```swift
let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
guard isRepeat == 0 else { break }
```

### Fullscreen Space Detection
**Private CGS APIs** (only reliable method):
```swift
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> UInt32
@_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_ cid: UInt32) -> UInt64
@_silgen_name("CGSSpaceGetType") func CGSSpaceGetType(_ cid: UInt32, _ space: UInt64) -> Int32
// Type 0 = normal desktop, Type 4 = fullscreen Space
```

**Fullscreen chat flow**:
1. Detect fullscreen via `CGSSpaceGetType == 4`
2. Switch to `NSApp.setActivationPolicy(.accessory)`
3. Destroy pre-warmed chat panel
4. Create fresh panel → auto-associates with current fullscreen Space
5. Use `showOnFullscreen()` (orderFrontRegardless + makeKey)
6. Call `NSApp.activate(ignoringOtherApps:)` **synchronously after** — safe because window is already on this Space via `orderFrontRegardless`. Required for first-click responsiveness on WKWebView buttons.
7. 200ms later: lock to `[.fullScreenAuxiliary]` only

**What triggers Space switch** (avoid these on fullscreen):
- `NSApp.activate(ignoringOtherApps:)` **before** the window is on the Space — teleports user to another desktop. Safe **after** `orderFrontRegardless()` because window is already there.
- `NSApp.setActivationPolicy(.regular)` — same effect; use `NSApp.hide()` first, then restore Regular after 100ms delay (extracted as `restoreActivationPolicyIfNeeded()`)

### Multi-Desktop Behavior
Show with `[.canJoinAllSpaces, .fullScreenAuxiliary]` → after 200ms switch to `[.fullScreenAuxiliary]` only. The initial `canJoinAllSpaces` ensures the window appears on the current Space; removing it locks the window there.

### WKWebView Requires Edit Menu for Cmd+C/V
Without an Edit menu with standard key equivalents, Cmd+C/V/X/A don't work in WKWebView. Must create `NSMenu` with Cut/Copy/Paste/SelectAll items programmatically.

### AI Response Format
Frontend expects `{ success: true, content: [{ type: "text", text: "..." }] }` (Anthropic format). All providers must be normalized to this format — NOT `{ success: true, message: "..." }`.

### WebKit Threading
Use `DispatchQueue.main.async` for all WebKit interactions. `Task { @MainActor in }` crashes WebKit on macOS 26.x (Tahoe). See `PHASE0-LEARNINGS.md`.

## Phase 1 Status (Chat MVP — Complete)

### Working
- Cmd+Shift+X toggle chat (instant, reliable, key repeat filtered)
- Keyboard input (NSPanel + canBecomeKey)
- AI responses (Claude/GPT/Gemini, non-streaming)
- Thread persistence (save/load/delete/switch/new)
- API key management (save/validate/delete)
- Window dragging (CGEventTap-based)
- Fullscreen Space support (destroy+recreate path)
- Multi-desktop (single-Space lock after 200ms)
- Pin toggle (floating ↔ normal window level)
- ESC closes chat
- Cmd+C/V copy/paste
- Chat resize on AI reply (grows upward, animated)

### Not Working
- **Invite code via `open`** — env vars not passed. Works when binary launched directly, or use embedded keys via `build.sh`.

## Phase 2 Status (Screenshot Flow — Complete)

### Working
- Cmd+Shift+Z captures screen → overlay with selection/annotation tools
- Auto-highlight window under cursor on trigger (synthetic mousemove via swift-shim.js)
- Window snap on hover, Desktop fallback when cursor not over any window
- Draw selection → chat panel appears → AI responds about screenshot
- Copy selection to clipboard (PNG + TIFF for compatibility)
- Save selection to file (NSSavePanel, overlay lowered during dialog)
- ESC closes overlay (priority over chat, consumed to prevent beep)
- Cmd+Shift+X during overlay → switch to chat, and vice versa
- Pin flow: overlay chat → standalone chat panel (seamless alpha-swap transition)
- Fullscreen Space support (destroy+recreate for overlay and pinned chat)
- Window level: unpinned chat at `.normal` (other windows can cover it), pinned at `.floating`
- Shortcuts consumed via `.defaultTap` — no beep, works in Terminal

### Hard-Won Lessons (Phase 2)

#### Seamless Pin Transition (alpha swap)
**Problem**: Replacing overlay's chat panel with standalone chat causes visible flash — overlay hides before chat appears.

**Solution**: Show chat at `alphaValue = 0` above overlay → emit thread data (JS runs on invisible windows) → wait 150ms for React render → set `alphaValue = 1` + hide overlay in same frame. Overlay stays visible during the render wait; user sees atomic swap.

For fullscreen: `onChatReadyAction` callback defers the swap until the recreated WebView loads.

#### Pin State Sync
**Problem**: `isPinned` persisted across chat sessions. User reopens chat → frontend shows unpinned (default), Swift has `isPinned = true` → first toggle click appears to do nothing (toggles to false, which frontend already shows).

**Fix**: Reset `isPinned = false` in `hideChat()`. Emit `pin-state` + `clear-screenshot` to WebView **before** showing window (JS runs on hidden WebView, so React updates DOM before window is visible — no flash).

#### CSS → Cocoa Coordinate Conversion
Overlay bounds from JS are CSS viewport coords (top-left origin). Cocoa uses bottom-left origin.
```swift
let screenX = overlayFrame.origin.x + cssX
let screenY = overlayFrame.origin.y + overlayFrame.height - cssY - elementHeight
```
JSON numbers from JS arrive as `NSNumber` — cast via `(value as? NSNumber).map { CGFloat($0.doubleValue) }`, not `as? Int` or `as? CGFloat` (silently fail).

#### NSSavePanel + Overlay Workflow
Save dialog can't appear above screenSaver-level overlay. Must: lower overlay to `.normal` → run NSSavePanel → restore overlay level → `makeKey()` to refocus.

#### Overlay WebView Reuse (Phase 3 update)
**Previous**: Always destroy + recreate overlay WebView per screenshot (stale React state).
**Current**: Reuse WebView on non-fullscreen Spaces. `resetState()` in React now clears `screenImage` to null. Key ordering: call `resetState()` BEFORE `setScreenImage(newUrl)` — otherwise reset wipes the new image. Fullscreen still requires recreate (Space association).

#### CGEventTap: `.defaultTap` vs `.listenOnly`
**Problem**: `.listenOnly` can't consume events — shortcuts pass through to focused apps, causing system beep and Terminal intercepting Cmd+Shift+Z as "Redo".

**Fix**: Use `.defaultTap` and return `nil` for our shortcuts (Cmd+Shift+X, Cmd+Shift+Z, ESC when windows visible). This consumes the event before any app sees it. Requires Accessibility permission (same as `.listenOnly` at HID level).

#### Window Bounds: Filter System UI
`CGWindowListCopyWindowInfo` returns system windows that cover the entire screen (Dock, Notification Center, Window Server, Control Center). These must be filtered out, otherwise hover detection "selects" the entire screen. Add a Desktop fallback entry at the end of the bounds array for full-screen selection when cursor is over empty desktop.

#### Auto-Highlight on Screenshot Trigger
React's hover detection only fires on `mousemove`. To auto-highlight the window under the cursor when the overlay first appears: include cursor position (CSS coords) in `screen-captured` event data, then dispatch a synthetic `mousemove` from swift-shim.js 50ms after data loads.

## Phase 3 Status (Polish & Parity — Complete)

### Working
- Tray icon (NSStatusItem + dynamic menu with thread list)
- Welcome/onboarding flow (first-launch detection, permission grants, shortcut practice)
- Settings window (smart positioning, overlay-level aware)
- Toast notifications (native NSPanel, Outfit font, matches Tauri design)
- Text quoting (CGEvent Cmd+C simulation ~10ms)
- Native screenshot selection (CAShapeLayer-level smoothness)
- Invite code with embedded API keys (baked in by build.sh, never in git)
- Production build script (universal arm64+x86_64, DMG, code signing)

### Hard-Won Lessons (Phase 3)

#### Native Selection Overlay (NativeSelectionOverlay.swift)
**Why**: WebView selection had ~3-5ms WebKit IPC lag per mousemove + rAF throttle adding up to 16ms. Native selection eliminates both.

**Architecture**: Native overlay handles selection phase only (mouseDown → drag → mouseUp). On mouseUp, capture screen below native overlay → emit data to hidden WebView → React renders + signals `overlayRendered` → CATransaction atomic swap (show WebView + dismiss native in same run loop). WebView handles post-selection (annotations, toolbar, chat).

**Native→WebView handoff (hard-won)**:
The handoff from native selection to WebView overlay required multiple iterations to eliminate flash:
1. **Fixed delay (150ms)**: Emit to hidden WebView → wait 150ms → swap. Flash on fast screenshots when React hadn't finished rendering.
2. **Show WebView behind native**: Tried `orderFrontRegardless` at lower window level. `makeKeyAndOrderFront` + `NSApp.activate` in `showOverlay()` disrupted the native overlay, causing WORSE flash.
3. **`overlayRendered` callback** (final solution): React signals Swift after render + image decode (`setTimeout(50ms)` + `Image.onload`). Swift calls `showOverlay()` + `nativeSelectionOverlay.dismiss()`. 500ms safety timeout as fallback.

**Key decision**: Emit to HIDDEN WebView, not visible. JS executes on ordered-out WKWebViews. The backing store updates even when hidden (unlike GPU compositing which is deferred).

**Failed approach**: Showing WebView at a lower level "behind" native overlay for pre-painting. Any call to `showAndFocus()`/`NSApp.activate()` disrupts the native overlay's visual state, and setting the window level AFTER `makeKeyAndOrderFront` means there's at least one frame at the wrong level.

**CRITICAL — hasShadow/cornerRadius cause flash on overlay (hard-won)**:
`GlimpsePanel.hasShadow = true` and `WKWebView.layer.cornerRadius + masksToBounds` MUST NOT be applied to the overlay panel. When applied to a full-screen overlay:
- `hasShadow = true` forces the window server to compute shadow compositing on first show, adding an extra compositor frame that produces a visible flash.
- `cornerRadius + masksToBounds` clips the full-screen WebView at the corners and changes the compositor's code path, compounding the flash.
These properties are intended for the chat panel only. Apply them in `prewarmChat()` after creating the panel, NOT in `createWebView()` or `GlimpsePanel.init`. If you add any visual styling to GlimpsePanel or createWebView, verify it doesn't affect the overlay — the overlay MUST be a plain borderless panel with `hasShadow = false` and no layer masking.

**Key gotchas**:
- Must use `NSPanel` subclass (not NSWindow) — NSWindow can't become key in `.accessory` activation policy
- Window background must be near-transparent `NSColor(white: 0, alpha: 0.001)`, not `.clear` — fully transparent windows pass clicks through to windows behind
- `acceptsFirstMouse(for:) → true` required for immediate click reception
- Crosshair cursor: use `resetCursorRects` + `cursorUpdate` + `NSCursor.crosshair.set()` in mouseMoved (all three needed for consistency)
- Desktop entry in window bounds must be excluded from hover detection but used as click fallback for full-screen selection
- 5px drag threshold distinguishes click (snap) from drag (free-form)
- `draw()` must check `currentRect.width > 2` (not `hasDraggedPastThreshold`) for BOTH cutout AND toast visibility — `hasDraggedPastThreshold` is reset on mouseUp, so any condition using it will flicker on redraw after selection completes

#### Screenshot Performance
**JPEG + file URL** instead of PNG + base64:
- JPEG 85% quality: 10-20x faster encoding than PNG
- Write to unique `/tmp/glimpse-capture-{timestamp}.jpg` per capture, pass `file://` URL to WebView
- Unique filenames prevent WKWebView `file://` caching (query string cache-busters don't work for file URLs)
- Previous capture file auto-cleaned on next capture
- WKWebView needs `allowingReadAccessTo: URL(fileURLWithPath: "/")` for temp file access

**CRITICAL — WKWebView `file://` Image decode race (hard-won)**:
`new Image(); img.src = fileUrl; img.onload = () => ctx.drawImage(img, ...)` is **BROKEN** in WKWebView for `file://` URLs. `onload` fires after metadata (dimensions) is parsed but BEFORE pixel data is fully decoded. `img.decode()` also does NOT reliably wait. Result: `drawImage` reads black pixels intermittently, producing black screenshots.

**Fix**: Use `fetch(url)` → `resp.blob()` → `createImageBitmap(blob)` which guarantees full pixel decode. Applied to all three image processing paths: `cropSelection`, `getCompositeImage`, `getHiResComposite`. **Never use `new Image()` for canvas operations with `file://` URLs in WKWebView.**

**Frozen screen** (for non-native-selection fallback on fullscreen):
- `CGDisplayCreateImage` reads framebuffer in ~5ms (vs CGWindowListCreateImage ~20ms)
- Shows NSWindow with NSImageView instantly, real work happens behind it
- Must hide chat BEFORE capturing frozen screen (compositor lag)
- Dismiss with 50ms delay to let React render before removing frozen screen

#### Text Quoting (TextGrabber.swift)
**Two-tier approach**: AX API first (instant, no beep), Cmd+C fallback (may beep).

**AXResult enum** distinguishes three outcomes:
- `.success(text)`: AX read selectedText — use it, no Cmd+C needed
- `.noSelection`: AX reached the focused element but `kAXSelectedTextAttribute` failed — nothing selected, do NOT fall back to Cmd+C (would beep)
- `.appFailed`: AX couldn't get the focused element at all (e.g., Chrome returns -25212 on fullscreen) — fall back to Cmd+C

**Key decision**: The distinction between `.noSelection` and `.appFailed` is based on WHERE AX fails. `kAXFocusedUIElementAttribute` failure = app-level issue (try Cmd+C). `kAXSelectedTextAttribute` failure = element-level issue (nothing selected, skip Cmd+C).

**Execution order**: AX API runs on main thread BEFORE any window operations (hideChat, showChat). If AX fails and Cmd+C fallback is needed, it runs on a background thread (Thread.sleep + DispatchQueue.main.sync) BEFORE showChat — source app still has focus.

**Focus restoration**: `hideChat()` calls `NSApp.hide(nil)` after `orderOut` to deactivate Glimpse. Without this, Glimpse stays frontmost after hiding chat, and the next text grab sees Glimpse (not the source app) as `frontmostApplication`.

#### Shortcut UX Decisions
**Chat shortcut (Cmd+Shift+X) is always-open, never toggle-off.** User closes chat with ESC. This avoids wasted keypresses when Space transitions cause showChat to fail — with toggle behavior, a failed show gets toggled off on the next press, requiring 3 presses total. With always-open, worst case is 2 presses (first fails, second succeeds).

**Toggle check uses `isKeyWindow`**, not `isVisible`. `panel.isVisible` returns true even when the panel is on a different Space. `panel.screen` returns the same `NSScreen` for different Spaces on the same physical display. Only `isKeyWindow` reliably indicates the panel is on the current Space.

**Screenshot shortcut defers during Space transitions** (300ms after `activeSpaceDidChangeNotification`). Uses single-pending flag to prevent stacked retries. Chat shortcut does NOT defer — with always-open behavior, the extra press is fast enough.

**Known limitation**: Auto-selection window bounds are slightly off when screenshotting immediately after switching to a fullscreen Space. `CGWindowListCopyWindowInfo` needs time to update positions after Space transitions. Feishu has the same issue.

#### CGEventTap on Fresh Install
- Don't create event tap at startup — defer until accessibility is granted
- Poll every 2s with Timer until `AXIsProcessTrusted()` returns true
- `applicationDidBecomeActive` doesn't fire reliably for `.accessory` apps
- Also retry in `handleWelcomeDone()` and `check_permissions` IPC
- Hidden menu items (Cmd+Shift+X/Z) as fallback when tap unavailable

#### Activation Policy (Dock Icon)
- During onboarding: `.regular` (dock icon visible, discoverable)
- After welcome done: `.accessory` (tray-only, no dock icon)
- Welcome window: `.normal` level (not `.floating`) so system permission dialogs appear above it
- Welcome window: `isMovableByWindowBackground = true` for drag without CGEventTap

#### Embedded API Keys
- `EmbeddedKeys.swift` checked into git with empty strings
- `build.sh` overwrites with real keys from env vars before compiling
- Restored to empty after build — keys never linger in source
- `SettingsStore` reads embedded keys first, falls back to env vars (dev mode)

#### Frontend Source Location
- React source lives in `../glimpse-tauri/src/`, NOT `glimpse-swift/src/`
- `npm run build` runs from `glimpse-tauri/` directory
- Must `rm -rf dist` before `cp -r` (stale hashed files persist otherwise)
- Copy edited files to `glimpse-swift/src/` for reference only

#### React State Ordering
- `resetState()` includes `setScreenImage(null)` — must be called BEFORE `setScreenImage(newUrl)` in event handlers, not after. Wrong order: set image → reset → image cleared → invisible overlay.

## Chat Window Behavior (Consolidated 2026-04-13)

### Architecture: Unified State, Two Render Targets
- **Standalone** (`ChatOnlyApp.jsx` + Swift NSPanel): window size controlled by Swift (`lastChatSize`, `resizeChatWindow`)
- **Screenshot overlay** (`App.jsx`): chat size controlled by React (`chatFullSize`, `chatMinimized`), but initial state decided by Swift
- Same `ChatPanel` component shared; two IPC bridges (`bridgeId="main"` vs `"overlay"`) for routing only
- **Single set of state flags** in Swift — no separate overlay/standalone tracking

### State Flags (Swift side)
| Flag | Purpose | Set by |
|---|---|---|
| `lastDismissTime` | When any chat was last hidden | `hideChat()`, `hideOverlay()` |
| `wasNewThread` | Last session was empty/new thread | `handleNewThreadCreated()`, `handleConversationStarted()` |
| `lastChatSize` | Standalone window size to restore | `hideChat()` |
| `userDidResizeChat` | User manually resized (block JS resize) | `didEndLiveResize` |

### Unified Decision Function
```swift
func decideChatState() -> ChatInitState {
    let isStale = Date().timeIntervalSince(lastDismissTime) >= chatStaleThreshold // 5 min
    if isStale || wasNewThread {
        return (startNewThread: true, compact: true)
    }
    return (startNewThread: false, compact: false)
}
```
Used by both `showChat()` (standalone) and `handleScreenshotShortcut()` (overlay). Swift is the sole authority on stale detection — JS has no `STALE_THRESHOLD`.

### Compact vs Expanded Decision Flow
```
Any open (standalone or screenshot):
  decideChatState() → stale OR wasNewThread → compact + start-new-thread
  decideChatState() → !stale AND !wasNewThread → expanded + keep thread

Standalone: compact = 380×412 setFrame, expanded = restore lastChatSize
Overlay: compact = setChatMinimized(true) + setChatFullSize(false)
         expanded = setChatMinimized(userMinimizedRef) + setChatFullSize(true)

"+" clicked:
  notifyNewThread → wasNewThread=true
  Next open → compact

AI replies:
  chatConversationStarted → wasNewThread=false
  Next open within 5min → expanded + keep thread
```

### Cross-Entry Thread Sync
Overlay WebView is pre-warmed at startup — its thread state may be stale. When `!startNewThread`, overlay calls `tm.loadLatestThread()` to reload the most recent thread from disk (which may have been created by standalone chat).

### Critical Rules (Still Valid)
1. **`cropSelection` must receive `displayInfo`/`windowOffset` as direct params.** Closure capture gets stale values (React hasn't re-rendered yet when `setTimeout(cropSelection, 50)` fires). First screenshot gets black image otherwise.

2. **Re-quote `initialContext.seq` must use `Date.now()`.** Incremental counter cycles back to same value — `useEffect` dependency doesn't change.

3. **Don't `NSApp.hide` in re-quote path.** Races with `NSApp.activate` in `showAndFocus`.

4. **`scrollToRevealLoading` must fire in compact mode too.**

5. **Overlay `onThreadChange` needs wrapper.** `handleThreadChange` only calls `resizeChatWindow` (standalone-only). Overlay must also set `chatFullSize`/`chatMinimized`.

### Known Remaining Pattern
- **`handleResizeChatWindow` cross-fire**: Both bridges post `.resizeChatWindow` notification — overlay's ChatPanel resize attempts to resize standalone NSPanel

## macOS API Quick Reference

| API | Use | Gotcha |
|---|---|---|
| `NSPanel(canBecomeKey: true)` | Chat/overlay windows | Can become key in `.accessory` policy (NSWindow can't) |
| `CGEvent.tapCreate(.defaultTap)` | Shortcuts, drag, ESC | Defer creation until accessibility granted; filter key repeats |
| `CGDisplayCreateImage` | Instant frozen screen | ~5ms framebuffer read; shows stale compositor state |
| `CGWindowListCreateImage` | Real screen capture | ~20ms; run on background thread; JPEG encode to /tmp |
| `CGSSpaceGetType` | Fullscreen detection | Private API, type 4 = fullscreen |
| `NSApp.setActivationPolicy` | Dock icon control | `.regular` = dock icon, `.accessory` = tray only |
| `CTFontManagerRegisterFontsForURL` | Bundle custom fonts | Register at launch; use `.process` scope |
| `evaluateJavaScript` | Swift→JS events | Async; delay frozen screen dismissal 50ms for React render |
| `NSWindow.backgroundColor(.001 alpha)` | Transparent but clickable | Fully `.clear` passes clicks through to windows behind |
| `acceptsFirstMouse(for:)` | Click-through | Override on NSView for immediate click reception |
| `NSAnimationContext` | Window fade in/out | GPU-backed; use instead of manual Timer for smooth animation |
| `NSWindow.hasShadow` | Window shadow | Adds compositor overhead; do NOT enable on full-screen overlays |
| `CALayer.cornerRadius` | Rounded corners | With `masksToBounds`, changes compositor path; chat-only, not overlay |
