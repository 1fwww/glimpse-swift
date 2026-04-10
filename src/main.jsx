import './tauri-shim'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import ChatOnlyApp from './ChatOnlyApp'
import WelcomeApp from './WelcomeApp'
import SettingsApp from './SettingsApp'
import HomeApp from './HomeApp'

// ── Theme system: apply on every window startup ──
function applyTheme() {
  const pref = localStorage.getItem('glimpse-theme') || 'light'
  const root = document.documentElement
  root.classList.remove('theme-light', 'theme-dark')
  if (pref === 'light') {
    root.classList.add('theme-light')
  } else if (pref === 'dark') {
    // dark is :root default, no class needed
  } else {
    // system
    if (window.matchMedia('(prefers-color-scheme: light)').matches) {
      root.classList.add('theme-light')
    }
  }
}

// Apply immediately (before render to avoid flash)
applyTheme()

// Sync when another window changes the theme via localStorage
window.addEventListener('storage', (e) => {
  if (e.key === 'glimpse-theme') applyTheme()
})

// Sync when OS theme changes (for "system" mode)
window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', () => {
  const pref = localStorage.getItem('glimpse-theme') || 'light'
  if (pref === 'system') applyTheme()
})

// ── Render ──
const hash = window.location.hash
const root = ReactDOM.createRoot(document.getElementById('root'))

if (hash.startsWith('#home')) {
  root.render(<HomeApp />)
} else if (hash.startsWith('#welcome')) {
  root.render(<WelcomeApp />)
} else if (hash.startsWith('#settings')) {
  root.render(<SettingsApp />)
} else if (hash.startsWith('#chat-only')) {
  root.render(<ChatOnlyApp />)
} else {
  root.render(<App />)
}
