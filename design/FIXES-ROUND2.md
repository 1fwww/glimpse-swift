# Fixes Round 2

Items from design review session. In priority order.

---

## 1. Welcome button sizing (all steps)

The "Get Started" / "Continue" / "Try both to continue" buttons are too wide, too thick, and too pill-shaped.

```css
.welcome-btn {
  max-width: 260px;        /* was 280 or wider */
  padding: 12px 20px;      /* verify — no thicker */
  border-radius: var(--radius-md);  /* 12px, NOT pill/capsule */
  font-size: var(--text-md);        /* 14px */
  margin-top: 24px;        /* separate button from tagline/content above */
}
```

Apply to ALL welcome step buttons consistently.

---

## 2. Welcome Step 3 — Pin highlight

Remove the breathing pulse animation on the pin button. Replace with static visual hierarchy:

- All mini-chat demo elements (eye, title, +new button, separator, messages, input): `opacity: 0.3`
- Pin button stays `opacity: 1` + `background: var(--brand-dim)` + `border-color: var(--brand-border)` + `color: var(--brand-text)` + slightly larger: `width: 26px; height: 26px` (other buttons are 22px)

No animation. The pin stands out because everything else steps back.

Reference: `design/mockups/pin-highlight.html` Option 4.

---

## 3. "Glimpsing..." text color

Currently uses `var(--brand-text)` (purple) — too prominent. The eye icon already carries the brand color.

**Change to:** `var(--text-dim)` 

The synced opacity animation (0.45→0.75) stays the same — just the base color changes.

```css
.glimpsing-text {
  color: var(--text-dim);   /* was var(--brand-text) */
  /* animation: textSync stays unchanged */
}
```

---

## 4. Eyebrow pinned state — instant path swap

The v2 spec says "crossfade 0.3s ease" but the design decision is **instant swap, no fade.**

In the GlimpseIcon component:
```jsx
const BROW_RESTING = "M98 212C152 174 365 158 420 248";
const BROW_FOCUSED = "M98 192C200 192 350 204 420 234";

<path d={isPinned ? BROW_FOCUSED : BROW_RESTING} ... />
```

No opacity transition, no crossfade. Just swap the `d` attribute directly based on pinned state.

The focused brow is a straighter, slightly higher line — the companion looks "locked in" when pinned.

Reference: `design/mockups/pinned-furrow.html` — interactive demo at the bottom.

---

## 5. Tray icon — E2a right crop

Update the tray icon to use a cropped/zoomed view of the right side of the eye, not the full logo scaled down.

**Same SVG paths** as the full logo, just a different viewBox:

```svg
<svg viewBox="230 180 220 220" width="44" height="44" xmlns="http://www.w3.org/2000/svg">
  <path d="M98 212C152 174 365 158 420 248" fill="none" stroke="black" stroke-width="22" stroke-linecap="round"/>
  <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="black" stroke-width="24" stroke-linecap="round"/>
</svg>
```

- Template image: black strokes on transparent background
- macOS handles light/dark automatically
- Export as 22×22pt (44×44px @2x) PNG with alpha
- Strokes slightly thicker than in-app (22/24 vs 20/22)
- The cropped lines boldly exit the frame edges — this is intentional ("zoomed in" concept)

See `design/ICON-SPEC.md` (already updated) for full details.

---

## 6. Font loading (if not already done)

Production build may fall back to system fonts if Google Fonts CDN is unreachable. Bundle fonts locally:

1. Download Outfit (wght 300-700) and JetBrains Mono (wght 300-600) woff2 files
2. Place in `src/fonts/` or `public/fonts/`
3. Replace `@import url('https://fonts.googleapis.com/...')` in `app.css` with local `@font-face` declarations
