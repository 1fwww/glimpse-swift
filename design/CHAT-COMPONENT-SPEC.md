# Chat Panel — Detailed Component Spec

> Exact values for every container, border, color, radius, and spacing.
> All token references resolve to the values in DESIGN-SPEC.md Section 3.
> Light theme values in parentheses where different from dark.

---

## Chat Panel Container

```
width: 390px (floating) or 100% (pinned/full)
border-radius: 16px (--radius-lg)
border: 1px solid rgba(108,99,255,0.08)              DARK
        1px solid rgba(0,0,0,0.065)                   LIGHT
background: rgba(22,21,30,0.96)                       DARK  (--surface-panel)
            #FAFAFC                                    LIGHT (--surface-panel)
box-shadow: 0 4px 20px rgba(0,0,0,0.30),
            0 1px 3px rgba(0,0,0,0.15)                DARK  (--shadow-md)
            0 4px 16px rgba(0,0,0,0.06),
            0 1px 2px rgba(0,0,0,0.03)                LIGHT (--shadow-md)
overflow: hidden
backdrop-filter: blur(24px) saturate(1.2)
```

---

## Header

```
padding: 13px 14px 11px
gap: 10px
border-bottom: 1px solid rgba(108,99,255,0.08)       DARK
               1px solid rgba(0,0,0,0.065)            LIGHT
background: transparent (inherits from panel)
```

### Eye icon (brand presence)
```
width: 24px, height: 16px
viewBox: "60 140 420 280"
stroke: #6C63FF
Not clickable for navigation — part of drag handle
Click triggers eyebrow wiggle (one-shot)
```

### Thread title button
```
padding: 3px 6px 3px 0
border-radius: 5px
font: Outfit 600, 13px
color: rgba(242,240,255,0.93)                         DARK  (--text-primary)
       rgba(18,18,25,0.90)                            LIGHT
hover background: rgba(255,255,255,0.04)              DARK
                  rgba(0,0,0,0.03)                    LIGHT
flex: 1 (fills remaining space)
overflow: hidden, text-overflow: ellipsis, white-space: nowrap
```

### Chevron (next to title)
```
width: 12px, height: 12px
color: rgba(140,137,175,0.50)                         DARK  (--text-dim, 0.5 opacity)
       rgba(70,70,95,0.50)                            LIGHT
stroke-width: 2.5
```

### Separator (between +new and pin)
```
width: 1px
height: 18px
background: rgba(108,99,255,0.08)                     DARK  (--border-dim)
            rgba(0,0,0,0.065)                         LIGHT
margin: 0 (gap handles spacing)
```

### New chat button (+)
```
width: 28px, height: 28px
border: 1.5px solid rgba(108,99,255,0.13)             DARK  (--border-active)
        1.5px solid rgba(0,0,0,0.11)                  LIGHT
border-radius: 8px
background: transparent
color: #8580FF                                        DARK  (--brand-text)
       #5B53E0                                        LIGHT
icon: plus sign, 14x14, stroke-width 2
hover:
  background: rgba(108,99,255,0.07)                   DARK  (--brand-dim)
  border-color: rgba(108,99,255,0.25)                 DARK  (--brand-border)
```

### Pin button
```
width: 28px, height: 28px
border: 1.5px solid rgba(108,99,255,0.08)             DARK  (--border-dim)
border-radius: 8px
background: transparent
color: rgba(140,137,175,0.50)                         DARK  (--text-dim)

PINNED STATE:
  background: rgba(108,99,255,0.07)                   DARK  (--brand-dim)
  border-color: rgba(108,99,255,0.25)                 DARK  (--brand-border)
  color: #8580FF                                      DARK  (--brand-text)
```

---

## Attachment Cue (inside input box)

```
display: flex, align-items: center, gap: 6px
margin: 6px 8px 2px
padding: 5px 10px
background: rgba(108,99,255,0.12)                     DARK  (bumped from 0.06 — was invisible)
            rgba(108,99,255,0.06)                     LIGHT (unchanged — already visible)
border-left: 2px solid rgba(108,99,255,0.35)          DARK  (bumped from 0.22)
             2px solid rgba(108,99,255,0.22)          LIGHT (unchanged)
border-radius: 2px 6px 6px 2px (flat left, rounded right)
font: Outfit, 11px
color: rgba(175,172,205,0.75)                         DARK  (--text-secondary, 4.62:1 ✓)
       rgba(45,45,62,0.72)                            LIGHT (5.06:1 ✓)
icon: 13x13, stroke-width 1.5, same color as text
```

### Dismiss button (× on attachment)
```
Simplified — no background, no border. Just × character in --text-secondary.
This passes AA (4.62:1 dark, 5.06:1 light) and is visually cleaner.

width: 16px, height: 16px
border-radius: 50%
background: transparent                               BOTH
border: none                                          BOTH
color: rgba(175,172,205,0.75)                         DARK  (--text-secondary)
       rgba(45,45,62,0.72)                            LIGHT
font-size: 10px
margin-left: auto
cursor: pointer
hover:
  color: rgba(242,240,255,0.93)                       DARK  (--text-primary)
         rgba(18,18,25,0.90)                          LIGHT
  background: rgba(255,255,255,0.06)                  DARK  (--surface-hover)
              rgba(0,0,0,0.035)                       LIGHT
```

