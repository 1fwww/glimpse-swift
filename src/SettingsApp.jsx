import React, { useState, useEffect, useRef } from 'react'
import './app.css'

export default function SettingsApp() {
  const [apiKeys, setApiKeys] = useState({ ANTHROPIC_API_KEY: '', GEMINI_API_KEY: '', hasAnyKey: false, isInvite: false })
  const [prefs, setPrefs] = useState({ launchAtLogin: false, saveLocation: 'ask', savePath: '' })
  const [editingKey, setEditingKey] = useState(null)
  const [keyInput, setKeyInput] = useState('')
  const [saving, setSaving] = useState(false)
  const [keySaved, setKeySaved] = useState(null)
  const [keyError, setKeyError] = useState('')
  const [deletingKey, setDeletingKey] = useState(null)
  const [theme, setTheme] = useState(() => localStorage.getItem('glimpse-theme') || 'system')
  const [showInvite, setShowInvite] = useState(false)
  const [inviteCode, setInviteCode] = useState('')
  const [inviteError, setInviteError] = useState('')
  const [inviteSaving, setInviteSaving] = useState(false)

  useEffect(() => {
    loadData()
  }, [])

  const loadData = async () => {
    const keys = await window.electronAPI?.getApiKeys()
    if (keys) setApiKeys(keys)
    const p = await window.electronAPI?.getPreferences()
    if (p) setPrefs(p)
  }

  const handleDeleteKey = async (provider) => {
    await window.electronAPI?.deleteApiKey(provider)
    setDeletingKey(null)
    loadData()
  }

  const handleThemeChange = (value) => {
    setTheme(value)
    localStorage.setItem('glimpse-theme', value)
    // Apply theme class to document
    const root = document.documentElement
    root.classList.remove('theme-light', 'theme-dark')
    if (value === 'light') root.classList.add('theme-light')
    else if (value === 'dark') root.classList.add('theme-dark')
    else {
      // System: follow prefers-color-scheme
      if (window.matchMedia('(prefers-color-scheme: light)').matches) root.classList.add('theme-light')
    }
  }

  const handleSaveKey = async (provider) => {
    if (!keyInput.trim()) return
    setSaving(true)
    setKeyError('')
    const keys = {}
    if (provider === 'anthropic') keys.ANTHROPIC_API_KEY = keyInput.trim()
    if (provider === 'gemini') keys.GEMINI_API_KEY = keyInput.trim()
    if (provider === 'openai') keys.OPENAI_API_KEY = keyInput.trim()
    const result = await window.electronAPI?.saveApiKeys(keys)
    setSaving(false)
    if (result?.success) {
      setEditingKey(null)
      setKeyInput('')
      setKeySaved(provider)
      setTimeout(() => setKeySaved(null), 1500)
      loadData()
      window.electronAPI?.notifyProvidersChanged?.()
    } else {
      setKeyError(result?.error || 'Invalid key')
    }
  }

  const handleInviteCode = async () => {
    if (!inviteCode.trim()) return
    setInviteSaving(true)
    setInviteError('')
    const result = await window.electronAPI?.validateInviteCode(inviteCode.trim())
    setInviteSaving(false)
    if (result?.valid) {
      setShowInvite(false)
      setInviteCode('')
      loadData()
      window.electronAPI?.notifyProvidersChanged?.()
    } else {
      setInviteError(result?.error || 'Invalid code')
    }
  }

  const handleToggleLaunchAtLogin = async () => {
    const newVal = !prefs.launchAtLogin
    await window.electronAPI?.setPreference('launchAtLogin', newVal)
    setPrefs(p => ({ ...p, launchAtLogin: newVal }))
  }

  const suppressBlur = useRef(false)

  const handleSaveLocationChange = async (value) => {
    if (value === 'folder') {
      suppressBlur.current = true
      const result = await window.electronAPI?.selectFolder()
      suppressBlur.current = false
      if (result) {
        await window.electronAPI?.setPreference('saveLocation', 'folder')
        await window.electronAPI?.setPreference('savePath', result)
        setPrefs(p => ({ ...p, saveLocation: 'folder', savePath: result }))
      }
    } else {
      await window.electronAPI?.setPreference('saveLocation', 'ask')
      setPrefs(p => ({ ...p, saveLocation: 'ask', savePath: '' }))
    }
  }

  const handleClose = () => {
    window.electronAPI?.closeSettings?.()
  }

  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') handleClose()
    }
    let blurTimer = null
    const handleBlur = () => {
      if (suppressBlur.current) return
      blurTimer = setTimeout(handleClose, 150)
    }
    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('blur', handleBlur)
    return () => {
      clearTimeout(blurTimer)
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('blur', handleBlur)
    }
  }, [])

  return (
    <div className="settings-app">
      <div className="settings-inner">
      <div className="settings-header">
        <h1 className="settings-title">Settings</h1>
        <button className="settings-close" onClick={handleClose} aria-label="Close settings">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M18 6L6 18M6 6l12 12" />
          </svg>
        </button>
      </div>
      <div className="settings-content">
        {/* API Keys */}
        <div className="settings-section">
          <h2 className="settings-section-title">API Keys</h2>

          {apiKeys.isInvite && (
            <div className="settings-invite-row">
              <span className="settings-invite-badge">Using invite code</span>
              <button className="settings-invite-link" onClick={async () => {
                await window.electronAPI?.deleteApiKey('invite')
                loadData()
              }}>Use my own keys</button>
            </div>
          )}
          {!apiKeys.isInvite && (
            <>
              {[
                { id: 'anthropic', label: 'Anthropic', keyField: 'ANTHROPIC_API_KEY', placeholder: 'sk-ant-...' },
                { id: 'gemini', label: 'Gemini', keyField: 'GEMINI_API_KEY', placeholder: 'AIza...' },
                { id: 'openai', label: 'OpenAI', keyField: 'OPENAI_API_KEY', placeholder: 'sk-...' },
              ].map(p => (
                <div key={p.id} className="settings-key-row">
                  <div className="settings-key-info">
                    <span className="settings-key-label">{p.label}</span>
                    <span className={`settings-key-value ${keySaved === p.id ? 'key-saved' : ''}`}>
                      {keySaved === p.id ? '✓ Saved' : (apiKeys[p.keyField] || 'Not configured')}
                    </span>
                  </div>
                  {editingKey === p.id ? (
                    <div className="settings-key-edit">
                      <input
                        type="password"
                        placeholder={p.placeholder}
                        value={keyInput}
                        onChange={(e) => setKeyInput(e.target.value)}
                        onKeyDown={(e) => e.key === 'Enter' && handleSaveKey(p.id)}
                        autoFocus
                        spellCheck={false}
                        aria-label={`${p.label} API key`}
                      />
                      <div className="settings-key-actions">
                        <button className="settings-btn-sm" onClick={() => handleSaveKey(p.id)} disabled={saving}>
                          {saving ? '...' : 'Save'}
                        </button>
                        <button className="settings-btn-sm cancel" onClick={() => { setEditingKey(null); setKeyInput(''); setKeyError('') }}>Cancel</button>
                      </div>
                      {keyError && <div className="settings-key-error">{keyError}</div>}
                    </div>
                  ) : deletingKey === p.id ? (
                    <div className="settings-delete-confirm">
                      <span className="settings-delete-text">Delete this key?</span>
                      <button className="settings-btn-sm danger" onClick={() => handleDeleteKey(p.id)}>Delete</button>
                      <button className="settings-btn-sm" onClick={() => setDeletingKey(null)}>Keep</button>
                    </div>
                  ) : (
                    <div className="settings-key-actions">
                      <button className="settings-btn-sm" onClick={() => { setEditingKey(p.id); setKeyInput(''); setKeyError('') }}>
                        {apiKeys[p.keyField] ? 'Update' : 'Add'}
                      </button>
                      {apiKeys[p.keyField] && (
                        <button className="settings-btn-sm danger" onClick={() => setDeletingKey(p.id)}>Delete</button>
                      )}
                    </div>
                  )}
                </div>
              ))}
              {!showInvite ? (
                <button className="settings-invite-link" onClick={() => setShowInvite(true)}>
                  Have an invite code?
                </button>
              ) : (
                <div className="settings-invite-input">
                  <input
                    type="text"
                    placeholder="Enter invite code"
                    value={inviteCode}
                    onChange={(e) => setInviteCode(e.target.value)}
                    onKeyDown={(e) => e.key === 'Enter' && handleInviteCode()}
                    autoFocus
                    spellCheck={false}
                    aria-label="Invite code"
                  />
                  <button className="settings-btn-sm" onClick={handleInviteCode} disabled={inviteSaving}>
                    {inviteSaving ? '...' : 'Apply'}
                  </button>
                  <button className="settings-btn-sm cancel" onClick={() => { setShowInvite(false); setInviteCode(''); setInviteError('') }}>Cancel</button>
                  {inviteError && <div className="settings-key-error">{inviteError}</div>}
                </div>
              )}
            </>
          )}
        </div>

        {/* Preferences */}
        <div className="settings-section">
          <h2 className="settings-section-title">Preferences</h2>

          <div className="settings-pref-row">
            <span className="settings-pref-label">Appearance</span>
            <div className="settings-btn-group">
              <button className={`settings-btn-group-item ${theme === 'light' ? 'active' : ''}`} onClick={() => handleThemeChange('light')}>Light</button>
              <button className={`settings-btn-group-item ${theme === 'dark' ? 'active' : ''}`} onClick={() => handleThemeChange('dark')}>Dark</button>
              <button className={`settings-btn-group-item ${theme === 'system' ? 'active' : ''}`} onClick={() => handleThemeChange('system')}>System</button>
            </div>
          </div>

          <div className="settings-pref-row">
            <span className="settings-pref-label">Launch at login</span>
            <button
              className={`settings-toggle ${prefs.launchAtLogin ? 'on' : ''}`}
              onClick={handleToggleLaunchAtLogin}
              role="switch"
              aria-checked={prefs.launchAtLogin}
              aria-label="Launch at login"
            >
              <div className="settings-toggle-knob" />
            </button>
          </div>

          <div className="settings-pref-row">
            <span className="settings-pref-label">Save screenshots to</span>
            <div className="settings-btn-group">
              <button
                className={`settings-btn-group-item ${prefs.saveLocation === 'ask' ? 'active' : ''}`}
                onClick={() => handleSaveLocationChange('ask')}
              >
                Ask each time
              </button>
              <button
                className={`settings-btn-group-item ${prefs.saveLocation === 'folder' ? 'active' : ''}`}
                onClick={() => handleSaveLocationChange('folder')}
              >
                {prefs.saveLocation === 'folder' && prefs.savePath
                  ? `/${prefs.savePath.split('/').pop()}`
                  : 'Choose folder'}
              </button>
            </div>
          </div>
        </div>

        {/* Shortcuts */}
        <div className="settings-section">
          <h2 className="settings-section-title">Shortcuts</h2>
          <div className="settings-shortcut-row">
            <span className="settings-pref-label">Screenshot</span>
            <span className="settings-shortcut-keys"><kbd>Cmd</kbd><kbd>Shift</kbd><kbd>Z</kbd></span>
          </div>
          <div className="settings-shortcut-row">
            <div className="settings-shortcut-info">
              <span className="settings-pref-label">Text chat</span>
              <span className="settings-shortcut-hint">Select text first, then press</span>
            </div>
            <span className="settings-shortcut-keys"><kbd>Cmd</kbd><kbd>Shift</kbd><kbd>X</kbd></span>
          </div>
          <span className="settings-shortcuts-note">Customizable shortcuts coming soon</span>
        </div>
      </div>
      <div className="settings-footer">
        <span className="settings-version">Glimpse v0.2.0</span>
        <button className="settings-esc-btn" onClick={handleClose}><kbd>Esc</kbd> to close</button>
      </div>
      </div>
    </div>
  )
}
