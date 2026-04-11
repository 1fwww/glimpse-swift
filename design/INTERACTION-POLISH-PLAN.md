# Glimpse — Interaction Polish Plan

> Source of truth for window behavior, animation, and micro-interaction upgrades.
> Architecture: Swift shell (NSPanel/NSWindow) + WKWebView + React. UI is CSS — Swift controls window-level behavior.
> Design principles: Disappear when not needed · Calm over clever · Warm not clinical · Respect focus · Accessible by default.

---

## Architecture Rule: Single Owner

Every animation has ONE owner — either Swift or CSS, never both simultaneously.

- **Swift owns**: window alpha, position (origin), frame size (resize)
- **CSS owns**: shadow, border, background color, content layout, internal transitions
- **Coordination**: Swift calls `evaluateJavaScript` to trigger CSS changes. ~5-15ms IPC delay is imperceptible. No sync protocol needed.

---

## Priority Order

| # | Topic | Why this order |
|---|---|---|
| **P0** | Window edge & shadow | Constant visual — 100% of user time. Foundation for everything else. |
| **P1** | Chat resize | Highest-frequency interaction. Every conversation. |
| **P2** | Window show / hide | Window must look good (P0) before its entrance matters. |
| **P3** | Pin transition | Depends on P0 (shadow), P1 (resize), P2 (window appear). Subset of users. |
| **P4** | Adaptive toolbar | Independent exploration. After core four are solid. |

---

## P0 — Window Edge & Shadow

**Decision: Option B — stronger ring + shadow, keep warm gray surface.**

### What to change

**Scope: ONLY `border` and `box-shadow` on `.chat-only-inner`.** Do not change background colors, button styles, or any other properties.

**Light mode — unpinned:**
```css
.chat-only-inner {
  border: none;  /* remove 1px solid border */
  box-shadow:
    0 0 0 0.5px rgba(0, 0, 0, 0.12),        /* edge ring — defines boundary */
    0 1px 2px rgba(0, 0, 0, 0.06),            /* contact shadow — grounds it */
    0 4px 16px rgba(0, 0, 0, 0.08),           /* ambient shadow — depth */
    inset 0 0.5px 0 rgba(255, 255, 255, 0.7); /* top highlight — glass edge */
}
```

**Light mode — pinned:**
```css
.chat-only-inner.pinned {
  box-shadow:
    0 0 0 0.5px rgba(108, 99, 255, 0.12),       /* brand-tinted ring */
    0 2px 4px rgba(0, 0, 0, 0.04),               /* contact — lighter (floating) */
    0 8px 28px rgba(0, 0, 0, 0.08),              /* ambient — deeper + wider */
    0 0 0 1px rgba(108, 99, 255, 0.06),          /* subtle brand halo */
    inset 0 0.5px 0 rgba(255, 255, 255, 0.6);   /* top highlight */
}
```

**Dark mode — unpinned:**
```css
/* Dark mode: ring uses white instead of black */
.theme-dark .chat-only-inner {
  border: none;
  box-shadow:
    0 0 0 0.5px rgba(255, 255, 255, 0.08),
    0 1px 2px rgba(0, 0, 0, 0.3),
    0 4px 16px rgba(0, 0, 0, 0.4),
    inset 0 0.5px 0 rgba(255, 255, 255, 0.06);
}
```

**Dark mode — pinned:**
```css
.theme-dark .chat-only-inner.pinned {
  box-shadow:
    0 0 0 0.5px rgba(108, 99, 255, 0.2),
    0 2px 4px rgba(0, 0, 0, 0.25),
    0 8px 28px rgba(0, 0, 0, 0.45),
    0 0 0 1px rgba(108, 99, 255, 0.08),
    inset 0 0.5px 0 rgba(255, 255, 255, 0.04);
}
```

### Swift side

```swift
// GlimpsePanel — final form (when moving past Phase 0)
hasShadow = false          // disable system shadow, CSS controls it fully
backgroundColor = .clear   // fully transparent, CSS background does the work
```

### Why this matters
Ring at 12% (up from 6%) + ambient at 8% (up from 6%) gives the window presence on any background while keeping the warm gray `--surface-base`. The 0.5px ring replaces the 1px border — thinner, more refined on Retina, defined by shadow rather than stroke.