---

## Text Context Snippet (inside input box)

Same as attachment cue but with:
```
background: rgba(108,99,255,0.12)                     DARK  (same as attachment)
            rgba(108,99,255,0.06)                     LIGHT (same as attachment)
border-left: 2px solid rgba(108,99,255,0.50)          DARK  (bumped from 0.40 — needs to be visibly stronger than attachment)
             2px solid rgba(108,99,255,0.40)          LIGHT (unchanged)
font: JetBrains Mono, 11px (it's referenced text — technical data)
color: rgba(175,172,205,0.75)                         DARK  (--text-secondary)
       rgba(45,45,62,0.72)                            LIGHT
max-height: 120px, overflow-y: auto
dismiss: same simplified × as attachment
```

---

## Messages Area

```
flex: 1
overflow-y: auto
padding: 10px 14px
display: flex, flex-direction: column, gap: 10px
min-height: 80px
```

### Scrollbar
```
width: 4px
track: transparent
thumb: rgba(108,99,255,0.10)                          DARK
       rgba(0,0,0,0.06)                               LIGHT
thumb border-radius: 2px
thumb:hover: rgba(108,99,255,0.20)                    DARK
```

### User message bubble
```
align-self: flex-end
max-width: 88%
padding: 10px 14px
background: rgba(108,99,255,0.10)                     DARK  (--brand-muted)
            rgba(108,99,255,0.10)                     LIGHT
color: rgba(242,240,255,0.93)                         DARK  (--text-primary)
       rgba(18,18,25,0.90)                            LIGHT
border: none
border-radius: 14px 14px 4px 14px (flat bottom-right = "my message")
font: Outfit, 13px, line-height 1.55
```

### Assistant message bubble
```
align-self: flex-start
max-width: 88%
padding: 10px 14px
background: rgba(31,29,42,0.92)                       DARK  (--surface-elevated)
            #EEEEF2                                    LIGHT (--surface-elevated)
color: rgba(242,240,255,0.93)                         DARK  (--text-primary)
       rgba(18,18,25,0.90)                            LIGHT
border: 1px solid rgba(108,99,255,0.08)               DARK  (--border-dim)
        1px solid rgba(0,0,0,0.065)                   LIGHT
border-radius: 14px 14px 14px 4px (flat bottom-left = "their message")
font: Outfit, 13px, line-height 1.55
```

### Model tag (below assistant message)
```
font: JetBrains Mono, 10px
color: rgba(140,137,175,0.50)                         DARK  (--text-dim)
       rgba(70,70,95,0.50)                            LIGHT
margin-top: 3px
padding-left: 2px
```

### Inline code (inside messages)
```
background: rgba(255,255,255,0.06)                    DARK
            rgba(0,0,0,0.05)                          LIGHT
padding: 1px 5px
border-radius: 4px
font: JetBrains Mono, 12px
cursor: pointer (click to copy)
hover background: rgba(108,99,255,0.12)               DARK  (--brand-muted)
                  rgba(108,99,255,0.10)               LIGHT
```

---

## Code Block (inside assistant message)

```
border-radius: 10px
overflow: hidden
border: 1px solid rgba(108,99,255,0.08)               DARK  (--border-dim)
        1px solid rgba(0,0,0,0.065)                   LIGHT
margin: 8px 0
```

### Code block header
```
display: flex, justify-content: space-between, align-items: center
padding: 5px 10px
background: rgba(31,29,42,0.80)                       DARK  (elevated, slightly transparent)
            #EEEEF2                                    LIGHT (--surface-elevated)
border-bottom: 1px solid rgba(108,99,255,0.06)        DARK
               1px solid rgba(0,0,0,0.065)            LIGHT
```

### Language label
```
font: JetBrains Mono, 10px
color: rgba(160,157,195,0.65)                         DARK  (3.15:1 ✓)
       rgba(80,80,105,0.65)                           LIGHT (3.05:1 ✓)
```

### Copy icon (in header, right side)
```
width: 22px, height: 22px
border-radius: 4px
icon: clipboard, 13x13, stroke-width 2
color: rgba(160,157,195,0.40)                         DARK  (dim resting)
       rgba(80,80,105,0.35)                           LIGHT
background: transparent
ALWAYS visible (not hidden until hover)
hover:
  color: rgba(175,172,205,0.75)                       DARK
         rgba(55,55,75,0.65)                          LIGHT
  background: rgba(108,99,255,0.08)                   DARK
              rgba(0,0,0,0.04)                        LIGHT
copied state:
  color: #2DA44E (--success)
```

### Code content
```
padding: 10px 12px
background: rgba(0,0,0,0.18)                          DARK
            #FAFAFC                                    LIGHT (--surface-panel)
font: JetBrains Mono, 11.5px, line-height 1.55
color: rgba(242,240,255,0.93)                         DARK  (--text-primary)
       rgba(18,18,25,0.90)                            LIGHT
overflow-x: auto
keyword color: #8580FF                                DARK  (--brand-text)
               #5B53E0                                LIGHT
```

