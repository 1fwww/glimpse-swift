# Fixes Round 4 — Eye Animations

---

## 1. Welcome Step 0: Add cursor dot before frame expansion

**Reference:** `design/mockups/welcome-capture-v3.html` (updated) + `design/WELCOME-STEP0-ANIM.md` (updated)

Before the frame starts expanding, a small purple dot (8px circle) appears at the top-left corner and pauses for 0.35s — like a cursor being placed before dragging a selection. The dot fades as the frame starts expanding from 8×8 (instead of 0×0).

**Changes from previous spec:**
- New `<div className="w-cursor-dot" />` element inside eye container
- Dot appears at 0.35s, pauses until 0.7s, fades out
- Frame expansion delay shifts from 0.5s → 0.7s
- Frame starts from `width: 8px; height: 8px` (not 0)
- All downstream timings shift +0.2s (blink at 1.9s, text at 2.3s)
- See updated `WELCOME-STEP0-ANIM.md` for exact values

**Note:** This dot is ONLY for Welcome Step 0. The tray reveal (Step 4) does NOT get the dot — it looks fine without it.

---

## 2. NEW: Glimpsing scan — thinking state animation

**Reference:** `design/mockups/glimpsing-scan.html`

Replaces the current focus pulse (`Glimpsing...` + 16px eye opacity pulse) with a scanning frame that drifts across a ghost eye.

### Concept

A selection frame drifts continuously across the ghost Glimpse eye, like eyes scanning/examining something. The area inside the frame shows at full brand color. The frame also breathes in size (44-56px), and moves at varying speeds (lingering in some areas, faster between). This directly communicates "I'm looking at what you gave me."

### DOM structure

```jsx
<div className="scan-stage">  {/* position: relative, matches eye size */}
  {/* Ghost eye — always visible, 18% opacity */}
  <svg className="scan-ghost" ... />
  
  {/* Full color eye — clipped to frame position */}
  <svg className="scan-reveal" ... />
  
  {/* Frame border */}
  <div className="scan-frame" />
</div>
<span className="scan-label">Glimpsing...</span>
```

### Key CSS

**Ghost:** `opacity: 0.18`

