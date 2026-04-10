# Glimpse Swift Migration Plan

## Context

Glimpse is a macOS screenshot + AI chat tool. Users press Cmd+Shift+Z to capture a screenshot with an overlay for selection and annotation, then chat with AI about it. Cmd+Shift+X opens a standalone chat window for text-based conversations.

### Why migrate from Tauri to Swift

Tauri v2 (Rust + React) hit a hard architectural wall: **NSPanel**. macOS requires NSPanel for floating windows on fullscreen Spaces with keyboard input. Tauri only creates NSWindow. We spent 2 days trying every workaround:

- `object_setClass` NSWindow→NSPanel: fullscreen works but **keyboard input completely broken** (Window Server init path never runs)
- Real NSPanel + reparent WKWebView from Tauri's NSWindow: **events stop routing** (Tauri's event system bound to original NSWindow)
- NSWindow + CGSSpaceGetType + CanJoinAllSpaces + set_single_space: works on one machine but **fails on Sonoma**, relies on private API, 200ms race condition

These are not bugs — they are architectural limits of Tauri's window abstraction layer.

### Target architecture

Native Swift shell + WKWebView loading the existing React frontend. Same architecture as Raycast, Alfred, CleanShot X.

- **React frontend**: 100% reused, zero changes to JSX/CSS
- **Rust backend**: 100% rewritten in Swift (but largely mechanical translation)
- **IPC**: Tauri invoke → WKScriptMessageHandler + evaluateJavaScript

---

## Core Features & Expected Experience

### 1. Screenshot (Cmd+Shift+Z)
- Press shortcut → overlay appears **instantly** (pre-warmed, <50ms)
- Overlay covers full screen at ScreenSaver window level
- User drags to select area → selection border + dim mask
- Selection resize/move handles
- Edit toolbar appears (draw, arrow, text, blur, color/size)
- Chat panel appears beside selection
- User asks AI about the screenshot
- Pin: detach chat to standalone floating window
- Save/copy screenshot with annotations
- ESC cancels at any point

**Key experience**: trigger-to-visible must feel instant. Selection drag must be smooth (60fps target). Works on fullscreen Spaces.