### Verify
- Open on light macOS wallpaper — window should be clearly distinct
- Open on white webpage — should not "melt"
- Open on dark IDE — shadow should be visible
- Compare pinned vs unpinned — pinned should feel elevated

---

## P1 — Chat Window Resize

**Current state:** `resize_chat_window` IPC is a no-op. Window is fixed 432×412. Content fills 100% and scrolls.

### Layer 0 — Basic resize ability (Swift)

Implement `resize_chat_window` in IPCBridge.swift:

```swift
case "resize_chat_window":
    guard let size = args["size"] as? [String: Any],
          let height = size["height"] as? CGFloat else { return true }
    
    let panel = /* reference to chatPanel */
    let current = panel.frame
    var newFrame = current
    newFrame.size.height = height
    
    // Bottom-anchored: top edge moves, bottom stays
    newFrame.origin.y = current.origin.y + current.size.height - height
    
    // Clamp to screen
    if let screen = panel.screen {
        let visible = screen.visibleFrame
        newFrame.origin.y = max(visible.minY, newFrame.origin.y)
        newFrame.size.height = min(height, visible.height * 0.75)
    }
    
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.35
        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        panel.animator().setFrame(newFrame, display: true)
    }
    return true
```

Spring parameters — **start over-damped, tune on device:**
```
Start:    response 0.35, dampingRatio 0.92  (almost no bounce)
Try:      response 0.35, dampingRatio 0.85  (micro-bounce)
Target:   response 0.38, dampingRatio 0.78  (visible settle)
```
Resize triggers content reflow — high damping prevents reflow-induced jank.

### Layer 1 — Smart triggers (implement as atomic unit)

These two MUST ship together — doing P0 without P1 creates a worse experience than the current fixed-size baseline.

**New chat (empty):**
```
createChatWindow({ height: 360 })   // compact
```

**Open existing chat (has messages):**
```
createChatWindow({ height: 520 })   // expanded, no animation, correct from start
```

**First AI response starts streaming:**
```javascript
// In ChatPanel.jsx, when first assistant message appears:
if (isFirstResponse) {
  window.electronAPI?.resizeChatWindow?.({ height: 520 })
}
```
This is the ONE animated resize per conversation. 360 → 520, bottom-anchored, spring.

**New chat (clear/reset):**
```javascript
// When user clicks "New chat":
window.electronAPI?.resizeChatWindow?.({ height: 360, force: true })
```
`force: true` allows shrinking (normally resize only grows during conversation).

### Layer 2 — Attachment-aware sizing (after Layer 1 is stable)

| State | Compact height | Notes |
|---|---|---|
| Empty | 360 | Baseline |
| With text quote | 390 | +30 for snippet |
| With screenshot | 390 | +30 for attachment cue |
| With both | 420 | +60 combined |

Only implement after Layer 0+1 are stable and feel good. Each trigger is independent and can be added/tested individually.

### What NOT to do
- No progressive resize during streaming (too risky, jank potential)
- No width changes (keep 432 fixed — width resize adds complexity for minimal gain)
- No resize on every message (only on first AI response)

---

## P2 — Window Show / Hide

**Decision: Scale + Opacity (Raycast style), no directional movement.**

### Show animation (~200ms)

**Swift layer (window):**
```swift
func showChat() {
    guard let panel = chatPanel else { return }
    
    // Start invisible and slightly scaled down
    panel.alphaValue = 0
    // Position at target location (screen center or cursor monitor)
    positionOnCurrentMonitor(panel)
    panel.makeKeyAndOrderFront(nil)
    
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        panel.animator().alphaValue = 1
    }
}
```

**CSS layer:**
Remove existing `panelSlideIn` animation on `.chat-panel`. The window-level fade handles entrance — CSS content comes along for the ride. No double-animation.

**Scale note:** NSPanel doesn't have a direct `transform: scale()` equivalent. Two approaches:
- **Option A:** Pure opacity fade (simpler, still a big upgrade from instant `orderFront`)
- **Option B:** Briefly set frame 2% smaller, then animate to target frame alongside opacity (adds scale feel, but more code)

Recommend starting with **Option A**. If it feels insufficient, try B.

### Hide animation (~120ms)

