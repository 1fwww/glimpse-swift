import React, { useState } from 'react'

const PROVIDERS = [
  { id: 'anthropic', name: 'Anthropic (Claude)', placeholder: 'sk-ant-...', keyName: 'ANTHROPIC_API_KEY', url: 'https://console.anthropic.com/settings/keys' },
  { id: 'openai', name: 'OpenAI', placeholder: 'sk-...', keyName: 'OPENAI_API_KEY', url: 'https://platform.openai.com/api-keys' },
  { id: 'gemini', name: 'Google Gemini', placeholder: 'AIza...', keyName: 'GEMINI_API_KEY', url: 'https://aistudio.google.com/apikey' },
]

export default function ApiKeySetup({ onDone, onSkip }) {
  const [mode, setMode] = useState('keys')
  const [selectedProvider, setSelectedProvider] = useState(null)
  const [savedProviders, setSavedProviders] = useState([])
  const [keyInput, setKeyInput] = useState('')
  const [inviteCode, setInviteCode] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const hasInput = mode === 'keys' ? keyInput.trim() : inviteCode.trim()

  const handleSave = async () => {
    if (!hasInput) return
    setSaving(true)
    setError('')

    if (mode === 'invite') {
      const result = await window.electronAPI?.validateInviteCode(inviteCode.trim())
      setSaving(false)
      if (result?.valid) onDone()
      else setError(result?.error || 'Invalid invite code')
      return
    }

    const provider = PROVIDERS.find(p => p.id === selectedProvider)
    if (!provider) return
    const keys = { [provider.keyName]: keyInput.trim() }
    const result = await window.electronAPI?.saveApiKeys(keys)
    setSaving(false)
    if (result?.success) {
      setSavedProviders(prev => [...prev, selectedProvider])
      setSelectedProvider(null)
      setKeyInput('')
    } else {
      setError(result?.error || 'Failed to save')
    }
  }

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && hasInput) handleSave()
  }

  const switchMode = () => {
    setError('')
    setMode(mode === 'keys' ? 'invite' : 'keys')
    setSelectedProvider(null)
    setKeyInput('')
  }

  return (
    <div className="api-key-setup">
      <div className="api-key-header">
        <h2>Connect to AI</h2>
      </div>

      {mode === 'keys' ? (
        <>
          {savedProviders.length === 0 && <p className="api-key-desc">Keys stay on your device.</p>}

          {selectedProvider === null ? (
            <>
              <div className="api-key-providers">
                {PROVIDERS.map(p => (
                  <button
                    key={p.id}
                    className={`api-key-provider-btn ${savedProviders.includes(p.id) ? 'saved' : ''}`}
                    onClick={() => { if (!savedProviders.includes(p.id)) { setSelectedProvider(p.id); setKeyInput(''); setError('') } }}
                    disabled={savedProviders.includes(p.id)}
                  >
                    <span>{p.name}</span>
                    {savedProviders.includes(p.id) ? (
                      <svg className="check-icon" viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M20 6L9 17l-5-5" /></svg>
                    ) : (
                      <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18l6-6-6-6" /></svg>
                    )}
                  </button>
                ))}
              </div>
              {savedProviders.length > 0 && (
                <button className="api-key-save" onClick={onDone}>
                  Continue
                </button>
              )}
            </>
          ) : (
            <div className="api-key-input-section">
              <button className="api-key-back" onClick={() => { setSelectedProvider(null); setKeyInput(''); setError('') }}>
                <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2"><path d="M15 18l-6-6 6-6" /></svg>
                {PROVIDERS.find(p => p.id === selectedProvider)?.name}
              </button>
              <div className="api-key-field">
                <input
                  type="password"
                  placeholder={PROVIDERS.find(p => p.id === selectedProvider)?.placeholder}
                  value={keyInput}
                  onChange={(e) => setKeyInput(e.target.value)}
                  onKeyDown={handleKeyDown}
                  spellCheck={false}
                  autoFocus
                  aria-label={`${PROVIDERS.find(p => p.id === selectedProvider)?.name} API key`}
                />
                {!error && (
                  <span className="api-key-hint">
                    <button className="api-key-hint-link" onClick={() => window.electronAPI?.openExternal(PROVIDERS.find(p => p.id === selectedProvider)?.url)}>
                      Get key
                    </button>
                  </span>
                )}
              </div>

              {error && <div className="api-key-error">Invalid key. <button className="api-key-error-link" onClick={() => window.electronAPI?.openExternal(PROVIDERS.find(p => p.id === selectedProvider)?.url)}>Get a new one</button></div>}

              <button className="api-key-save" onClick={handleSave} disabled={!hasInput || saving}>
                {saving ? 'Verifying...' : 'Connect'}
              </button>
            </div>
          )}
        </>
      ) : (
        <>
          <div className="api-key-field">
            <input
              type="text"
              placeholder="Enter invite code"
              value={inviteCode}
              onChange={(e) => setInviteCode(e.target.value)}
              onKeyDown={handleKeyDown}
              spellCheck={false}
              autoFocus
              aria-label="Invite code"
              className="invite-code-input"
            />
          </div>

          {error && <div className="api-key-error">{error}</div>}

          <button className="api-key-save" onClick={handleSave} disabled={!hasInput || saving}>
            {saving ? 'Verifying...' : 'Connect'}
          </button>
        </>
      )}

      <div className="api-key-footer">
        <button className="api-key-link" onClick={switchMode}>
          {mode === 'keys' ? 'Use invite code' : 'Use API keys'}
        </button>
        {onSkip && (
          <>
            <span className="api-key-dot" aria-hidden="true">·</span>
            <button className="api-key-link" onClick={onSkip}>Skip for now</button>
          </>
        )}
      </div>
    </div>
  )
}
