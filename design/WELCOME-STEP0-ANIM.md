# Welcome Step 0 — Capture Reveal Animation

**Reference mockup:** `design/mockups/welcome-capture-v3.html` — open in browser and click "Play in context" to see the exact animation.

---

## Concept

The welcome splash uses a "screenshot capture" metaphor to introduce the Glimpse logo. A ghost eye appears, a selection frame expands across it (like dragging a screenshot region), and the area inside the frame progressively reveals at full color. This directly communicates what Glimpse does — capture your screen.

## DOM Structure

```jsx
<div className="w-stage"> {/* 280×120, position:relative, flex center */}
  <div className="w-eye-container"> {/* 100×67, position:relative */}
    
    {/* Ghost eye — 35% opacity, hides after reveal */}
    <svg viewBox="60 140 420 280" width="100" height="67" aria-hidden="true">
      <path d="M98 212C152 174 365 158 420 248" fill="none" stroke="var(--brand)" strokeWidth="20" strokeLinecap="round"/>
      <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="var(--brand)" strokeWidth="22" strokeLinecap="round"/>
    </svg>
    
    {/* Selection frame — expands from top-left */}
    <div className="w-crop-frame" />
    
    {/* Full-color overlay — clipped in sync with frame */}
    <div className="w-white-overlay">
      <svg viewBox="60 140 420 280" width="100" height="67" aria-hidden="true">
        {/* Same paths, same stroke color */}
      </svg>
    </div>
    
  </div>
</div>
```

**Key structural detail:** The full-color overlay is a **sibling** of the ghost SVG (not a child), so it isn't affected by the ghost's opacity.

## Animation Timeline

```
0.0–0.3s   Ghost eye fades in at 35% opacity
0.35–0.7s  Cursor dot appears (8px purple circle), pauses 0.35s
0.7–1.5s   Dot fades, frame expands from 8×8 + progressive color reveal (synced)
1.4–1.55s  Ghost fades out (masked by overlay, 0.15s ease-out)
1.85s      Frame snap: flash→fade (0.4s single animation)
1.9s       Eyebrow blink (synced with frame fade — "被拍到眨眼")
2.3s       "Glimpse" title fades up
2.45s      Tagline fades up
2.6s       "Get Started" button fades up
```

## Animation Details

### 0. Cursor Dot (0.35–0.7s)

A small purple dot appears at the frame's starting position (top-left of eye), pauses for 0.35s like a cursor being placed, then fades as the frame starts expanding. This is the "someone placed their cursor here" moment before dragging.

```jsx
<div className="w-cursor-dot" />
```

```css
.w-cursor-dot {
  position: absolute;
  top: -5px; left: -5px;
  width: 8px; height: 8px;
  border-radius: 50%;
  background: rgba(108, 99, 255, 0.7);
  z-index: 6;
  opacity: 0;
}

animation: wDotIn 0.15s ease-out 0.35s forwards, wDotOut 0.1s ease-out 0.7s forwards;

@keyframes wDotIn {
  from { opacity: 0; transform: scale(0.3); }
  to { opacity: 1; transform: scale(1); }
}
@keyframes wDotOut {
  from { opacity: 1; }
  to { opacity: 0; }
}
```

### 1. Ghost Eye (0–0.3s)

```css
/* Animate ONLY the SVG element, not the container */
.w-eye-container > svg {
  animation: ghostIn 0.3s ease-out forwards;
}
@keyframes ghostIn {
  from { opacity: 0; }
  to { opacity: 0.35; }
}
```

The container itself is set to `opacity: 1` immediately (via a 0.01s animation). Only the SVG inside fades to 35%.

### 2. Frame Expansion — Human Drag Feel (0.7–1.5s)

Starts at 8×8 (matches the cursor dot size) instead of 0×0. Delay shifted to 0.7s so it begins as the dot fades.

```css
.w-crop-frame {
  position: absolute;
  top: -5px; left: -5px;
  width: 0px; height: 0px;
  border: 1.5px solid rgba(108, 99, 255, 0.8);
  border-radius: 4px;
}

animation: wCropExpand 0.8s cubic-bezier(0.25, 0.1, 0.25, 1) 0.7s forwards;

@keyframes wCropExpand {
  0%   { width: 8px;   height: 8px;  }   /* matches cursor dot size */
  40%  { width: 55px;  height: 38px; }   /* fast initial drag */
  55%  { width: 60px;  height: 42px; }   /* human hesitation */
  100% { width: 110px; height: 77px; }   /* commits to full size */
}
```