```swift
func hideChat() {
    guard let panel = chatPanel else { return }
    
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.12
        ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
        panel.animator().alphaValue = 0
    }, completionHandler: {
        panel.orderOut(nil)
        panel.alphaValue = 1  // reset for next show
    })
}
```

Pure opacity fade, no position change. Fast exit = "still here, just stepped back." Asymmetric timing (show 200ms > hide 120ms) matches natural expectation: arriving takes longer than leaving.

### Shadow behavior
Shadow is CSS (box-shadow on `.chat-only-inner`). Since it's inside the WKWebView, it fades with the window's alpha automatically. No extra work needed.

---

## P3 — Pin Transition

**Decisions: Both single-window and cross-window preserved for builder evaluation. Glow ring kept (evaluate in practice). Content micro-stagger removed.**

### Approach A — Single Window (safe)

Pin doesn't create a new NSPanel. The existing chat window stays; overlay fades out.

**Timeline (~600ms):**

```
T+0ms     [CSS]    Pin button press feedback
                    scale(1) → scale(0.85) → scale(1.02) → scale(1)
                    200ms, ease-out

T+50ms    [Swift]   Overlay window: alpha 1 → 0 (250ms, ease-out)
                    Selection: fade with overlay

T+100ms   [Swift]   evaluateJavaScript → add .pinned class to .chat-only-inner

T+100ms   [CSS]    Shadow transition: unpinned → pinned (values from P0)
                    Border: brand-tinted ring appears
                    Background: shift to --surface-pinned
                    All 450ms, cubic-bezier(0.22, 1, 0.36, 1)

T+150ms   [Swift]   Panel origin.y += 6 (lift)
                    spring(response: 0.5, dampingRatio: 0.72)
                    Subtle physical "float up"

T+300ms   [CSS]    Pin button fills with brand color
                    400ms transition

T+600ms            Complete.
```

**Glow ring (optional, evaluate on device):**
At T+200ms, CSS plays a one-shot glow:
```css
.pin-glow {
  box-shadow: 0 0 0 2px rgba(108,99,255,0.3), 0 0 20px rgba(108,99,255,0.15);
  animation: pinGlow 500ms cubic-bezier(0.22, 1, 0.36, 1) forwards;
}
@keyframes pinGlow {
  0%   { opacity: 0; }
  40%  { opacity: 0.8; }
  100% { opacity: 0; }
}
```
If it feels "clever over calm" in practice, remove it. The shadow depth change alone may be sufficient.

### Approach B — Cross-Window (ambitious)

Creates a new NSPanel at the exact position of the overlay's chat panel, crossfades.

**Additional requirements:**
- Pre-warm a second WKWebView at startup (memory cost: ~50-80MB)
- OR attempt WKWebView reparent from overlay to new panel
- Coordinate thread data transfer before crossfade

**Timeline adds a crossfade phase:**
```
T+80ms    [Swift]   New NSPanel created, alpha=0, at overlay chat position
T+120ms   [Swift]   Crossfade: new panel alpha 0→1, overlay alpha 1→0 (200ms)
T+320ms   [Swift]   Overlay destroyed. New panel is standalone.
T+350ms+           Same lift + CSS transition as Approach A
```

**Risk:** WKWebView in new panel may not be rendered yet → white flash during crossfade.
**Mitigation:** Test WKWebView reparent first. If white flash occurs, fall back to Approach A.

**Recommendation to builder:** Implement Approach A first. If the "moment of pin" feels insufficiently distinct (overlay vanishes, chat just sits there), then explore Approach B.

### Unpin

**If overlay is active:** Reverse — panel sinks 6pt, shadow returns to unpinned values, overlay fades back in.
**If no overlay:** Panel fades out (reuse P2 hide animation). Next Cmd+Shift+X opens fresh chat.

---

## P4 — Adaptive Annotation Toolbar

**Concept:** Screenshot annotation toolbar adapts its appearance based on the screenshot content directly behind it.

**Why it works here (but not for floating windows):**
- Screenshot is frozen/static — sample once, no flickering
- Functional value — toolbar is always readable regardless of screenshot content
- Aligns with "calm" — adaptation is invisible, user just perceives "it looks right"
- Image data already in memory (CGImage from capture) — zero extra cost

### Phase 1 — Binary luminance adaptation