### 2. Chat (Cmd+Shift+X)
- Press shortcut → chat window appears on current desktop/Space
- **Works on fullscreen Spaces** (floats on top, keyboard input works)
- **Stays on current desktop** when switching Spaces (doesn't follow)
- Compact window (432×412) with header, message area, input
- Supports text quoting: selected text from any app is captured and attached
- AI responds, window expands to 550 height
- Thread management: new chat, switch threads, clear all
- Model selection (Claude, GPT, Gemini)
- Pin to keep always-on-top

**Key experience**: must feel like a native floating panel. No Space switching, no wrong-screen appearance, keyboard always works.

### 3. Onboarding (Welcome flow)
- Step 0: Capture reveal animation (cursor dot → frame expand → color reveal → blink)
- Step 1: Permission grants (Screen Recording + Accessibility)
- Step 2: Try shortcuts
- Step 3: Pin demo
- Step 4: Tray reveal animation
- Step 5: API key setup or invite code

### 4. Tray icon
- Menu bar icon (template image, rounded stroke ends)
- Menu: Screenshot, Chat, recent threads, Settings, Quit
- Dynamic menu rebuild on thread save/delete

### 5. Settings
- Theme (light/dark/system)
- API keys (Anthropic, OpenAI, Gemini)
- Invite code
- Launch at login
- Save location
- Keyboard shortcuts display

---

## Tested Scenarios & Known Edge Cases

From CLAUDE.md and 2 days of intensive testing:

### Fullscreen Space
- Chat must appear ON the fullscreen Space, not on another desktop
- ESC in overlay must work (CGEventTap, not NSEvent monitor — Accessory policy blocks NSEvent)
- Closing overlay in fullscreen must not trigger macOS Space switch
- Pin from fullscreen screenshot → chat stays on fullscreen Space

### Multi-desktop
- Chat opened on Desktop A must NOT appear on Desktop B
- Closing chat on Desktop A, switching to Desktop B, opening chat → appears on B
- Chat window position: centered on the monitor where the cursor is

### Shortcut switching
- Cmd+Shift+X during screenshot → overlay closes, chat appears (shortcut = clear all + execute)
- Cmd+Shift+Z during chat → chat hides, screenshot triggers
- No "press twice" issues

### Window management
- Chat pre-warmed at startup (hidden, offscreen) for instant show
- Close chat = hide (not destroy) for reuse
- Overlay pre-warmed, reused for 2s after close, then destroyed + re-prewarmed
- Window position clamped to screen bounds

### Screenshot
- Selection resize/move: useRef + direct DOM (zero React re-render during drag)
- Minimum 10px selection threshold
- Window hover detection before selection
- Dimensions badge during drag

### Text quoting (Cmd+Shift+X)
- Simulates Cmd+C to grab selected text from any app
- Uses sentinel string in clipboard to detect "no selection" (prevents quoting stale clipboard)
- pbpaste -Prefer txt (prevents garbled terminal text)
- Accessibility permission required for keystroke simulation

### Permission flow
- Screen Recording: CGPreflightScreenCaptureAccess + CGRequestScreenCaptureAccess
- Accessibility: AXIsProcessTrustedWithOptions(prompt: true) — registers correct process identity
- Polling every 2s + check on window focus + visibilitychange
- Session-based localStorage to handle stale onboarding state across reinstalls

### API key management
- Keys stored in ~/Library/Application Support/glimpse/api_keys.json
- Auth errors → show API key setup (not generic error)
- Pending message auto-sends after key setup + connected animation
- Provider refresh on screenshot show (in case key was added in chat-only window)

### Animations
- Welcome Step 0: cursor dot → frame expansion → color reveal → blink → text cascade
- Glimpsing scan: drifting frame reveals eye (8s loop, inline 28×19)
- Connected wake-up: spiral draw → eye opens with overshoot → wink → gentle fade
- Eye animations: blink, squint (thinking), eyebrow hover/crossfade
- Chat window smooth resize (native animate_frame)
- Pin icon rotation 20°→0°
- Title reveal clip-path

### Toast
- Temp transparent window, auto-closes after 1.8s
- No NSWindow shadow (prevents border artifact)

---

## Migration Phases

### Phase 0: Skeleton + Validation (Day 1 morning)

**Goal**: Prove WKWebView + NSPanel + keyboard works.

**Build**:
1. Create Xcode project (or Swift Package Manager) with Swift AppDelegate
2. Create one NSPanel subclass (GlimpsePanel) with `canBecomeKey` returning true
3. Create WKWebView, load `dist/index.html#chat-only`
4. Implement minimal WKScriptMessageHandler (just `getApiKeys` → return empty)
5. Show panel, test keyboard input

**Checkpoint**:
- [ ] React frontend renders in NSPanel
- [ ] Can type in the textarea
- [ ] Window dragging works (-webkit-app-region: drag)
- [ ] Panel floats on fullscreen Space
- [ ] Panel stays on current desktop when switching

**Risk flags**:
- ⚠️ WKWebView might not load local file:// URLs without explicit allow — use `loadFileURL(_:allowingReadAccessTo:)`
- ⚠️ `-webkit-app-region: drag` might conflict with mouse events in certain areas
- ⚠️ NSPanel on fullscreen: test with AND without Accessory policy to determine what's actually needed

**Designer/User can help**: Nothing blocked — this is pure backend work.

### Phase 1: Chat MVP (Day 1 afternoon + Day 2)

**Goal**: Full chat flow works end-to-end.

**Build**:
1. Full IPC bridge (swift-shim.js replacing tauri-shim.js):
   - All `window.electronAPI.*` methods mapped to postMessage
   - Callback ID mechanism for invoke-style returns
   - Event dispatch (backend → frontend) via evaluateJavaScript
2. AI API calls (URLSession async/await):
   - Anthropic Claude
   - OpenAI GPT
   - Google Gemini
   - System prompt injection
   - Title generation
3. Thread persistence:
   - Save/load JSON in ~/Library/Application Support/glimpse/threads/
   - Recent threads list (max 5)
4. API key management:
   - Save/load/delete keys
   - Validate by test API call
   - Invite code validation
5. Preferences:
   - Theme, save location, launch at login
6. Global shortcut:
   - CGEventTap for Cmd+Shift+X
   - Handle shortcut = clear all + execute
7. Text quoting:
   - Cmd+C simulation via osascript
   - Sentinel clipboard mechanism
   - clear-text-context event before show
8. Chat window management:
   - Pre-warm at startup (offscreen, wait for ready signal)
   - Show on Cmd+Shift+X → position on cursor's monitor
   - Hide on close (not destroy)
   - Resize on AI reply (412 → 550, animate upward)

**Checkpoint**:
- [ ] Cmd+Shift+X opens chat
- [ ] Can type a question and get AI response
- [ ] Thread saved and appears in thread list
- [ ] Switch threads works
- [ ] New chat works
- [ ] Close and reopen preserves thread
- [ ] Text quoting from another app works
- [ ] Fullscreen: chat appears on fullscreen Space with keyboard
- [ ] Multi-desktop: chat doesn't follow to other desktops
- [ ] API key setup flow works (no key → setup → connected animation → auto-send)

**Risk flags**:
- ⚠️ IPC callback timing: evaluateJavaScript is async, WebView might not be ready
- ⚠️ CHAT_READY equivalent: need handshake before sending events to WebView
- ⚠️ Theme sync: localStorage 'glimpse-theme' must be readable by WKWebView

**Designer/User can help**:
- Test the IPC bridge by running the React dev server and loading in WKWebView
- Verify all animations play correctly in the new shell

### Phase 2: Screenshot Flow (Day 3 + Day 4 morning)

**Goal**: Full screenshot-to-chat flow works.

**Build**:
1. Overlay window:
   - NSPanel at ScreenSaver level (or NSWindow — overlay doesn't need NSPanel since it's always in Accessory mode)
   - Full screen, transparent, borderless
   - Pre-warmed at startup
   - accept_first_mouse for immediate interaction
2. Screen capture:
   - CGWindowListCreateImage for screen capture
   - CGWindowListCopyWindowInfo for window bounds
   - Run in parallel (separate threads/async)
3. Activation policy management:
   - Switch to Accessory BEFORE capture (synchronous, on main thread)
   - Restore to Regular when all windows closed
4. Overlay lifecycle:
   - Show → capture → emit screen-captured to WebView
   - Hide on close (reuse for 2s, then destroy + prewarm fresh)
   - Prewarm fresh overlay for fullscreen Space re-association
5. ESC detection:
   - Extend CGEventTap (already handling Cmd+Shift+X/Z) to detect keycode 53
   - Install when overlay shows, remove when overlay closes
   - Handle tap timeout (re-enable on 0xFFFFFFFE)
6. Pin flow:
   - Overlay chat → standalone chat panel
   - Transfer thread data + cropped image
   - Position chat at overlay panel's location
   - Close overlay after chat visible
7. Shortcut switching:
   - Cmd+Shift+X during screenshot: hide overlay, show chat
   - Cmd+Shift+Z during chat: hide chat, trigger screenshot
8. Screenshot data to WebView:
   - Write temp file, pass file URL (not base64 — performance improvement!)
   - Or: custom URL scheme handler
9. Save/copy image:
   - NSSavePanel for save
   - NSPasteboard for copy
   - Lower overlay during save dialog

**Checkpoint**:
- [ ] Cmd+Shift+Z shows overlay instantly
- [ ] Selection drag is smooth
- [ ] Selection resize/move works
- [ ] Chat panel appears beside selection
- [ ] AI can analyze the screenshot
- [ ] Pin works (overlay → standalone chat)
- [ ] ESC cancels selection/closes overlay
- [ ] Cmd+Shift+X during screenshot switches to chat
- [ ] Cmd+Shift+Z during chat switches to screenshot
- [ ] Fullscreen screenshot works
- [ ] Fullscreen pin works
- [ ] Save and copy work

**Risk flags**:
- ⚠️ Overlay window level: must be high enough to cover fullscreen apps but not system dialogs
- ⚠️ Prewarm timing: too aggressive = resource waste, too lazy = visible delay
- ⚠️ Screenshot image transfer: base64 is slow for 5K screens, file URL is better but WKWebView file access needs explicit permission
- ⚠️ Overlay reuse gap: 2s window between destroy and prewarm — screenshot during this gap needs fresh overlay path

**Designer/User can help**:
- Test screenshot quality (JPEG compression, retina rendering)
- Verify annotation tools work (draw, arrow, text, blur) — these are all React Canvas, should work unchanged
- Test on external monitors

### Phase 3: Polish & Parity (Day 4 afternoon + Day 5 morning)

**Goal**: Feature parity with Tauri v0.3.0.

**Build**:
1. Tray icon:
   - NSStatusItem with template image
   - NSMenu with Screenshot, Chat, recent threads divider, Settings, Quit
   - Dynamic rebuild on thread save/delete
2. Welcome/onboarding:
   - Welcome window (NSWindow, transparent, borderless)
   - WKWebView loads index.html#welcome
   - Permission checking + grant flow
   - Shortcut tried detection (from CGEventTap)
   - Onboarding completion marker
3. Settings window:
   - NSWindow, transparent, borderless
   - WKWebView loads index.html#settings
   - Position relative to tray icon or chat panel
4. Toast:
   - Borderless transparent NSWindow
   - HTML content or simple NSTextField
   - Auto-close after 1.8s
5. Remaining IPC commands:
   - openExternal (NSWorkspace.shared.open)
   - selectFolder (NSOpenPanel)
   - copyImage (NSPasteboard)
   - saveImage (NSSavePanel)
   - resizeChatWindow
   - inputFocus / lowerOverlay / restoreOverlay
6. App lifecycle:
   - Dock icon click → open chat or welcome
   - Reopen handler
   - Quit handler

**Checkpoint**:
- [ ] Tray icon visible with correct template image
- [ ] Tray menu shows recent threads
- [ ] Welcome flow completes successfully
- [ ] Permissions grant and show green checkmarks
- [ ] Settings opens and saves correctly
- [ ] Toast appears and auto-dismisses
- [ ] All IPC commands work

**Risk flags**:
- ⚠️ Toast window: transparent + no shadow requires same fixes as Tauri (setHasShadow: false + transparent bg)
- ⚠️ Welcome step persistence: uses localStorage in WKWebView — same WebKit storage path concerns

**Designer/User can help**:
- Walk through complete onboarding flow
- Verify all design details (spacing, colors, animations) match Tauri version
- Test on light and dark themes

### Phase 4: Testing & Ship (Day 5 afternoon)

**Goal**: Shippable .app with confidence.

**Build**:
1. Full regression test against Tauri version
2. Multi-monitor testing
3. Fullscreen Space testing (the whole reason we migrated!)
4. Memory profiling (WKWebView leak check)
5. Code signing setup (ad-hoc for now, Developer ID later)
6. DMG creation
7. GitHub release

**Test matrix**:

| Scenario | Expected |
|---|---|
| Fresh install, no prior data | Welcome flow starts |
| Cmd+Shift+Z non-fullscreen | Overlay instant |
| Cmd+Shift+Z fullscreen | Overlay on fullscreen Space |
| Selection → chat → pin | Pin to standalone window |
| Cmd+Shift+X non-fullscreen | Chat appears on current desktop |
| Cmd+Shift+X fullscreen | Chat floats on fullscreen |
| Cmd+Shift+X with selected text | Text quoted |
| Switch desktops | Chat stays on original desktop |
| Close chat → reopen | Instant (pre-warmed) |
| No API key → send message | API key setup appears |
| Add key → connected animation | Animation plays → auto-send |
| Delete all keys → send | API key setup appears |
| Multiple rapid Cmd+Shift+Z | All succeed |
| Screenshot → Cmd+Shift+X | Switch to chat |
| Chat → Cmd+Shift+Z | Switch to screenshot |
| Long conversation | Scroll works, no memory issues |
| Theme switch | All windows update |
| Tray → recent thread | Opens in chat |
| Quit and reopen | Threads persist |

**Checkpoint**:
- [ ] All test matrix scenarios pass
- [ ] No crashes in 30 minutes of normal use
- [ ] Memory stable (no growing leak)
- [ ] .app bundle created and signed
- [ ] DMG created
- [ ] Runs correctly on both Apple Silicon and Intel (if universal build)

**Risk flags**:
- ⚠️ Universal binary: Swift compiles for both architectures easily, but WKWebView behavior may differ
- ⚠️ Code signing: ad-hoc has TCC issues (same as Tauri). Developer ID signing is the long-term fix.

---

## Architecture Decisions to Lock In

Before writing code, confirm these:

1. **NSPanel for chat, NSWindow for overlay** — Chat needs keyboard + fullscreen floating. Overlay is always in Accessory mode at ScreenSaver level, NSWindow is fine.

2. **Single CGEventTap for all shortcuts + ESC** — One tap, filter by keycode + modifiers. Cleaner than separate systems.

3. **File URL for screenshot transfer** (not base64) — Performance win. Use `loadFileURL` or custom URL scheme.

4. **IPC via WKScriptMessageHandler** — JS calls `window.webkit.messageHandlers.glimpse.postMessage(...)`. Swift responds via `evaluateJavaScript`. Callback IDs for async returns.

5. **Keep React frontend unchanged** — tauri-shim.js replaced by swift-shim.js. Same `window.electronAPI` interface. Zero JSX/CSS changes.

6. **Data directory: ~/Library/Application Support/glimpse/** — Same path as Tauri for migration compatibility.

7. **Bundle ID: com.yifuwu.glimpse** — Same as Tauri for TCC permission compatibility.

---

## File Structure

```
glimpse-swift/
├── Glimpse/                    # Swift source
│   ├── AppDelegate.swift       # Entry point, app lifecycle
│   ├── GlimpsePanel.swift      # NSPanel subclass (canBecomeKey)
│   ├── WindowManager.swift     # Window creation, prewarm, show/hide
│   ├── ShortcutManager.swift   # CGEventTap for global shortcuts + ESC
│   ├── ScreenCapture.swift     # CGWindowListCreateImage + window bounds
│   ├── IPCBridge.swift         # WKScriptMessageHandler + command dispatch
│   ├── AIService.swift         # URLSession calls to Claude/GPT/Gemini
│   ├── ThreadStore.swift       # JSON persistence for threads
│   ├── SettingsStore.swift     # API keys, preferences
│   ├── PermissionManager.swift # Screen recording + accessibility checks
│   ├── TrayManager.swift       # NSStatusItem + dynamic menu
│   └── TextGrabber.swift       # Cmd+C simulation + sentinel clipboard
├── src/                        # React frontend (unchanged from Tauri)
├── dist/                       # Built frontend
├── icons/                      # App + tray icons
├── design/                     # Design specs + mockups
├── CLAUDE.md                   # Architecture docs (updated for Swift)
└── MIGRATION-PLAN.md           # This file
```
