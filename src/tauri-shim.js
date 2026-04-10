/**
 * Tauri shim — provides window.electronAPI using Tauri's invoke/listen APIs.
 * When running under Electron, this file is a no-op.
 * When running under Tauri, it populates window.electronAPI so React components
 * don't need any changes.
 */

if (window.__TAURI_INTERNALS__ && !window.electronAPI) {
  const { invoke } = window.__TAURI_INTERNALS__

  // Enable window dragging for Tauri
  // Tauri uses data-tauri-drag-region attribute instead of -webkit-app-region: drag
  const DRAG_SELECTORS = '.home-drag-bar, .welcome-drag-bar, .chat-header, .settings-header'
  const addDragRegions = () => {
    document.querySelectorAll(DRAG_SELECTORS).forEach(el => {
      el.setAttribute('data-tauri-drag-region', '')
    })
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', addDragRegions)
  } else {
    setTimeout(addDragRegions, 50)
  }
  new MutationObserver(() => setTimeout(addDragRegions, 50))
    .observe(document.documentElement, { childList: true, subtree: true })

  // Dynamic imports for Tauri plugins
  const eventModule = import('@tauri-apps/api/event')
  const shellModule = import('@tauri-apps/plugin-shell')

  // Helper: listen to Tauri events, return unlisten function
  async function listen(event, callback) {
    const { listen: tauriListen } = await eventModule
    return tauriListen(event, (e) => callback(e.payload))
  }

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
    openExternal: async (url) => {
      const { open } = await shellModule
      open(url)
    },
    inputFocus: () => invoke('input_focus'),
    lowerOverlay: () => invoke('lower_overlay'),
    restoreOverlay: () => invoke('restore_overlay'),

    // ── Events ──
    onScreenCaptured: (callback) => listen('screen-captured', (data) => callback(data.dataUrl, data.windowBounds, data.displayInfo, data.offset)),
    onNewCapture: (callback) => listen('new-capture', (data) => callback(data.dataUrl, data.displayInfo)),
    onPinState: (callback) => listen('pin-state', callback),
    onLoadThreadData: (callback) => listen('load-thread-data', callback),
    onSetCroppedImage: (callback) => listen('set-cropped-image', callback),
    onClearScreenshot: (callback) => listen('clear-screenshot', callback),
    onClearTextContext: (callback) => listen('clear-text-context', callback),
    onTextContext: (callback) => listen('text-context', callback),
    onShortcutTried: (callback) => listen('shortcut-tried', callback),
    onResetOverlay: (callback) => listen('reset-overlay', callback),
    onProvidersChanged: (callback) => listen('providers-changed', callback),
  }
}