**Frame:** Animates position + size in ONE animation (important — do NOT split into separate position and size animations, they'll desync):

```css
.scan-frame {
  border: 1.5px solid rgba(108, 99, 255, 0.45);
  border-radius: 3px;
}

animation: frameDrift 8s ease-in-out infinite;

@keyframes frameDrift {
  0%   { top: -4px;  left: -6px; width: 52px; height: 52px; }
  10%  { top: 2px;   left: 34px; width: 56px; height: 56px; }
  28%  { top: 12px;  left: 50px; width: 44px; height: 44px; }
  35%  { top: -3px;  left: 44px; width: 56px; height: 56px; }
  52%  { top: 16px;  left: 10px; width: 48px; height: 48px; }
  60%  { top: 6px;   left: -6px; width: 48px; height: 48px; }
  72%  { top: 17px;  left: 42px; width: 54px; height: 54px; }
  90%  { top: -2px;  left: 8px;  width: 46px; height: 46px; }
  100% { top: -4px;  left: -6px; width: 52px; height: 52px; }
}
```

**Reveal:** `clip-path: inset()` synced with frame position+size. Inset 2% on each edge to prevent purple peeking outside frame during interpolation:

```css
animation: revealDrift 8s ease-in-out infinite;

@keyframes revealDrift {
  0%   { clip-path: inset(2%    56%   30.4% 2%);  }
  10%  { clip-path: inset(5%    12%   15.4% 36%); }
  28%  { clip-path: inset(19.9% 8%    18.4% 52%); }
  35%  { clip-path: inset(2%    2%    22.9% 46%); }
  52%  { clip-path: inset(25.9% 44%   6.5%  12%); }
  60%  { clip-path: inset(11%   60%   21.4% 2%);  }
  72%  { clip-path: inset(27.4% 6%    2%    44%); }
  90%  { clip-path: inset(2%    48%   30.4% 10%); }
  100% { clip-path: inset(2%    56%   30.4% 2%);  }
}
```

**Label pulse:**
```css
animation: labelPulse 8s ease-in-out infinite;
@keyframes labelPulse {
  0%, 100% { opacity: 0.5; }
  50% { opacity: 0.8; }
}
```

### Small inline variant (for chat thinking state)

Same concept scaled to 40×27 eye, 20×20 frame. See mockup for exact keyframe values.

### Production notes

- In production, use `transform: scale()` + `transform-origin` instead of animating `width`/`height` on the frame
- The 2% clip-path buffer is critical — without it, purple peeks outside the frame during interpolation
- `prefers-reduced-motion`: stop all animations, show static ghost eye + "Glimpsing..." text
- 8s cycle — long enough that it doesn't feel repetitive during typical 10-30s AI responses

---

## 3. NEW: Connected animation — eye wake-up (chat panel)

**Reference:** `design/mockups/connected-chat-v2.html`

Replaces the current `logo-draw-only` animation in `.api-key-welcome`. Only plays on first successful API key connection.

### Concept

The eye is "sleeping" (eyebrow pressed down, closed). The iris spiral draws/undraws while connecting. On success: eye opens with an energetic overshoot + scale pop, winks at the user. The big eye then shrinks and flies to the title bar, where a small icon settles into its permanent home.

### Before connect

Title bar shows "New Chat" with NO eye icon. The eye icon only appears after first successful connection.

### Animation timeline

```
0.0–0.15s   Closed eye fades in (25% opacity, brow translateY(28px) = closed)
0.15–1.65s  Iris spiral draws on → off → on (stroke-dashoffset cycling)
1.8s        Eye OPENS:
              - Brow lifts with overshoot (28px → -8px → 2px → 0)
              - Awake eye fades in with scale pop (0.9 → 1.05 → 1.0)
              - "Connected. Happy Glimpsing!" text appears
2.0s        Closed eye fades out
2.6s        Wink (brow translateY 22px, 0.45s)
3.4s        Text fades out + eye shrinks/flies to title bar position
3.7s        Small icon (20×14) fades into title bar
4.5s        Done — chat panel ready for input
```

### Key details

**Eye size:** 100×67 (matches Welcome Step 0)

**Closed state:** Same SVG paths. Brow has `transform: translateY(28px)` pushing it down onto the body curve. Spiral uses `stroke-dasharray: 820; stroke-dashoffset: 820` to be hidden initially.

**Spiral draw loop:**
```css
@keyframes cSpiralDraw {
  0%   { stroke-dashoffset: 820; }    /* hidden */
  35%  { stroke-dashoffset: 0; }      /* fully drawn */
  65%  { stroke-dashoffset: -820; }   /* undrawn (reverse) */
  100% { stroke-dashoffset: -1640; }  /* fully drawn again */
}
```

**Brow lift — overshoot is critical for delight:**
```css
@keyframes cBrowLift {
  0%   { transform: translateY(28px); }
  50%  { transform: translateY(-8px); }   /* overshoot — surprised! */
  75%  { transform: translateY(2px); }    /* tiny bounce back */
  100% { transform: translateY(0px); }    /* settle */
}
```

**Awake scale pop:**
```css
@keyframes cAwakeIn {
  0%   { opacity: 0; transform: scale(0.9); }
  60%  { opacity: 1; transform: scale(1.05); }
  100% { opacity: 1; transform: scale(1); }
}
```

**Fly to title:** Eye wrapper animates from center of welcome area to title bar position:
```css
@keyframes cFlyToTitle {
  0%   { transform: translate(0, 0) scale(1); opacity: 1; }
  100% { transform: translate(-155px, -175px) scale(0.2); opacity: 0; }
}
```
The translate values need to be calculated based on actual layout — these are approximate from the mockup.

**Title icon appears** as the big eye arrives:
```css
@keyframes titleIconIn {
  from { opacity: 0; transform: scale(0.8); }
  to { opacity: 1; transform: scale(1); }
}
```

### Implementation notes

- Only trigger on **first** successful API key save, not on subsequent saves
- The fly-to-title translate values are layout-dependent — calculate from actual element positions
- `stroke-dasharray` value (820) is approximate for the spiral path length — measure actual path with `getTotalLength()` and adjust
- After the animation, the chat panel shows normal state with eye icon in title
- `prefers-reduced-motion`: skip animation, show awake eye + text immediately
