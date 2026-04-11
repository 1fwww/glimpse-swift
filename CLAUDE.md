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

## Architecture

### File Structure (2,119 lines Swift + 133 lines JS)
```
Glimpse/
├── main.swift              # NSApplication run loop
├── AppDelegate.swift       # Lifecycle, shortcuts, window management, overlay (633 lines)
├── GlimpsePanel.swift      # NSPanel subclass — canBecomeKey, showAndFocus/showOnFullscreen (48 lines)
├── GlimpseWebView.swift    # WKWebView subclass — acceptsFirstMouse for click-through (41 lines)
├── IPCBridge.swift         # WKScriptMessageHandler — all JS↔Swift IPC (374 lines)
├── ScreenCapture.swift     # CGWindowListCreateImage + window bounds (136 lines)
├── AIService.swift         # URLSession calls to Claude/GPT/Gemini (295 lines)
├── ShortcutManager.swift   # CGEventTap — shortcuts + window drag (146 lines)
├── SpaceDetector.swift     # CGSSpaceGetType private API — fullscreen detection (26 lines)
├── SettingsStore.swift     # API keys + preferences persistence (193 lines)
├── ThreadStore.swift       # Thread JSON persistence, 5 max, auto-prune (86 lines)
├── TextGrabber.swift       # Cmd+C simulation — DISABLED, needs fix (135 lines)
└── swift-shim.js           # Drop-in replacement for tauri-shim.js (133 lines)
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
- `threads/` — chat thread JSON files (max 5, auto-pruned)

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
- **Text quoting** (Cmd+C simulation) — disabled. Root cause: `Task {}` from `@MainActor` blocks main thread; `DispatchQueue.global` works but ~400ms delay before chat appears causes key repeat race conditions. Fix: use `CGEvent`-based keystroke injection (10ms vs osascript 200ms).
- **Invite code via `open`** — env vars not passed. Works when binary launched directly.

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

#### Overlay Must Be Recreated Each Session
**Problem**: Reusing the overlay WebView across screenshot sessions causes accumulated dark masks and stale screenshots. `emit("reset-overlay")` can't reliably clear React state because `evaluateJavaScript` is async — the overlay becomes visible with stale state before the reset JS executes.

**Fix**: Always destroy + recreate the overlay panel (`prewarmOverlay()`) for every screenshot. Fresh WebView = guaranteed clean state. The WebView load (~200ms) runs in parallel with the capture, so total latency is similar.

#### CGEventTap: `.defaultTap` vs `.listenOnly`
**Problem**: `.listenOnly` can't consume events — shortcuts pass through to focused apps, causing system beep and Terminal intercepting Cmd+Shift+Z as "Redo".

**Fix**: Use `.defaultTap` and return `nil` for our shortcuts (Cmd+Shift+X, Cmd+Shift+Z, ESC when windows visible). This consumes the event before any app sees it. Requires Accessibility permission (same as `.listenOnly` at HID level).

#### Window Bounds: Filter System UI
`CGWindowListCopyWindowInfo` returns system windows that cover the entire screen (Dock, Notification Center, Window Server, Control Center). These must be filtered out, otherwise hover detection "selects" the entire screen. Add a Desktop fallback entry at the end of the bounds array for full-screen selection when cursor is over empty desktop.

#### Auto-Highlight on Screenshot Trigger
React's hover detection only fires on `mousemove`. To auto-highlight the window under the cursor when the overlay first appears: include cursor position (CSS coords) in `screen-captured` event data, then dispatch a synthetic `mousemove` from swift-shim.js 50ms after data loads.

## Phase 3: Polish & Parity

- Tray icon (NSStatusItem + dynamic menu)
- Welcome/onboarding flow
- Settings window
- Toast notifications
- Text quoting fix (CGEvent keystroke injection)
- Remaining IPC stubs (selectFolder, copyImage, saveImage, etc.)

## macOS API Quick Reference

| API | Use | Gotcha |
|---|---|---|
| `NSPanel(canBecomeKey: true)` | Chat window | Must init via `initWithContentRect:` — `object_setClass` doesn't work |
| `CGEvent.tapCreate(.cghidEventTap, .listenOnly)` | Shortcuts, drag, ESC | Filter `.keyboardEventAutorepeat`; callback on main run loop |
| `CGSSpaceGetType` | Fullscreen detection | Private API, type 4 = fullscreen |
| `NSApp.setActivationPolicy(.accessory)` | Fullscreen windows | Causes Space switch on restore — use `restoreActivationPolicyIfNeeded()` |
| `orderFrontRegardless() + makeKey()` | Show on fullscreen | Call `NSApp.activate` **after** (safe once window is on Space) |
| `CanJoinAllSpaces → FullScreenAuxiliary` | Single-desktop lock | 200ms delay between set calls |
| `evaluateJavaScript` | Swift→JS events | Must be on main thread via `DispatchQueue.main.async` |
| `WKScriptMessageHandler` | JS→Swift IPC | Callback IDs for async returns |
| `CGWindowListCreateImage` | Screen capture | Run on background thread; capture BEFORE showing overlay |
| `NSWindow.alphaValue` | Seamless transitions | Show at alpha=0, render content, then reveal — atomic swap |
| `NSSavePanel` | File save dialog | Lower overlay level first, restore after, `makeKey()` to refocus |
| `acceptsFirstMouse(for:)` | Click-through | Override on WKWebView subclass for fullscreen click responsiveness |
