# Build Audit — TODO for Builder

Audit of commit `8db5a8d` (Design system v1 — full visual redesign).
Prioritized by severity: P0 = must fix, P1 = should fix, P2 = nice to have.

---

## P0 — Must Fix

### 1. Welcome flow spacing — the "blob" problem
The `.welcome-step` class has **no gap or spacing defined**. All elements (logo, title, tagline, button) stack with default browser spacing, creating a chunky block. The `.welcome-content` has `padding: 0 40px 20px` but no `gap`.

**Fix:** Add to `.welcome-step`:
```css
.welcome-step {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 16px;       /* spacing between logo, title, tagline */
}
```
And add `margin-top: 24px` to `.welcome-btn` to separate the brand group from the CTA. The button should feel visually detached from the logo/title/tagline unit.

### 2. Welcome CTA button too wide
Button has `max-width: 280px` but `width: 100%` — on a 400px window with 40px padding it stretches to 320px. Needs to be `max-width: 260px` to feel like a focused action, not a full-width bar.

**Fix:** Change `.welcome-btn { max-width: 260px; }`

### 3. Light theme not applied anywhere
Light theme tokens are defined (`.theme-light` class) and the Settings theme toggle exists, but the app **defaults to dark**. Per spec, light should be the default. The `theme-light` class needs to be applied to the document root on first launch.

**Fix:** In `main.jsx` or the root component, check `localStorage.getItem('glimpse-theme')` and apply `theme-light` as default if no preference saved. Currently only `SettingsApp.jsx` handles theme switching.

### 4. Tagline still uses old copy
Welcome screen shows "Snap it. Ask it. Never lose your flow." — should be **"Glimpse your screen. Stay in flow."**

**Fix:** In `WelcomeApp.jsx`, change the welcome-desc text.

### 5. Legacy cyan aliases still in use
The builder added legacy aliases (`--cyan-primary: var(--brand)` etc.) which is smart for migration, but **8 places in the CSS still reference `var(--cyan-primary)` and `var(--cyan-dim)` directly**. These should be migrated to the proper token names.

Remaining references:
- `.scroll-to-bottom:hover` → `var(--cyan-glow)`
- `.chat-msg.assistant .msg-text a` → `var(--cyan-primary)`, `var(--cyan-dim)`
- `.edit-ai-toggle.active` → `var(--cyan-glow)`
- `.chat-header-chevron:hover` → `var(--cyan-primary)`
- `.thread-action-link:hover` → `var(--cyan-primary)`
- `.model-link:hover` → `var(--cyan-primary)`
- `.settings-invite-badge` → `var(--cyan-primary)`

**Fix:** Find-and-replace remaining `var(--cyan-*)` with the proper brand tokens, then remove the legacy aliases from `:root`.

---

## P1 — Should Fix

### 6. Attachment/snippet dark theme too faint
Per our latest audit, attachment cue background should be `rgba(108,99,255,0.12)` on dark (was 0.06). Border-left should be `0.35` (was 0.22). Snippet border should be `0.50`. Dismiss button should be simplified (no bg/border, just × in `--text-secondary`).

**Fix:** Apply the updated values from `design/CHAT-COMPONENT-SPEC.md` (just pushed).

### 7. No blockquote copy icon
The spec calls for dim copy icons on blockquotes (same pattern as code blocks). The builder implemented code block copy icons but **blockquotes still have no copy affordance** or still use the old "Copy" text button.

**Fix:** Add `.bq-copy-icon` (position: absolute, top-right, same dim style as code block copy) to the blockquote component in `ChatPanel.jsx`.

### 8. Thinking state uses old squint-loop, not focus-pulse
The CSS has both `thinkLoop` (the old squint animation, 2.4s) AND `focusPulse` (the new heartbeat, 1.6s) defined. The thinking indicator in `ChatPanel.jsx` should use the **focus-pulse eye + "Glimpsing..."** with synced text opacity — not the squint loop.

**Fix:** Verify `ChatPanel.jsx` uses `.glimpsing-eye` + `.glimpsing-text` classes, not the old `.logo-think` class. The `thinkLoop` keyframes can stay (used for API key verification squint in header).

### 9. Chat header missing eye icon
Per spec, the header should be: `[eye] [title ▼] ... [+new] | [pin]`. Need to verify the Glimpse eye icon is present as the first element in the header (brand presence, wiggle on click).

### 10. Settings: no version info in footer
Spec calls for "Glimpse v1.0" on the left side of the settings footer. Need to verify this was added.

### 11. Welcome step 3: pin icon still cyan?
The original code had `stroke={pinnedEgg ? '#00E5FF' : '#00E5FF'}`. Should be `#6C63FF`.

**Fix:** Check `WelcomeApp.jsx` step 3 pin icon stroke color.

---

## P2 — Nice to Have

### 12. Welcome delight moments not verified
The spec calls for:
- Draw-on + blink combo on step 0 (CSS exists as `.logo-draw-blink` — verify it works)
- Green check stroke-draw animation on permission granted (step 1)
- CTA scale pop when both shortcuts complete (step 2) — `.btn-pop` class exists
- Active dot pulse on step 3 load

These are subtle — verify they're wired up in the JSX, not just defined in CSS.

### 13. API key setup delight
- Header eye should squint-loop during "Verifying..." state
- Header eye should double-blink on key saved
- Success transition ("Key added. Happy chatting!") should show double-blink eye

### 14. Code block header — light theme colors
The code block header uses hardcoded dark values (`background: rgba(31, 29, 42, 0.80)`). In light theme this needs to be `var(--surface-elevated)`. Check if the light theme override is missing.

### 15. Remove the `max-width: 400px` removal
The builder removed `max-width: 400px` from `.welcome-content`. This might cause the welcome content to stretch too wide on larger windows. Verify the window size is constrained by Tauri config, or add the max-width back.

### 16. Wordmark weight
Current: Outfit 600 on welcome title. Per our latest decision: Outfit 500 with `letter-spacing: 0.02em`. Not urgent — can be updated when tagline changes.

---

## What's Done Well ✓

- Token system fully implemented (brand, surfaces, borders, text, shadows, spacing, radii)
- Light theme tokens defined correctly
- Soft Lavender pinned tokens defined
- Polished logo SVG paths everywhere
- Draw-on, squint-loop, double-blink, focus-pulse animations all in CSS
- Code block header with language label + icon-only copy button
- Colorblind-safe 7-color annotation palette
- Selection border: static, round handles, no glow/brackets/pulse
- overlayExit replaced with simple fade
- selectionPulse and shortcutPulse removed
- prefers-reduced-motion implemented
- focus-visible implemented
- ARIA labels added to chat panel buttons
- Settings: theme toggle, delete confirmation, shortcuts note, version footer
- API key setup: "Connect to AI" title, solid CTA, copy changes
- App icon regenerated with polished logo
- All font sizes ≥ 11px
- Monospace reserved for code/keys/kbd/model names
