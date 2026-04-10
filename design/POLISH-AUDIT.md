# Glimpse Design Polish Audit — 6/10 → 9/10

> Current state: solid foundation, correct tokens, right structure. What's missing is consistency and polish — the details that separate "working" from "crafted."

---

## Score Breakdown

| Area | Current | Target | Gap |
|---|---|---|---|
| Token system | 9/10 | 10/10 | A few hardcoded colors remain |
| Typography | 9/10 | 10/10 | Done — all correct |
| Spacing | 5/10 | 9/10 | 20+ off-scale values throughout |
| Border-radius | 5/10 | 9/10 | 15+ inconsistent values |
| Color consistency | 7/10 | 10/10 | 9 hardcoded colors bypass tokens |
| Interaction states | 7/10 | 9/10 | Some missing hover/active/focus |
| Light theme | 6/10 | 9/10 | Not yet implemented app-wide |
| Animation/motion | 8/10 | 9/10 | Good — minor tweaks |
| Accessibility | 8/10 | 9/10 | ARIA labels done, contrast mostly good |
| Component polish | 7/10 | 9/10 | Structure correct, details need tightening |

---

## Tier 1: High Impact, Low Effort (do first)

### 1.1 Hardcoded colors → tokens

These bypass the design system and will break when themes change:

| Location | Current | Replace with |
|---|---|---|
| Selection handles `border` | `2px solid #fff` | `2px solid rgba(255,255,255,0.9)` or token |
| Pinned dark bg | `#222131` | Define as `--surface-pinned` token |
| Pinned light bg | `#F3F4F9` | Define as `--surface-pinned` token |
| Welcome button hover | `#5B53E0` | `var(--brand-btn-hover)` |
| Permission granted color | `#238542` | `var(--success)` |
| Home app background | `#0c121e` | `var(--surface-base)` |
| Clear button hover | `#ff6b6b` | `var(--error)` |
| Light theme dropdowns | `#fff` | `var(--surface-panel)` |

**Why it matters:** One token change should update the entire app. Hardcoded values create orphaned styles that look wrong when themes change.

### 1.2 Spacing normalization

The spacing scale is `4, 8, 12, 16, 20, 24, 32, 40`. These values are off-scale:

| Value | Count | Replace with |
|---|---|---|
| `3px` | 6 instances | `4px` (`--space-1`) |
| `5px` | 8 instances | `4px` or `8px` |
| `6px` (non-gap) | 4 instances | `8px` (`--space-2`) |
| `7px` | 2 instances | `8px` |
| `10px` (padding) | 5 instances | `8px` or `12px` |
| `11px` (padding) | 2 instances | `12px` (`--space-3`) |
| `13px` (padding) | 2 instances | `12px` or `16px` |
| `14px` (padding) | 3 instances | `12px` or `16px` |

**Most impactful fix:** The chat header uses `padding: 13px 14px 11px` — three off-scale values in one line. Change to `padding: 12px 12px 12px` or `12px 16px 12px`.

**Note:** Not every value needs to be on-scale. Inner code block padding (`1px 5px` for inline code) is fine — it's content-level, not layout-level. Focus on padding/margin/gap on containers and components.

### 1.3 Border-radius cleanup

The radius scale is `8, 12, 16, 20, 9999`. These are off-scale:

| Value | Instances | Replace with |
|---|---|---|
| `3px` | 1 | `4px` (below scale — keep as special case for inline code) |
| `4px` | 3 | `var(--radius-sm)` (8px) or keep for message bubble corners |
| `5px` | 2 | `var(--radius-sm)` (8px) |
| `6px` | 5 | `var(--radius-sm)` (8px) |
| `7px` | 2 | `var(--radius-sm)` (8px) |
| `10px` | 1 | `var(--radius-md)` (12px) |
| `14px` | 1 | `var(--radius-lg)` (16px) |

**Exception:** Message bubble radii (`14px 14px 4px 14px`) are intentionally asymmetric — the 4px "tail" corner is a design choice, not a mistake. Don't change these.

---

## Tier 2: Medium Impact (do next)

### 2.1 Missing interaction states

These elements have hover but no `focus-visible` or `:active`:

