# Debug: Accessibility Permission Not Detected

## Problem
`AXIsProcessTrusted()` returns `false` even though Glimpse is enabled in System Settings → Accessibility.

- Screen Recording permission works fine (`CGPreflightScreenCaptureAccess()` returns `true`)
- Accessibility shows `false` in the app's permission check
- System Settings shows Glimpse as "on" for Accessibility
- Toggling off→on in Settings doesn't fix it
- Removing and re-adding Glimpse in Settings doesn't fix it
- Quitting and reopening the app doesn't fix it
- Machine: macOS Sonoma 14.5

## What to investigate

### 1. Check the actual bundle identifier
```bash
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "/Applications/Glimpse.app/Contents/Info.plist"
# or
defaults read /Applications/Glimpse.app/Contents/Info.plist CFBundleIdentifier
```

### 2. Reset TCC with the correct bundle ID
```bash
tccutil reset Accessibility <BUNDLE_ID_FROM_STEP_1>
```
Then reopen Glimpse and re-grant Accessibility.

### 3. Check TCC database directly
```bash
# Needs Full Disk Access for the terminal
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT service, client, allowed FROM access WHERE service='kTCCServiceAccessibility'"
```
Look for the Glimpse entry — does `client` match the bundle ID? Is `allowed` = 1?

### 4. Check code signing
```bash
codesign -dv /Applications/Glimpse.app 2>&1
codesign -dv /Applications/Glimpse.app/Contents/MacOS/Glimpse 2>&1
```
If the app is ad-hoc signed (no team ID), macOS might not match the TCC entry to the running process correctly.

### 5. Quick AXIsProcessTrusted test
Open Glimpse with DevTools:
```bash
WEBKIT_INSPECTOR_DEVICE=1 open /Applications/Glimpse.app
```
Then Cmd+Option+I → Console:
```javascript
window.electronAPI.checkPermissions().then(r => console.log(r))
```
Should show `{screen: true/false, accessibility: true/false}`.

### 6. Compare with working machine
On the machine where permissions DO work, run the same codesign command and compare. The key difference is likely the code signature identity — TCC matches permissions to the binary's code directory hash.

## Relevant code
- `src-tauri/src/commands/permissions.rs` — `check_permissions()`, `check_accessibility_trusted()`
- `src/WelcomeApp.jsx` — `checkPermissions()` called on mount + 2s polling + focus/visibility events
- `src/tauri-shim.js` line 79 — `checkPermissions: () => invoke('check_permissions')`

## Hypothesis
The app is not properly code-signed (ad-hoc signature from `npx tauri build`). macOS TCC on Sonoma 14.5 may require a stable code signing identity to match Accessibility permissions to the running process. Screen Recording uses a different check (`CGPreflightScreenCaptureAccess`) that may be more lenient with ad-hoc signatures.