The mid-pause at 40%→55% creates a natural "dragging, adjusting, then committing" feel. This is the signature moment.

### 3. Progressive Color Reveal (synced with frame)

The full-color overlay uses `clip-path: inset()` animated with identical timing/easing as the frame:

```css
.w-white-overlay {
  position: absolute; top: 0; left: 0;
  width: 100px; height: 67px;
  opacity: 1;                           /* always opaque */
  clip-path: inset(0 100% 100% 0);     /* fully clipped initially */
  z-index: 4;
}

animation: wRevealExpand 0.8s cubic-bezier(0.25, 0.1, 0.25, 1) 0.5s forwards;

@keyframes wRevealExpand {
  0%   { clip-path: inset(0 100% 100% 0); }
  40%  { clip-path: inset(0 50% 50.7% 0); }   /* matches 55×38 frame */
  55%  { clip-path: inset(0 45% 44.8% 0); }   /* matches 60×42 frame */
  100% { clip-path: inset(0 0% 0% 0); }       /* fully revealed */
}
```

**Critical:** Same duration (0.8s), same delay (0.5s), same easing — so the color boundary stays inside the frame border.

### 4. Ghost Fade-Out (1.2–1.35s)

```css
animation: ghostHide 0.15s ease-out 1.2s forwards;
@keyframes ghostHide {
  from { opacity: 0.35; }
  to { opacity: 0; }
}
```

By 1.2s the overlay fully covers the ghost, so this fade is invisible — but prevents any edge flicker.

### 5. Frame Snap + Fade (1.65s)

Single combined animation — no gap between flash and fade:

```css
animation: wFrameSnap 0.4s ease-out 1.65s forwards;

@keyframes wFrameSnap {
  0%   { border-color: rgba(108, 99, 255, 0.8); box-shadow: none; opacity: 1; }
  10%  { border-color: rgba(108, 99, 255, 1); box-shadow: 0 0 14px rgba(108, 99, 255, 0.25); opacity: 1; }
  100% { border-color: rgba(108, 99, 255, 0.6); box-shadow: none; opacity: 0; }
}
```

**Do NOT animate `border-width`** — it triggers layout reflow and causes micro-jitter.

### 6. Blink (1.7s)

```css
.w-white-overlay svg path:first-child {
  transform-origin: 260px 212px;
  animation: wBlink 0.5s cubic-bezier(0.22, 1, 0.36, 1) 1.7s;
}
@keyframes wBlink {
  0%   { transform: translateY(0); }
  30%  { transform: translateY(24px); }
  35%  { transform: translateY(24px); }
  100% { transform: translateY(0); }
}
```

Blink fires on the **full-color overlay's** eyebrow (first path = the arc), synced with the frame fade — reads as "reacting to being captured."

### 7. Text Cascade (2.1–2.4s)

```css
@keyframes wFadeUp {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}
.w-title   { animation: wFadeUp 0.35s ease-out 2.1s forwards; }
.w-desc    { animation: wFadeUp 0.35s ease-out 2.25s forwards; }
.w-btn     { animation: wFadeUp 0.35s ease-out 2.4s forwards; }
```

150ms stagger between each element.

## Performance Notes

- Use `will-change: clip-path` on the overlay and `will-change: width, height, opacity` on the frame
- In production, prefer `transform: scale()` with `transform-origin: top left` for the frame instead of animating `width`/`height` — but sync the clip-path percentages accordingly
- The ghost fade uses `0.15s` (not instant) to avoid edge flicker artifacts
- Frame snap is a single animation (flash + fade combined) — no separate flash-then-gap-then-fade

## Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  * { animation-duration: 0.01ms !important; }
}
```

All elements have `animation-fill-mode: forwards`, so reduced motion shows the final state immediately.

## Copy

- Title: **Glimpse**
- Tagline: **Glimpse your screen. Stay in flow.**
- CTA: **Get Started**