| Element | Missing state | Fix |
|---|---|---|
| `.sel-handle` (selection handles) | `:hover` | Add cursor change + slight scale |
| `.edit-settings-btn` | `:focus-visible`, `:active` | Add brand outline + scale(0.95) |
| `.perm-grant` button | `:active` | Add scale(0.97) press feedback |
| `.chat-header-title-btn` | `:focus-visible` | Add brand outline |
| `.edit-tool-btn` | `:active` press | Add scale(0.95) for tactile feel |

### 2.2 Light theme completeness

The light theme tokens are defined but some components still rely on dark-theme rgba() values that don't adapt:

**Check these manually in light mode:**
- Tooltip backgrounds and text
- Thread menu popup background and shadows
- Model dropdown styling
- Code block header background (hardcoded `rgba(31,29,42,0.80)` — dark only)
- Edit toolbar background and borders
- Settings key-row backgrounds
- Home dashboard (if still visible)

**The code block header is the biggest gap:** `background: rgba(31, 29, 42, 0.80)` is a dark-specific value. In light mode it needs `var(--surface-elevated)`.

### 2.3 "Glimpsing..." color

Per our review: builder changed to `--brand-text` (too prominent). Revert to `--text-dim` with synced opacity animation. The eye icon carries the brand color — the text should be subordinate.

### 2.4 Eyebrow crossfade → instant swap

Builder added 0.3s opacity crossfade. We decided on instant path swap. Revert.

---

## Tier 3: Polish Details (final pass)

### 3.1 Tooltip consistency

Tooltips should use:
```css
font-family: var(--font-display);  /* not mono */
font-size: var(--text-xs);         /* 11px */
padding: 4px 8px;                  /* on-scale */
border-radius: var(--radius-sm);   /* 8px, not 4px */
```

Currently some tooltips use `3px 8px` padding and `4px` radius.

### 3.2 Scroll-to-bottom FAB

The floating action button for scroll-to-bottom should match the design system:
- Border: `var(--border-active)` not hardcoded
- Background: `var(--surface-base)` not hardcoded
- Color: `var(--brand-text)` not cyan

### 3.3 Thread menu items

Verify consistent padding, hover states, and font usage. Thread menu items should use:
- `font-family: var(--font-display)`
- `font-size: var(--text-sm)` (12px)
- `padding: 8px 12px`
- `border-radius: var(--radius-sm)`

### 3.4 Model dropdown

When single provider: no section header (per v2 spec).
When multiple: 11px section header + divider.
Model items indented 14px vs provider 8px.

### 3.5 Empty state

When no messages and no API key setup showing — what does the user see? Should be a clean, welcoming empty state, not a blank void. Consider showing the Glimpse eye + "Ask me anything about your screenshot" or similar.

---

## What's Already Good ✓

- Token system (brand, surfaces, borders, text, shadows) — fully implemented
- Typography — Outfit for UI, mono for code, min 11px
- Logo — polished SVG, draw-on + blink, squint loop, double blink, focus pulse
- Annotation palette — 7-color colorblind-safe
- Selection border — static, round handles, no glow/brackets
- Welcome flow — all 4 steps, correct copy, animations, API hint
- Settings — theme toggle, delete confirm, version, shortcuts note
- API key setup — correct copy, solid CTA, inline errors
- Chat header — correct layout (eye, title, new, pin)
- Footer — correct layout (settings, esc, model)
- Code blocks — header bar with dim copy icon
- Blockquotes — copy icon
- Thinking state — "Glimpsing..." with focus pulse eye
- ARIA labels — comprehensive coverage
- Reduced motion — implemented
- Focus-visible — global style added
- No cyan/magenta — fully removed

---

## Implementation Order

```
Week 1 (Tier 1): Hardcoded colors + spacing + radius = consistent foundation
Week 2 (Tier 2): Light theme + interaction states + Glimpsing color fix
Week 3 (Tier 3): Tooltips + FAB + thread menu + dropdown + empty state
```

After all three tiers: **9/10.**

The remaining 1 point is performance (screenshot → pin transition speed, selection drag framerate) — that's engineering, not design.
