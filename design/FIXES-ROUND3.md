# Fixes Round 3

---

## 1. Welcome flow restructure — add Step 4, remove dots from splash

### Page 0 (Splash): NO dots
- Title: "Glimpse"
- Tagline: "Glimpse your screen. Stay in flow."
- CTA: "Get Started"
- **Remove the dot navigation from this page.** It's a brand splash, not a step.

### Pages 1-4: Show 4 dots
- Page 1 (Permissions): dot 1 active
- Page 2 (Shortcuts): dot 2 active  
- Page 3 (Pin demo): dot 3 active — **CTA changes to "Got it"** (was "Start Using Glimpse")
- Page 4 (Tray reveal): dot 4 active — **NEW PAGE** (see below)

### NEW: Page 4 — Tray icon reveal

**Layout:**
```
You're all set                                    ← title (18px, semibold)
Glimpse will run quietly in the background.        ← subtitle (14px, secondary)

[tray icon reveal animation area]                 ← ~120px height

Find [inline tray icon SVG] in your menu bar.     ← hint (12px, dim, icon inline)

[Start Using Glimpse]                             ← CTA button (same solid brand style)
```

**Animation sequence (auto-plays on step load) — UPDATED v5:**
1. **0-0.3s:** Full Glimpse eye fades in (100% opacity — user already saw logo in Step 0)
2. **0.5-1.1s:** Crop frame expands from top-left + **progressive purple→black reveal** inside frame (clip-path synced). 0.6s, `cubic-bezier(0.25, 0.1, 0.25, 1)`. **Mid-pause at 40%→55%** (human hesitation — same feel as Step 0).
3. **1.1-1.5s:** Hold — user sees black inside frame, purple outside
4. **1.5s:** Dim overlay fades in (0.15s). **Frame stays visible** (does NOT fade out — reinforces "eye behind a window" metaphor).
5. **1.9s:** Hint text fades in with inline tray icon

**The eye SVG:** Same paths as the polished logo.
```jsx
<svg viewBox="60 140 420 280" width="100" height="67">
  <path d="M98 212C152 174 365 158 420 248" fill="none" stroke="#6C63FF" strokeWidth="20" strokeLinecap="round"/>
  <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="#6C63FF" strokeWidth="22" strokeLinecap="round"/>
</svg>
```

**Crop frame position (for eye at 100x67):**
- Top: 10px from eye top
- Left: 40px from eye left  
- Width: 52px, Height: 52px
- Expands from `width:0; height:0` at `top:10; left:40` to full size (top-left anchored)

**Dim overlay:** Covers eye except crop area. Use `clip-path` polygon to cut a hole.
- Light mode: `rgba(242, 242, 244, 0.88)` (matches background)
- Dark mode: `rgba(22, 21, 30, 0.88)` (matches background)

**Color change overlay:** Same crop area, black strokes (light) or white strokes (dark) fade in with the dim.
```
Light: stroke="#1a1a1a"  (tray icon is dark on light menu bar)
Dark:  stroke="white"    (tray icon is light on dark menu bar)
```

**Inline tray icon in hint text:** Use `currentColor` for stroke so it adapts to theme.
```jsx
<span>Find </span>
<svg viewBox="230 180 220 220" width="14" height="10" style={{display:'inline',verticalAlign:'middle'}}>
  <path d="M98 212..." stroke="currentColor" strokeWidth="26" .../>
  <path d="M262 374..." stroke="currentColor" strokeWidth="28" .../>
</svg>
<span> in your menu bar.</span>
```

**Reference:** `design/mockups/tray-intro-v5.html` — open in browser and click "Play" to see the full animation.

---

## 2. Chat-only window border on load

The ChatOnlyApp window (Cmd+Shift+X, text chat) is missing border and shadow when first created in light mode. Window edge is invisible against light desktop wallpaper.

**Fix:** Ensure `.chat-only-app` always has:
```css
.chat-only-app {
  border: 1px solid var(--border-dim);
  box-shadow: var(--shadow-md);
}
```

This should be present from window creation, not conditionally added after messages arrive.

---

## 3. App icon squircle

The icon PNG still renders as a square in DMG/Finder. The `rx/ry` on the rect gets clipped by the viewBox.

**Fix:** Use `clipPath` in the SVG source, not `rx/ry`:
```svg
<svg viewBox="0 0 1024 1024" width="1024" height="1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <clipPath id="squircle">
      <rect width="1024" height="1024" rx="228" ry="228"/>
    </clipPath>
  </defs>
  <g clip-path="url(#squircle)">
    <rect width="1024" height="1024" fill="#141414"/>
    <!-- Logo centered — adjust translate to optically center -->
    <g transform="translate(90, 195) scale(1.6)">
      <path d="M98 212C152 174 365 158 420 248" fill="none" stroke="#6C63FF" stroke-width="20" stroke-linecap="round"/>
      <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="#6C63FF" stroke-width="22" stroke-linecap="round"/>
    </g>
  </g>
</svg>
```

The squircle outside must be **transparent** in the exported PNG. The translate values may need visual tuning — check that the eye looks optically centered (not just geometrically centered — the spiral pulls weight to the right).

Regenerate all icon sizes from this source.
