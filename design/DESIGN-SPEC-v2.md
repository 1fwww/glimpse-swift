# Glimpse Design Specification — v2

> Updated 2026-04-08 after comprehensive design review session.
> Reflects actual implementation state. Changes from v1 marked with ⚡.

---

## 1. Design Principles

1. **Respect the user's focus.** Glimpse is a utility, not a destination. Show up, help, get out of the way. Less, then less again.
2. **Feel native, not web.** Respect macOS conventions. Tray icons, ESC to close, pixel-perfect edges. Users should never think "this is a webpage in a window."
3. **Tangible over digital.** Physical metaphors: pins that rotate in, surfaces that feel like frosted glass, an eye that blinks. No glowing gradients, no color washes, no "screen filter" effects.
4. **The eye is the product.** The Glimpse companion isn't a logo — it's a personality. Resting, focused, thinking, delighted. Every state change is an opportunity for the eye to respond.
5. **Accessible by default.** WCAG AA minimum. Color blindness safe. Reduced motion support. If it's interactive, it has a label.

---

## 2. Typography

Unchanged from v1. All UI text uses `--font-display` (Outfit). Mono only for code, API keys, kbd, model names. Minimum font size 11px (`--text-xs`).

⚡ **Enforced:** All 15 instances of `font-size: 10px` have been replaced with `var(--text-xs)`.

---

## 3. Color System

### Tokens

Unchanged from v1. Brand, semantic, surface, border, text tokens all as specified.

### ⚡ Token Enforcement

- Zero `rgba(255,255,255,...)` in component CSS — all replaced with `var(--surface-hover)`, `var(--border-dim)`, etc.
- Zero hard-coded greens — all iOS green (`#34c759`, `rgba(52,199,89,...)`) replaced with `var(--success)` / `var(--success-muted)`
- Zero cyan/magenta — including canvas selection handles (now brand purple)
- Zero `#ff453a` — replaced with `var(--error)`
- Zero `#0e1420` — replaced with `var(--surface-deep)`

### ⚡ Pinned State Colors — Revised

**Overlay mode** (chat panel floating over screenshot):
```css
/* Dark */
.chat-panel.pinned-panel {
  background: rgba(22, 21, 30, 0.97);
  border: 1.5px solid rgba(108, 99, 255, 0.20);
  box-shadow:
    0 8px 32px rgba(108, 99, 255, 0.08),
    0 20px 60px rgba(0, 0, 0, 0.35),
    0 2px 6px rgba(108, 99, 255, 0.04);
  transform: scale(1.015) translateY(-4px);
}

/* Light */
.theme-light .chat-panel.pinned-panel {
  background: rgba(248, 247, 252, 0.97);
  border: 1.5px solid rgba(108, 99, 255, 0.22);
  box-shadow:
    0 8px 32px rgba(108, 99, 255, 0.10),
    0 20px 60px rgba(0, 0, 0, 0.15),
    0 2px 6px rgba(108, 99, 255, 0.06);
  transform: scale(1.015) translateY(-4px);
}
```

**Chat-only mode** (standalone window) — ⚡ NEW:

Cannot use scale/external shadow (clipped by macOS window bounds). Cannot use `backdrop-filter` (Tauri floating window can't blur desktop). Pinned background must be **100% opaque** (semi-transparent causes visible antialiased edge at border-radius).

```css
/* Dark — "smoked glass" direction */
.chat-only-app .chat-panel.pinned-panel {
  background: #222131;  /* lighter than base #16151E, cool purple-gray */
  padding: 2px;  /* content tightens inward */
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.15),
    inset 0 -1px 0 rgba(255, 255, 255, 0.03);
}

/* Light — "frosted glass" direction */
.theme-light .chat-only-app .chat-panel.pinned-panel {
  background: #F3F4F9;  /* cooler than base #FAFAFC */
  padding: 2px;
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.8),
    inset 0 -1px 0 rgba(0, 0, 0, 0.04);
}
```

**Design decision:** User prefers frosted glass / cool neutral direction over purple tint for large surfaces. Purple is reserved for small accents (pin button, borders, brand text).

**No `backdrop-filter`** in any pinned state. The Tauri floating window sits above the OS desktop — blur can't see through to it.

---

## 4. Logo & Animation

### Three Animation Contexts

Unchanged from v1: Draw On, Squint Loop, Double Blink.

### ⚡ Additional Animation: Draw On (fast variant)

For header eye "new thread" animation — faster easing to avoid sluggish spiral tail:
```css
.logo-draw-only svg path:first-child {
  animation: drawBrow 0.45s cubic-bezier(0.25, 0.46, 0.45, 0.94) forwards;
}
.logo-draw-only svg path:last-child {
  animation: drawEye 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94) 0.1s forwards;
}
```

### ⚡ Eyebrow Shape Change (pinned state)

Two eyebrow paths — crossfade via opacity:
```
Resting (curved):  M98 212C152 174 365 158 420 248
Focused (straight): M98 192C200 192 350 204 420 234
```
Pinned = focused eyebrow (companion is "locked in"). Crossfade 0.3s ease.

---

## 5. Motion & Animation

### ⚡ New Micro-interactions

| Trigger | Animation | Duration |
|---|---|---|
| Send message | Button `scale(0.88)` press | 0.08s |
| New chat (+) | Button `scale(0.82)` press + eye draw-on + title reveal | 0.3s / 0.7s / 0.4s |
| Pin toggle | Pin icon rotate 20°→0° + eyebrow crossfade + eye blink + content padding 2px | 0.3s each |
| AI response complete | (removed — distracted from reading) | — |
| Title change (user action) | `clip-path` reveal left→right | 0.4s |
| Toolbar eye hover | Eyebrow lift translateY(-18px) rotate(-3deg) | 0.25s |
| Welcome step transition | Directional slide (forward=right, back=left) | 0.3s |

### ⚡ Pin Icon Rotation
```css
.chat-header-pin svg {
  transform: rotate(20deg);  /* unpinned: tilted */
  transition: transform 0.3s cubic-bezier(0.22, 1, 0.36, 1);
}
.chat-header-pin.pinned svg {
  transform: rotate(0deg);  /* pinned: straight (pushed in) */
}
```

### Title Reveal (user-initiated only)
Only triggers on: new thread button click, thread switch click.
Does NOT trigger on AI-generated title updates (user's attention is on messages).
```css
@keyframes titleReveal {
  from { clip-path: inset(0 100% 0 0); }
  to { clip-path: inset(0 0 0 0); }
}
```

---

## 6. Code Blocks — ⚡ REVISED

### Before (v1): 3-layer nested card
```
wrapper (border + radius) > header (bg) > pre (bg) = nested card anti-pattern
```

### After (v2): Single recessed layer
```css
.code-block-wrapper {
  background: rgba(0, 0, 0, 0.18);  /* dark */
  border-radius: 6px;
  overflow: hidden;
  /* NO border, NO separate header bg, NO pre bg */
}
.theme-light .code-block-wrapper {
  background: rgba(0, 0, 0, 0.04);
}
```

Header is transparent with only a `border-bottom: 1px solid var(--border-dim)` divider. Code content (`pre`) has `background: none`.

### Blockquote + Code Block
When a blockquote contains a code block, blockquote styling is auto-stripped via CSS `:has()`:
```css
.bq-copyable:has(.code-block-wrapper) {
  border-left: none;
  background: none;
  padding: 0;
  margin: 0;
}
.bq-copyable:has(.code-block-wrapper) > .bq-copy-btn {
  display: none;
}
```

### Inline Code Detection
react-markdown v10: `inline` prop doesn't exist. Detect fenced blocks by `language-*` className. No className = inline code.

---

## 7. Blockquote

```css
.bq-copyable {
  border-left: 2px solid rgba(108, 99, 255, 0.35);
  background: rgba(108, 99, 255, 0.08);  /* ⚡ strengthened from 0.04 */
  padding: 9px 32px 9px 12px;
  border-radius: 0 8px 8px 0;
}
```

---

## 8. Chat Header — ⚡ REVISED

### Layout
```
[Eye] [Title ▾] ............ [+ New] [Pin]
```

⚡ **No separator** between New Chat and Pin buttons. They're the same "window action" group.

### Pin Button
⚡ Border matches New Chat button: `1.5px solid var(--border-active)`.

### Header Eye
- Click: double blink (0.9s)
- Pinned: eyebrow crossfade curved→straight
- `GlimpseIcon` accepts `focused` prop for eyebrow state

### Footer
⚡ Interactive elements use `var(--text-secondary)` (5.3:1 AA) not `var(--text-dim)` (3.4:1).
"Esc to close" shows whenever `chatFullSize` is true (chat-only mode, pinned) or no screenshot attached.

### "Glimpsing..." Loading Text
⚡ Color: `var(--brand-text)` (was `var(--text-dim)`). Brand moment — companion is working.

---

## 9. Welcome Flow — ⚡ REVISED

### Step 3: Pin Demo
⚡ Replaced static "click card to see it glow" with interactive mini chat panel:
- Simulated desktop background (gray lines)
- Mini chat panel with header, messages, input
- Pin button with breathing pulse hint (`box-shadow` 2s cycle)
- Click pin → panel transition (matches real pinned behavior)
- Pin icon rotates 20°→0° (matches real chat header)
- Eye crossfade curved→straight (matches real chat header)
- Only pin button triggers — card not fully clickable
- "New Thread" → "New Chat" (consistent terminology)

### Step Transitions
⚡ Directional: forward slides right, back slides left (20px + opacity).

### Nav Dots
⚡ `<button role="tab">` with `aria-label="Step N: Name"`. Disabled for future steps.

### API Key Hint
⚡ "Settings" is clickable (`welcome-hint-link`), opens Settings window directly.

---

## 10. Settings — ⚡ REVISED

### Entrance Animation
⚡ `settingsIn`: scale 0.97→1 + opacity fade, 0.2s.

### Toggle Switch
⚡ `role="switch"` + `aria-checked` + `aria-label`.

### Invite Code
⚡ "Use my own keys" button changed from filled brand button to text link (`settings-invite-link`). Filled button implied active state; link correctly implies action.

### Section Titles
⚡ `var(--text-secondary)` (was `var(--text-dim)`) for AA contrast.

### Input Fields
⚡ `background: var(--surface-input)` (was `rgba(0,0,0,0.3)`).

---

## 11. API Key Setup (in-chat) — ⚡ REVISED

### Success Message
⚡ "Connected. Happy Glimpsing!" (was "Key added. Happy chatting!")

### Token Fixes
- `font-family: var(--font-body)` → `var(--font-display)` (typo fix)
- Saved provider check: `var(--success)` via `currentColor` (was `#34c759`)
- Save hover: `var(--brand-btn-hover)` (was `#5B53E0`)

---

## 12. Edit Toolbar — ⚡ REVISED

### Selection Handles
⚡ Brand purple `rgba(108, 99, 255, ...)` (was cyan `rgba(0, 229, 255, ...)`). Zero cyan remaining.

### AI Toggle Eye
⚡ Eyebrow lifts on hover: `translateY(-18px) rotate(-3deg)`, 0.25s.

### All Buttons
⚡ Every button has `aria-label`. Tool buttons have `aria-pressed`. Color dots have color names.

---

## 13. Model Dropdown — ⚡ REVISED

### Provider Grouping
- Single provider: no section header (no need for grouping)
- Multiple providers: 10px section header + divider between groups
- Model items indented 14px (vs provider 8px)

---

## 14. Accessibility Summary — ⚡ NEW

### ARIA Coverage
- All icon-only buttons: `aria-label`
- Thread menu: `role="menu"` + `role="menuitem"` + `aria-expanded` + `aria-haspopup`
- Model dropdown: same
- Welcome dots: `role="tab"` + `aria-label` + `aria-selected`
- Toggle switch: `role="switch"` + `aria-checked`
- Chat textarea: `aria-label="Message input"`
- All inputs in settings/API setup: `aria-label`

### Contrast
- Interactive elements: `var(--text-secondary)` minimum (5.3:1 dark, 5.2:1 light) ✓ AA
- `var(--text-dim)` (3.4:1) only for non-interactive: placeholders, timestamps, model tags
- Screenshot mode toast: hardcoded `rgba(255,255,255,0.9)` (dark bg, always white text)

### Minimum Font Size
11px (`var(--text-xs)`) enforced everywhere. Zero instances of `font-size: 10px`.

---

## 15. Known Constraints — ⚡ NEW

### macOS Transparent Window + CSS border-radius
Semi-transparent backgrounds create visible antialiased edge at rounded corners. **Pinned backgrounds in chat-only mode must be 100% opaque** (use `#hex` not `rgba(..., 0.9x)`).

### backdrop-filter in Tauri
Does NOT work for floating windows — can only blur content within the same WebView. Only valid during screenshot overlay mode (chat panel over screenshot).

### CSS specificity: pinned-panel
`.theme-light .chat-panel.pinned-panel` can leak border/background into chat-only mode. Chat-only pinned overrides must explicitly set `border: 1px solid transparent`.

### Tray Icon (macOS Tahoe)
Requires "Allow in Menu Bar" permission (System Settings → Menu Bar). May not appear until user manually enables. Known Tauri v2 issue #13770.

---

## 16. TODO

- [ ] Screenshot → Pin transition slow (~1s). Root cause: new webview creation. Fix: pre-warm chat window.
- [ ] Screenshot selection drag performance (mousemove triggers full React re-render)
- [ ] Fullscreen overlay may appear on wrong Space after hide+delayed-close prewarm
- [ ] Replace Home window with tray-only mode (blocked by macOS Tahoe tray permission UX)
