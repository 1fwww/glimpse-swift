# Bugfix Plan — Post-Performance Round

> Based on .app bundle testing on real machine (2026-04-09)

---

## Priority 1: Permission Flow Reliability

### Problem
Permission step shows "Grant" buttons even when permissions are already granted. After granting + quit/reopen, still shows "Grant" instead of checkmarks. User can't tell if permissions are actually granted.

### Root causes (likely multiple)
1. **`CGPreflightScreenCaptureAccess()` returns stale value** — macOS caches permission state per binary signature. Different builds = different cache.
2. **`AXIsProcessTrusted()` may not reflect toggle-on immediately** — macOS requires app restart for some permission changes.
3. **Polling interval (2s) misses the permission grant** — user grants and comes back before next poll.
4. **System residue** — repeated installs/uninstalls on same machine leave stale permission entries.

### Fix
1. Check permissions immediately on step 1 entry (already done) AND on window focus (`visibilitychange` event)
2. Add a "refresh" button or pull-to-check gesture
3. If permissions appear stuck, show a hint: "Already granted? Try closing and reopening Glimpse."
4. Log actual permission values to help debug

---

## Priority 2: Quote Text (Cmd+Shift+X) Fails in .app Bundle

### Problem
`grab_selected_text()` returns empty in .app bundle. Falls back to showing "screenshot attached" instead of quoted text.

### Root causes
1. **Accessibility permission not granted for .app** — `osascript` keystroke simulation requires Accessibility. The .app binary might have a different signature than what was authorized.
2. **`CGRequestScreenCaptureAccess` vs Accessibility confusion** — quote text needs Accessibility, not Screen Recording.
3. **Timing** — .app bundle may have different osascript execution speed.

### Fix
1. Verify Accessibility permission is checked and granted in onboarding
2. Add Accessibility check before `grab_selected_text` — if not granted, skip silently (no fake screenshot)
3. Debug: log the actual clipboard state before/after Cmd+C simulation

---

## Priority 3: Fullscreen Space Issues

### Problems
- Need 2 presses to trigger screenshot in fullscreen
- Pin from fullscreen → chat appears on different Space
- Chat (Cmd+Shift+X) from fullscreen → opens on different Space

### Root cause
All three are the same issue: **Accessory policy switch timing + window Space association**.

From CLAUDE.md:
- Accessory switch must be SYNCHRONOUS before capture
- `set_activation_policy(Regular)` in close causes Space switch
- Chat window created as Regular → opens on main Space, not fullscreen Space

### Fix
1. **2-press trigger**: Verify Accessory policy switch completes before capture. Add more aggressive spin-wait.
2. **Pin Space switch**: Chat window needs `CanJoinAllSpaces` or must be created WHILE still in Accessory mode on the correct Space.
3. **Chat Space**: Same as #2 — chat needs to appear on current Space.

### Risk: HIGH
These are the hardest issues in the codebase. Previous fixes took multiple iterations. Changes here can break non-fullscreen behavior.

---

## Priority 4: Chat Window Screen Positioning

### Problems
- Non-fullscreen pin: position/size not exactly matching overlay panel
- Switching screens then opening chat → pulled back to original screen

### Root cause
1. Pin bounds calculation uses overlay-relative coordinates. May have rounding or offset errors.
2. Chat hide/show preserves old position. Should reposition to current screen/cursor.

### Fix
1. Pin: verify bounds calculation with logging. Compare overlay panel getBoundingClientRect with chat window position.
2. Chat reopen: detect which monitor the cursor is on, position chat there.

---

## Execution Order

```
Session 1 (safe, no Space risk):
  - Permission flow reliability (#1)
  - Quote text debug + fix (#2)
  - Chat screen repositioning (#4)

Session 2 (high risk, Space-sensitive):
  - Fullscreen Space issues (#3)
  - Requires .app bundle testing for every change
```

---

## Testing Requirements

- All fixes must be tested in **.app bundle**, not dev mode
- Fullscreen fixes require testing on:
  - Single monitor fullscreen app
  - Multi-monitor with fullscreen on one
  - Fullscreen → non-fullscreen → fullscreen cycle
- Permission fixes require testing with:
  - Fresh install (no prior permissions)
  - Reinstall over existing (stale permissions)