---

## Blockquote (inside assistant message)

```
position: relative
border-left: 2px solid rgba(108,99,255,0.35)          DARK
             2px solid rgba(108,99,255,0.30)          LIGHT
background: rgba(108,99,255,0.04)                     BOTH
margin: 8px 0
padding: 9px 32px 9px 12px (right padding for copy icon)
border-radius: 0 8px 8px 0
font: Outfit, 13px, line-height 1.55
color: --text-primary
```

### Copy icon (top-right, same treatment as code block)
```
position: absolute, top: 7px, right: 6px
width: 20px, height: 20px
(same colors and behavior as code block copy icon)
```

---

## Input Area

```
padding: 10px 14px
border-top: 1px solid rgba(108,99,255,0.08)           DARK  (--border-dim)
            1px solid rgba(0,0,0,0.065)               LIGHT
```

### Input box (contains attachment + snippet + textarea)
```
width: 100%
background: rgba(26,25,36,0.96)                       DARK  (--surface-input)
            #F4F4F6                                    LIGHT
border: 1px solid rgba(108,99,255,0.08)               DARK  (--border-dim)
        1px solid rgba(0,0,0,0.065)                   LIGHT
border-radius: 12px (--radius-md)
display: flex, flex-direction: column
position: relative
transition: border-color 0.15s, box-shadow 0.15s

FOCUSED:
  border-color: rgba(108,99,255,0.25)                 DARK  (--brand-border)
  box-shadow: 0 0 0 2px rgba(108,99,255,0.08)        (brand focus ring)
```

### Textarea
```
flex: 1
background: transparent
border: none
padding: 10px 42px 10px 14px (right padding for send button)
font: Outfit, 13px, line-height 1.45
color: rgba(242,240,255,0.93)                         DARK  (--text-primary)
       rgba(18,18,25,0.90)                            LIGHT
resize: none
outline: none
placeholder color: rgba(140,137,175,0.50)             DARK  (--text-dim)
                   rgba(70,70,95,0.50)                LIGHT
```

### Send button
```
position: absolute, right: 6px, bottom: 6px
width: 28px, height: 28px
border-radius: 7px
border: none
background: #6C63FF                                   DARK  (--brand)
            #635AEE                                   LIGHT (--brand-btn)
color: #fff
icon: arrow-right, 16x16, stroke-width 2.5
hover: background #5B53E0 (--brand-btn-hover)
DISABLED:
  background: rgba(255,255,255,0.05)                  DARK
              rgba(0,0,0,0.04)                        LIGHT
  color: rgba(140,137,175,0.50)                       DARK  (--text-dim)
         rgba(70,70,95,0.50)                          LIGHT
  cursor: not-allowed
```

---

## Footer Bar

```
display: flex, align-items: center, gap: 6px
padding: 6px 14px 10px
NO border-top (input area already has one)
```

### Settings gear
```
background: none, border: none
padding: 2px
color: rgba(140,137,175,0.50)                         DARK  (--text-dim)
       rgba(70,70,95,0.50)                            LIGHT
icon: gear, 14x14
hover: color --text-secondary
```

### Esc to close
```
display: flex, align-items: center, gap: 4px
font: Outfit, 11px
color: rgba(160,157,195,0.60)                         DARK
       rgba(70,70,95,0.60)                            LIGHT
"Esc" in kbd style:
  font: JetBrains Mono, 10px
  min-width: 20px, height: 18px, padding: 0 5px
  background: rgba(108,99,255,0.05)                   DARK  (--surface-hover)
              rgba(0,0,0,0.035)                       LIGHT
  border: 1px solid rgba(108,99,255,0.08)             DARK  (--border-dim)
          1px solid rgba(0,0,0,0.065)                 LIGHT
  border-radius: 4px
  color: rgba(140,137,175,0.50)                       DARK  (--text-dim)
```

### Model switcher (right-aligned)
```
margin-left: auto (pushed right by flex)
font: JetBrains Mono, 11px (it's a technical identifier)
color: rgba(140,137,175,0.50)                         DARK  (--text-dim)
       rgba(70,70,95,0.50)                            LIGHT
padding: 2px 4px
border-radius: 4px
hover: color --text-secondary, background --surface-hover
chevron: 10x10, stroke-width 2
```

---

## Thinking State (replaces assistant message while loading)

```
display: flex, align-items: center, gap: 8px
```

### Glimpse eye (squint-loop animation)
```
width: 28px, height: 19px
Uses .logo-think class — squint loop animation from Section 5
```

### Animated dots
```
3 spans, each:
  width: 4px, height: 4px
  border-radius: 50%
  background: rgba(140,137,175,0.50)                  DARK  (--text-dim)
gap: 3px
animation: dotPulse 1.4s ease-in-out infinite
  span:nth-child(2) delay: 0.2s
  span:nth-child(3) delay: 0.4s
```

### "Thinking" text
```
font: Outfit, 12px
color: rgba(140,137,175,0.50)                         DARK  (--text-dim)
```
