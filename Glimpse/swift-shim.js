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

// Universal window dragging: any mousedown on non-interactive "dead space" starts a drag.
// Uses capture phase to fire BEFORE React's bubble-phase handlers.
// Rule: everything inside a draggable container is draggable EXCEPT interactive elements.
//
// Draggable containers (essentially the whole chat/settings/welcome window):
//   .chat-only-inner — standalone chat (entire window)
//   .settings-inner  — settings window
//   .welcome-inner   — welcome window
//
// NOT draggable (interactive elements that consume clicks):
//   buttons, inputs, textareas, links, selects
//   .chat-msg — chat bubbles (user may select/copy text)
//   .chat-messages — scrollable message list
//   .chat-input-box — input container (textarea inside)
//   .model-menu — model selector dropdown
//   .overlay — screenshot overlay (has its own click handling)
//   .selection-move-handle, .sel-handle — selection resize
//   .drawing-canvas — annotation drawing
//   .edit-toolbar — annotation toolbar
//   .panel-resize-edge — window resize edges
//   [data-no-drag] — explicit opt-out
var _NO_DRAG_SELECTORS = 'button, input, textarea, select, a, [data-no-drag], ' +
  '.chat-msg, .chat-messages, .chat-input-box, .model-menu, ' +
  '.overlay, .selection-move-handle, .sel-handle, .drawing-canvas, ' +
  '.edit-toolbar, .panel-resize-edge, .thread-list, .board-grid-area, .viewer-image-area, .viewer-context';
var _DRAG_CONTAINERS = '.chat-only-inner, .settings-inner, .welcome-inner';
document.addEventListener('mousedown', function(e) {
  if (!e.target.closest(_DRAG_CONTAINERS)) return;
  if (e.target.closest(_NO_DRAG_SELECTORS)) return;
  var tag = e.target.tagName.toLowerCase();
  if (tag === 'button' || tag === 'input' || tag === 'textarea' || tag === 'a' || tag === 'select') return;
  window.webkit.messageHandlers.glimpse.postMessage({ command: '_start_drag' });
}, true);

window.electronAPI = {
  // ── Thread management ──
  getThreads: () => invoke('get_threads'),
  saveThread: (thread) => invoke('save_thread', { thread }),
  deleteThread: (id) => invoke('delete_thread', { id }),
  saveThreadImage: (threadId, messageIndex, base64Data, mediaType) =>
    invoke('save_thread_image', { threadId, messageIndex, base64Data, mediaType }),
  getAllImages: () => invoke('get_all_images'),
  showImageViewer: (path, dataUrl, allImages, currentIndex, messageIndices) => invoke('show_image_viewer', {
    path: path || null, dataUrl: dataUrl || null,
    allImages: allImages || [], currentIndex: currentIndex || 0,
    messageIndices: messageIndices || []
  }),
  showImageViewerData: (dataUrl) => invoke('show_image_viewer', { dataUrl }),

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
  overlayRendered: () => invoke('overlay_rendered'),
  openSettings: (panelBounds) => invoke('toggle_settings', { panelBounds: panelBounds || null }),
  openThreadInChat: (threadId) => invoke('open_thread_in_chat', { threadId }),
  welcomeDone: () => invoke('welcome_done'),
  chatReady: () => invoke('chat_ready'),
  welcomeReady: () => invoke('welcome_ready'),
  settingsReady: () => invoke('settings_ready'),
  pinChat: (threadData, bounds) => invoke('pin_chat', { threadData: threadData || null, bounds: bounds || null }),
  togglePin: () => invoke('toggle_pin'),
  showToast: (message) => invoke('show_toast', { message }),
  notifyProvidersChanged: () => invoke('notify_providers_changed'),
  notifyNewThread: () => invoke('notify_new_thread'),
  notifyThreadLoaded: () => invoke('notify_thread_loaded'),
  refreshTrayMenu: () => invoke('refresh_tray_menu'),
  resizeChatWindow: (size) => {
    invoke('resize_chat_window', { size });
    // Return a promise that resolves when the native resize animation completes
    return new Promise((resolve) => {
      window._onResizeComplete = () => {
        window._onResizeComplete = null;
        resolve();
      };
      // Safety timeout — resolve even if callback never fires
      setTimeout(() => {
        if (window._onResizeComplete) {
          window._onResizeComplete = null;
          resolve();
        }
      }, 500);
    });
  },
  selectFolder: () => invoke('select_folder'),
  copyImage: (dataUrl) => invoke('copy_image', { dataUrl }),
  saveImage: (dataUrl) => invoke('save_image', { dataUrl }),

  // ── Permissions ──
  checkPermissions: () => invoke('check_permissions'),
  requestScreenPermission: () => invoke('request_screen_permission'),
  requestAccessibilityPermission: () => invoke('request_accessibility_permission'),
  openPermissionSettings: (type) => invoke('open_permission_settings', { type }),

  // ── Utilities ──
  log: (msg) => invoke('log', { msg }),
  openExternal: (url) => invoke('open_external', { url }),
  inputFocus: () => invoke('input_focus'),
  lowerOverlay: () => invoke('lower_overlay'),
  restoreOverlay: () => invoke('restore_overlay'),

  // ── Events ──
  onScreenCaptured: (cb) => listen('screen-captured', (data) => {
    // imageURL is a file:// URL to a unique JPEG in /tmp (timestamp in filename)
    var imageUrl = data.imageURL || data.dataUrl
    cb(imageUrl, data.windowBounds, data.displayInfo, data.offset, data.selection || null, data.startNewThread || false, data.compact || false)
    // Auto-trigger hover detection at cursor position so the window under
    // the cursor is highlighted immediately (only when no pre-applied selection)
    if (!data.selection && data.cursorX !== undefined) {
      setTimeout(() => {
        var el = document.elementFromPoint(data.cursorX, data.cursorY) || document.documentElement
        el.dispatchEvent(new MouseEvent('mousemove', {
          clientX: data.cursorX, clientY: data.cursorY, bubbles: true
        }))
      }, 50)
    }
  }),
  onNewCapture: (cb) => listen('new-capture', (data) => cb(data.dataUrl, data.displayInfo)),
  onApplySelection: (cb) => listen('apply-selection', cb),
  onPinState: (cb) => listen('pin-state', cb),
  onLoadThreadData: (cb) => listen('load-thread-data', cb),
  onSetCroppedImage: (cb) => listen('set-cropped-image', cb),
  onClearScreenshot: (cb) => listen('clear-screenshot', cb),
  onClearTextContext: (cb) => listen('clear-text-context', cb),
  // onCheckSize removed — Swift decides chat state via decideChatState()
  onStartNewThread: (cb) => listen('start-new-thread', cb),
  onTextContext: (cb) => listen('text-context', cb),
  onShortcutTried: (cb) => listen('shortcut-tried', cb),
  onResetOverlay: (cb) => listen('reset-overlay', cb),
  onResetOverlayKeepThread: (cb) => listen('reset-overlay-keep-thread', cb),
  onProvidersChanged: (cb) => listen('providers-changed', cb),
  onAutoSend: (cb) => listen('auto-send', cb),
  onViewMode: (cb) => listen('view-mode', cb),
};