```
Screenshot captured
→ Crop CGImage to toolbar region (known position, ~toolbar height × toolbar width)
→ Downsample to 8×4 pixels (CIFilter or vImage)
→ Calculate average luminance (0.0–1.0)

if luminance > 0.55:
    // Light screenshot content → dark toolbar
    toolbar-bg: rgba(0, 0, 0, 0.55)
    backdrop-filter: blur(12px) saturate(1.2)
    icon-color: rgba(255, 255, 255, 0.9)
    
else:
    // Dark screenshot content → light toolbar  
    toolbar-bg: rgba(255, 255, 255, 0.65)
    backdrop-filter: blur(12px) saturate(1.1)
    icon-color: rgba(0, 0, 0, 0.75)
```

**Edge case — high variance (half light, half dark):**
If luminance standard deviation > 0.25, default to dark toolbar (safer — dark bg + white icons is more universally readable).

**Transition:** If user moves/resizes selection and toolbar repositions over different content, re-sample and crossfade (150ms) between modes. No jarring switch.

### Phase 2 — Subtle warmth tint (after Phase 1 is proven)

Extract color temperature from sampled region:

```
Warm content (photos, designs, warm UI) → add rgba(255, 240, 220, 0.04) tint
Cool content (code, terminal, blue UI)  → add rgba(220, 230, 255, 0.04) tint
Neutral                                 → no tint
```

4% opacity is subliminal — user won't consciously notice, but toolbar "belongs."

### Implementation notes

**Swift side:**
```swift
func adaptToolbar(for image: CGImage, toolbarRect: CGRect) -> ToolbarAppearance {
    // Crop to toolbar region
    guard let cropped = image.cropping(to: toolbarRect) else {
        return .default
    }
    
    // Downsample to tiny size for fast average
    let luminance = averageLuminance(of: cropped)  // vImage or manual pixel walk
    
    return luminance > 0.55 ? .darkOnLight : .lightOnDark
}
```

**Communication to React:**
```javascript
// Swift sends toolbar mode before showing overlay UI
window.electronAPI?.onToolbarMode?.((mode) => {
    // mode: "light" | "dark"
    document.documentElement.setAttribute('data-toolbar-mode', mode)
})
```

**CSS:**
```css
[data-toolbar-mode="dark"] .annotation-toolbar {
    background: rgba(0, 0, 0, 0.55);
    color: rgba(255, 255, 255, 0.9);
}
[data-toolbar-mode="light"] .annotation-toolbar {
    background: rgba(255, 255, 255, 0.65);
    color: rgba(0, 0, 0, 0.75);
}
```

### Verify
- Screenshot white webpage → toolbar should be dark mode
- Screenshot dark IDE → toolbar should be light mode
- Screenshot mixed content → should pick a reasonable default
- Move selection across light/dark boundary → smooth crossfade, no jarring switch

---

## Decisions Log

| # | Decision | Date | Notes |
|---|---|---|---|
| 1 | Window show: Scale + Opacity (A) | 2026-04-11 | No directional movement. Raycast style. |
| 2 | Pin: Both approaches preserved | 2026-04-11 | Builder to evaluate. Start with single-window (A). |
| 3 | Pin glow ring: Keep | 2026-04-11 | Evaluate in practice. Remove if "clever over calm." |
| 4 | Pin content stagger: Remove | 2026-04-11 | Messages stay still. Stability = "content intact." |
| 5 | Window edge: Option B | 2026-04-11 | Stronger ring 12% + shadow 8%. Keep warm gray surface. |
| 6 | Adaptive toolbar: Approved | 2026-04-11 | Phase 1 binary luminance. After core four. |

---

## Mockup References

| Topic | File |
|---|---|
| Window edge & shadow | `mockups/window-edge-shadow.html` — Option B selected |
| Pin transition | `mockups/pin-transition-anim.html` — CSS phase reference |
| Pin variants | `mockups/pin-transition-v2.html`, `v3.html` |

---

## For the Builder

**Read this first:** This plan defines WHAT and WHY. The exact spring parameters, timing values, and CSS properties are starting points — tune on device.

**Scope control:** Each P-level is independent and shippable. Do not start P(n+1) until P(n) is verified. Within each P-level, follow the layer order (Layer 0 before Layer 1).

**What not to touch:** This plan only covers window behavior and animation. Do not modify: chat message rendering, API logic, thread management, onboarding flow, or any functionality beyond window presentation.
