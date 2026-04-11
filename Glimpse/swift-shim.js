/**
 * Swift shim — provides window.electronAPI using WKWebView messageHandler.
 * Replaces tauri-shim.js for the native Swift shell.
 * Same interface as tauri-shim.js so React components need zero changes.
 */

// Set route hash BEFORE React renders (this script runs at document-start)
// The hash is passed as a global by Swift before page load
if (window._glimpseRoute) {
  location.hash = window._glimpseRoute;
}

// Callback management for invoke-style calls (request → response)
window._glimpseCallbacks = {};
window._glimpseNextId = 1;

window._glimpseResolve = function(callbackId, result) {
  const cb = window._glimpseCallbacks[callbackId];
  if (cb) {
    cb(result);
    delete window._glimpseCallbacks[callbackId];
  }
};

function invoke(command, args) {
  return new Promise((resolve) => {
    const callbackId = window._glimpseNextId++;
    window._glimpseCallbacks[callbackId] = resolve;
    window.webkit.messageHandlers.glimpse.postMessage({
      command: command,
      args: args || {},
      callbackId: callbackId
    });
    // Timeout: resolve with null after 30s to prevent hanging
    setTimeout(() => {
      if (window._glimpseCallbacks[callbackId]) {
        delete window._glimpseCallbacks[callbackId];
        resolve(null);
      }
    }, 30000);
  });
}

// Event listeners (backend → frontend via CustomEvent)
function listen(event, callback) {
  const handler = (e) => callback(e.detail);
  window.addEventListener('glimpse:' + event, handler);
  // Return unlisten function
  return () => window.removeEventListener('glimpse:' + event, handler);
}

// Window dragging: React's handleHeaderMouseDown checks for __TAURI_INTERNALS__
// and returns early when chatFullSize=true. We can't intercept that cleanly, so
// we add a capture-phase listener directly on .chat-header that fires BEFORE React.
var _dragObserver = new MutationObserver(function() {
  var header = document.querySelector('.chat-header');
  if (header && !header._glimpseDragBound) {
    header._glimpseDragBound = true;
    header.addEventListener('mousedown', function(e) {
      if (e.target.closest('button') || e.target.closest('[data-no-drag]')) return;
      window.webkit.messageHandlers.glimpse.postMessage({ command: '_start_drag' });
    }, true); // capture phase — fires before React's bubble-phase handler
    _dragObserver.disconnect();
  }
});
_dragObserver.observe(document, { childList: true, subtree: true });

window.electronAPI = {
  // ── Thread management ──
  getThreads: () => invoke('get_threads'),
  saveThread: (thread) => invoke('save_thread', { thread }),
  deleteThread: (id) => invoke('delete_thread', { id }),

  // ── AI ──
  chatWithAI: (messages, provider, modelId) => invoke('chat_with_ai', { messages, provider, modelId }),
  generateTitle: (messages, provider, modelId) => invoke('generate_title', { messages, provider, modelId }),

  // ── API keys & providers ──
  getApiKeys: () => invoke('get_api_keys'),
  saveApiKeys: (keys) => invoke('save_api_keys', { keys }),
  deleteApiKey: (provider) => invoke('delete_api_key', { provider }),
  getAvailableProviders: () => invoke('get_available_providers'),
  validateInviteCode: (code) => invoke('validate_invite_code', { code }),

  // ── Preferences ──
  getPreferences: () => invoke('get_preferences'),
  setPreference: (key, value) => invoke('set_preference', { key, value }),

  // ── Window management ──
  closeHome: () => invoke('close_home'),
  closeWelcome: () => invoke('close_welcome'),
  closeSettings: () => invoke('close_settings'),
  closeChatWindow: () => invoke('close_chat_window'),
  closeOverlay: () => invoke('close_overlay'),
  openSettings: (panelBounds) => invoke('toggle_settings', { panelBounds: panelBounds || null }),
  openThreadInChat: (threadId) => invoke('open_thread_in_chat', { threadId }),
  welcomeDone: () => invoke('welcome_done'),
  chatReady: () => invoke('chat_ready'),
  pinChat: (threadData, bounds) => invoke('pin_chat', { threadData: threadData || null, bounds: bounds || null }),
  togglePin: () => invoke('toggle_pin'),
  showToast: (message) => invoke('show_toast', { message }),
  notifyProvidersChanged: () => invoke('notify_providers_changed'),
  refreshTrayMenu: () => invoke('refresh_tray_menu'),
  resizeChatWindow: (size) => invoke('resize_chat_window', { size }),
  selectFolder: () => invoke('select_folder'),
  copyImage: (dataUrl) => invoke('copy_image', { dataUrl }),
  saveImage: (dataUrl) => invoke('save_image', { dataUrl }),

  // ── Permissions ──
  checkPermissions: () => invoke('check_permissions'),
  requestScreenPermission: () => invoke('request_screen_permission'),
  requestAccessibilityPermission: () => invoke('request_accessibility_permission'),
  openPermissionSettings: (type) => invoke('open_permission_settings', { type }),

  // ── Utilities ──
  openExternal: (url) => invoke('open_external', { url }),
  inputFocus: () => invoke('input_focus'),
  lowerOverlay: () => invoke('lower_overlay'),
  restoreOverlay: () => invoke('restore_overlay'),

  // ── Events ──
  onScreenCaptured: (cb) => listen('screen-captured', (data) => {
    cb(data.dataUrl, data.windowBounds, data.displayInfo, data.offset)
    // Auto-trigger hover detection at cursor position so the window under
    // the cursor is highlighted immediately (like Feishu/CleanShot)
    if (data.cursorX !== undefined) {
      setTimeout(() => {
        var el = document.elementFromPoint(data.cursorX, data.cursorY) || document.documentElement
        el.dispatchEvent(new MouseEvent('mousemove', {
          clientX: data.cursorX, clientY: data.cursorY, bubbles: true
        }))
      }, 50)
    }
  }),
  onNewCapture: (cb) => listen('new-capture', (data) => cb(data.dataUrl, data.displayInfo)),
  onPinState: (cb) => listen('pin-state', cb),
  onLoadThreadData: (cb) => listen('load-thread-data', cb),
  onSetCroppedImage: (cb) => listen('set-cropped-image', cb),
  onClearScreenshot: (cb) => listen('clear-screenshot', cb),
  onClearTextContext: (cb) => listen('clear-text-context', cb),
  onTextContext: (cb) => listen('text-context', cb),
  onShortcutTried: (cb) => listen('shortcut-tried', cb),
  onResetOverlay: (cb) => listen('reset-overlay', cb),
  onProvidersChanged: (cb) => listen('providers-changed', cb),
};
