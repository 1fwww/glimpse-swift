import React, { useState, useRef, useEffect, useCallback } from 'react'
import ReactDOM from 'react-dom'
import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import ApiKeySetup from './ApiKeySetup'

const BROW_RESTING = "M98 212C152 174 365 158 420 248"
const BROW_FOCUSED = "M98 192C200 192 350 204 420 234"

const BoardIcon = ({ size = 24 }) => (
  <svg viewBox="0 0 100 100" width={size} height={size}>
    <rect x="8" y="8" width="38" height="38" rx="6" fill="none" stroke="currentColor" strokeWidth="5" />
    <rect x="54" y="8" width="38" height="38" rx="6" fill="none" stroke="currentColor" strokeWidth="5" />
    <rect x="8" y="54" width="38" height="38" rx="6" fill="none" stroke="currentColor" strokeWidth="5" />
    <rect x="54" y="54" width="38" height="38" rx="6" fill="none" stroke="currentColor" strokeWidth="5" />
  </svg>
)

const GlimpseIcon = ({ size = 20, focused = false }) => (
  <svg viewBox="60 140 420 280" width={size} height={Math.round(size * 280 / 420)}>
    {/* Eyebrow — crossfade between resting and focused */}
    <path d={BROW_RESTING} fill="none" stroke="#6C63FF" strokeWidth="20" strokeLinecap="round" style={{ opacity: focused ? 0 : 1, transition: 'opacity 0.3s ease' }} />
    <path d={BROW_FOCUSED} fill="none" stroke="#6C63FF" strokeWidth="20" strokeLinecap="round" style={{ opacity: focused ? 1 : 0, transition: 'opacity 0.3s ease' }} />
    <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="#6C63FF" strokeWidth="22" strokeLinecap="round" />
  </svg>
)

function Tooltip({ text, children }) {
  const [pos, setPos] = useState(null)
  const ref = useRef(null)
  // Dismiss tooltip when window loses focus (mouse may leave without onMouseLeave)
  useEffect(() => {
    if (!pos) return
    const dismiss = () => setPos(null)
    window.addEventListener('blur', dismiss)
    return () => window.removeEventListener('blur', dismiss)
  }, [pos])
  return (
    <span
      ref={ref}
      onMouseEnter={() => {
        const r = ref.current?.getBoundingClientRect()
        if (!r) return
        const centerX = r.left + r.width / 2
        const nearRight = centerX > window.innerWidth - 50
        const nearLeft = centerX < 50
        const spaceBelow = window.innerHeight - r.bottom
        if (spaceBelow > 34) {
          setPos({ left: centerX, top: r.bottom + 6, above: false, nearRight, nearLeft })
        } else {
          setPos({ left: centerX, top: r.top - 6, above: true, nearRight, nearLeft })
        }
      }}
      onMouseLeave={() => setPos(null)}
      style={{ display: 'inline-flex' }}
      data-no-drag
    >
      {children}
      {pos && ReactDOM.createPortal(
        <div className="chat-tooltip" style={{
          left: pos.nearRight ? undefined : pos.left,
          right: pos.nearRight ? 8 : undefined,
          top: pos.above ? undefined : pos.top,
          bottom: pos.above ? (window.innerHeight - pos.top) : undefined,
          transform: pos.nearRight ? 'none' : pos.nearLeft ? 'none' : 'translateX(-50%)',
          animation: (pos.nearRight || pos.nearLeft) ? 'none' : undefined,
        }}>{text}</div>,
        document.body
      )}
    </span>
  )
}

function ExpandableSnippet({ text, onDismiss }) {
  const [expanded, setExpanded] = useState(false)
  const isLong = text.length > 150
  const preview = isLong ? text.slice(0, 80) + ' … ' + text.slice(-30) : text
  return (
    <div className="msg-snippet" onClick={() => isLong && setExpanded(!expanded)} style={isLong ? { cursor: 'pointer' } : undefined}>
      {onDismiss && <button className="snippet-dismiss" onClick={(e) => { e.stopPropagation(); onDismiss() }}>×</button>}
      <div className="msg-snippet-text">{expanded ? text : preview}</div>
      {isLong && <span className="msg-snippet-toggle">{expanded ? 'Show less' : 'Show more'}</span>}
    </div>
  )
}

function generateId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

export default function ChatPanel({
  style,
  croppedImage,
  getCompositeImage,
  currentThread,
  setCurrentThread,
  recentThreads,
  onThreadChange,
  onNewThread,
  onClearAllThreads,
  onDismissScreenshot,
  initialContext = { text: '', seq: 0 },
  annotationCount,
  chatFullSize,
  setChatFullSize,
  isNewThread,
  setIsNewThread,
  refreshThreads,
  refreshProviders,
  onClose,
  onMinimize,
  onPin,
  onSentWithImage,
  autoSendPending,
  onAutoSendConsumed,
  isPinned,
  isWindowBlurred,
  onExitViewMode,
  skipNextScrollRef,
  onToggleBoard,
  boardActive,
  onTogglePin,
  provider,
  setProvider,
  modelId,
  setModelId,
  availableProviders,
}) {
  const [input, setInput] = useState('')
  const [threadMenuOpen, setThreadMenuOpen] = useState(false)
  const [textContext, setTextContext] = useState(initialContext?.text || '')
  const [showApiKeySetup, setShowApiKeySetup] = useState(false)
  const [modelMenuOpen, setModelMenuOpen] = useState(false)
  const [modelMenuPos, setModelMenuPos] = useState(null)
  const [showWelcome, setShowWelcome] = useState(false)
  const pendingQuestion = useRef(null)
  const pendingImageRef = useRef(null)
  const pendingSnippetRef = useRef(null)

  // Update textContext when initialContext arrives via IPC (including clear)
  useEffect(() => {
    setTextContext(initialContext?.text || '')
  }, [initialContext?.seq])

  // Strip file-referenced images for AI API calls — replace with text placeholder.
  // apiMessages.current keeps file refs (for saving), this is only for the API.
  const getApiSafeMessages = () => apiMessages.current.map(m => ({
    ...m,
    content: (m.content || []).map(c =>
      (c.type === 'image' && c.source?.type === 'file')
        ? { type: 'text', text: '[screenshot]' }
        : c
    ),
  }))

  const [isLoading, setIsLoading] = useState(false)
  const [messages, setMessages] = useState([])
  const [screenshotAttached, setScreenshotAttached] = useState(true)
  const [isAtBottom, setIsAtBottom] = useState(true)
  const bottomZoneRef = useRef(null)
  // Scroll-driven view mode: chrome fades as user scrolls while pinned+blurred
  const scrollAccum = useRef(0)
  const lastScrollTop = useRef(0)
  const headerRef = useRef(null)
  const viewModeActiveRef = useRef(false)
  const chromeHeights = useRef({ header: 0, bottom: 0 })
  const messagesEndRef = useRef(null)
  const lastAssistantRef = useRef(null)
  const messagesContainerRef = useRef(null)
  const suppressScrollHandler = useRef(false)
  const inputRef = useRef(null)
  const modelSelectorRef = useRef(null)
  const apiMessages = useRef([])
  const lastSentImageRef = useRef(null)
  const prevThreadIdRef = useRef(null)
  // Always reflects the LATEST thread ID — survives async awaits unlike closure values
  const currentThreadIdRef = useRef(currentThread?.id || null)
  currentThreadIdRef.current = currentThread?.id || null

  // Load messages from current thread
  useEffect(() => {
    const prevId = prevThreadIdRef.current
    const newId = currentThread?.id
    const isNewThreadGettingId = prevId === null && newId && apiMessages.current.length > 0

    // Always clear loading when switching to a different thread —
    // "Glimpsing..." must never follow across threads.
    if (!isNewThreadGettingId && prevId !== newId) {
      setIsLoading(false)
    }

    // Skip reload when a new thread just gets its first ID (preserve in-session images)
    if (!isNewThreadGettingId) {
            if (currentThread?.messages?.length > 0) {
        setMessages(currentThread.messages.map(m => {
          if (m.role === 'assistant') {
            return { role: 'assistant', text: (m.content || []).map(c => c.text || '').join(''), model: m.model }
          }
          const rawText = (m.content || []).map(c => c.type === 'text' ? c.text : '').join(' ').trim()
          const imageBlock = (m.content || []).find(c => c.type === 'image')
          let image = null
          let imagePath = null  // relative path for image viewer IPC
          if (imageBlock?.source?.type === 'file' && imageBlock.source.path) {
            imagePath = imageBlock.source.path
            const fullPath = `${window._glimpseAppSupportDir}/${imageBlock.source.path}`
            image = 'file://' + fullPath.split('/').map(s => encodeURIComponent(s)).join('/')
          } else if (imageBlock?.source?.data) {
            image = `data:${imageBlock.source.media_type || 'image/jpeg'};base64,${imageBlock.source.data}`
          }
          // Parse out [Referenced text: "..."] and annotation notes
          const refMatch = rawText.match(/^\[Referenced text: "(.+?)"\]\s*\n*(?:\[Note:.*?\]\s*\n*)?(.*)$/s)
          const annotMatch = rawText.match(/^\[Note:.*?\]\s*\n*(.*)$/s)
          if (refMatch) {
            return { role: 'user', text: refMatch[2].trim(), snippet: refMatch[1], image, imagePath }
          }
          if (annotMatch) {
            return { role: 'user', text: annotMatch[1].trim(), image, imagePath }
          }
          return { role: 'user', text: rawText, image, imagePath }
        }))
        // Keep file references in apiMessages — they're needed for saving back to disk.
        // File images are stripped only at the point of sending to the AI API.
        apiMessages.current = [...(currentThread.messages || [])]
      } else {
        setMessages([])
        apiMessages.current = []
      }
    }
    if (!isNewThreadGettingId) {
      setScreenshotAttached(true)
      lastSentImageRef.current = null
    }
    prevThreadIdRef.current = newId

    // Scroll to bottom only when switching to a DIFFERENT thread (ID changed).
    // Same-thread message additions (e.g., saveCurrentThread) should NOT scroll —
    // scrollToLastAssistant handles positioning after AI responds.
    const threadIdChanged = prevId !== newId

    // Check for pending scroll restore from overlay pin-out (even if thread ID unchanged)
    if (skipNextScrollRef?.current !== undefined && skipNextScrollRef?.current !== false) {
      const savedScrollTop = skipNextScrollRef.current
      skipNextScrollRef.current = false
      if (typeof savedScrollTop === 'number') {
        // Suppress flex-basis transition and scroll handler during restore
        const wrapper = messagesContainerRef.current?.closest('.chat-messages-wrapper')
        if (wrapper) wrapper.style.transition = 'none'
        suppressScrollHandler.current = true
        setTimeout(() => {
          whenLayoutStable(() => {
            const el = messagesContainerRef.current
            if (el) el.scrollTop = savedScrollTop
            requestAnimationFrame(() => {
              if (el) el.scrollTop = savedScrollTop
              suppressScrollHandler.current = false
              if (wrapper) wrapper.style.transition = ''
            })
          })
        }, 50)
      }
    } else if (!isNewThreadGettingId && threadIdChanged) {
      setIsAtBottom(true)
      setTimeout(() => {
        whenLayoutStable(() => {
          messagesEndRef.current?.scrollIntoView({ behavior: 'instant' })
        })
      }, 50)
    }
  }, [currentThread?.id, currentThread?.messages?.length])

  // Auto-send: overlay pinned out with a pending API call.
  // The thread data has the user message — just call chatWithAI.
  // Delay 100ms to ensure thread-loading useEffect has populated apiMessages.
  useEffect(() => {
    if (!autoSendPending) return
    const timer = setTimeout(async () => {
      if (apiMessages.current.length === 0) { return }
      onAutoSendConsumed?.()
      setIsLoading(true)
      setTimeout(() => scrollToRevealLoading(), 50)
      const isFirstMessage = apiMessages.current.length === 1
      // Snapshot for thread-switch safety (same pattern as sendMessage)
      const sendThreadId = currentThread?.id || generateId()
      const snapshotMessages = apiMessages.current.map(m => ({
        ...m,
        content: (m.content || []).map(c =>
          c.source ? { ...c, source: { ...c.source } } : { ...c }
        ),
      }))
      const snapshotTitle = currentThread?.title || 'New Chat'
      const snapshotCreatedAt = currentThread?.createdAt || Date.now()
      try {
        const result = await window.electronAPI.chatWithAI(getApiSafeMessages(), provider, modelId)

        // Thread switched while waiting — use ref (not stale closure)
        if (currentThreadIdRef.current !== sendThreadId) {
          setIsLoading(false)
          if (result.success) {
            const currentModelName = availableProviders.flatMap(p => p.models || []).find(m => m.id === modelId)?.name || ''
            snapshotMessages.push({ role: 'assistant', content: result.content, model: currentModelName })
            await saveCurrentThread({
              id: sendThreadId, title: snapshotTitle, messages: snapshotMessages,
              createdAt: snapshotCreatedAt, updatedAt: Date.now(),
            })
            if (isFirstMessage) {
              const title = await generateTitle(snapshotMessages.map(m => ({
                ...m, content: Array.isArray(m.content) ? m.content.filter(c => c.type !== 'image') : m.content,
              })))
              if (title) await saveCurrentThread({ id: sendThreadId, title, messages: snapshotMessages, createdAt: snapshotCreatedAt, updatedAt: Date.now() })
            }
            setIsNewThread(false)
          }
          return
        }

        // Same thread — normal flow
        setIsLoading(false)
        if (result.success) {
          const assistantText = result.content.map(c => c.text || '').join('')
          const currentModelName = availableProviders.flatMap(p => p.models || []).find(m => m.id === modelId)?.name || ''
          apiMessages.current.push({ role: 'assistant', content: result.content, model: currentModelName })
          setMessages(prev => [...prev, { role: 'assistant', text: assistantText, model: currentModelName }])
          if (!chatFullSize) setChatFullSize(true)
          await window.electronAPI?.resizeChatWindow?.({ width: 380, height: 550 })
          scrollToLastAssistant()
          const now = Date.now()
          const thread = {
            id: sendThreadId,
            title: snapshotTitle,
            messages: [...apiMessages.current],
            createdAt: snapshotCreatedAt,
            updatedAt: now,
          }
          await saveCurrentThread(thread)
          if (isFirstMessage) {
            const titleMsgs = apiMessages.current.map(m => ({
              ...m,
              content: Array.isArray(m.content) ? m.content.filter(c => c.type !== 'image') : m.content,
            }))
            const title = await generateTitle(titleMsgs)
            if (title) {
              thread.title = title
              await saveCurrentThread(thread)
              setIsNewThread(false)
            }
          }
        } else {
          setMessages(prev => [...prev, { role: 'assistant', text: `Error: ${result.error || 'Unknown error'}` }])
        }
      } catch (err) {
        setIsLoading(false)
        setMessages(prev => [...prev, { role: 'assistant', text: `Error: ${err.message}` }])
      }
    }, 100)
    return () => clearTimeout(timer)
  }, [autoSendPending]) // eslint-disable-line react-hooks/exhaustive-deps
  // Intentionally exclude currentThread?.id — auto-send must NOT re-fire on thread switch.
  // sendThreadId/snapshotTitle/snapshotCreatedAt capture values at fire time;
  // currentThreadIdRef.current detects switches after await.

  // Auto-focus input
  useEffect(() => {
    setTimeout(() => inputRef.current?.focus(), 100)
    // Retry focus when window gains focus (handles terminal stealing focus)
    // Also close menus — chat may have been hidden with menu open
    const handleFocus = () => {
      setThreadMenuOpen(false)
      setModelMenuOpen(false)
      // Don't auto-focus input when view mode is active (chrome is hidden)
      if (!viewModeActiveRef.current) {
        setTimeout(() => inputRef.current?.focus(), 50)
      }
    }
    window.addEventListener('focus', handleFocus)
    return () => window.removeEventListener('focus', handleFocus)
  }, [currentThread?.id])

  // Close thread menu on outside click
  useEffect(() => {
    if (!threadMenuOpen) return
    const handleClick = (e) => {
      if (!e.target.closest('.thread-menu-popup') && !e.target.closest('.chat-header-title-btn')) {
        setThreadMenuOpen(false)
      }
    }
    window.addEventListener('click', handleClick, { capture: true })
    return () => window.removeEventListener('click', handleClick, { capture: true })
  }, [threadMenuOpen, setThreadMenuOpen])

  // Close model menu on outside click
  useEffect(() => {
    if (!modelMenuOpen) return
    const handleClick = (e) => {
      if (!e.target.closest('.model-selector') && !e.target.closest('.model-dropdown')) setModelMenuOpen(false)
    }
    window.addEventListener('click', handleClick, { capture: true })
    return () => window.removeEventListener('click', handleClick, { capture: true })
  }, [modelMenuOpen])

  // When croppedImage changes (new screenshot), re-attach
  useEffect(() => {
    if (croppedImage) {
      setScreenshotAttached(true)
      lastSentImageRef.current = null
    }
  }, [croppedImage])

  // When annotations change (user edited the screenshot), re-attach
  const prevAnnotationCount = useRef(0)
  useEffect(() => {
    if (annotationCount !== prevAnnotationCount.current && croppedImage) {
      prevAnnotationCount.current = annotationCount
      if (!screenshotAttached && annotationCount > 0) {
        setScreenshotAttached(true)
      }
    }
  }, [annotationCount])

  // Listen for provider changes from Settings
  useEffect(() => {
    window.electronAPI?.onProvidersChanged?.(() => {
      if (refreshProviders) refreshProviders()
    })
  }, [refreshProviders])

  // Expand panel when setup appears, lower overlay so user can switch apps
  useEffect(() => {
    if (showApiKeySetup) {
      if (!chatFullSize) setChatFullSize(true)
      window.electronAPI?.resizeChatWindow?.({ width: 380, height: 550 })
      window.electronAPI?.lowerOverlay?.()
    } else {
      window.electronAPI?.restoreOverlay?.()
    }
  }, [showApiKeySetup])

  // After welcome animation, auto-send pending question (skip re-adding user msg)
  useEffect(() => {
    if (!showWelcome && pendingQuestion.current && availableProviders.length === 0) {
      // Keys saved but no providers available (e.g. dev mode without env vars)
      pendingQuestion.current = null
      setMessages(prev => [...prev, { role: 'assistant', text: 'No API keys found. Please add a key in Settings.' }])
      return
    }
    if (!showWelcome && pendingQuestion.current && availableProviders.length > 0) {
      if (!provider || !modelId) {
        return
      }
      const q = pendingQuestion.current
      const pendingImage = pendingImageRef.current
      const pendingSnippet = pendingSnippetRef.current
      pendingQuestion.current = null
      pendingImageRef.current = null
      pendingSnippetRef.current = null
      setInput('')

      // Build API message from the already-displayed user message
      const contentBlocks = []
      if (pendingImage) {
        const mediaType = pendingImage.startsWith('data:image/jpeg') ? 'image/jpeg' : 'image/png'
        contentBlocks.push({ type: 'image', source: { type: 'base64', media_type: mediaType, data: pendingImage.split(',')[1] } })
      }
      let apiText = q
      if (pendingSnippet) {
        apiText = `[Referenced text: "${pendingSnippet}"]\n\n${q}`
        setTextContext('')
      }
      contentBlocks.push({ type: 'text', text: apiText })
      apiMessages.current.push({ role: 'user', content: contentBlocks })

      // Send to AI without re-adding user message to UI
      setIsLoading(true)
      setTimeout(() => scrollToRevealLoading(), 50)
      ;(async () => {
        try {
          const result = await window.electronAPI.chatWithAI(getApiSafeMessages(), provider, modelId)
          setIsLoading(false)
          if (!result?.success) {
            if (result?.code === 'auth_error' || result?.error?.includes('No API key')) {
              // Re-save pending state so it retries after key setup
              pendingQuestion.current = q
              pendingImageRef.current = pendingImage
              pendingSnippetRef.current = pendingSnippet
              apiMessages.current.pop()
              if (refreshProviders) refreshProviders()
              setShowApiKeySetup(true)
            } else {
              setMessages(prev => [...prev, { role: 'assistant', text: `Error: ${result?.error || 'Something went wrong'}` }])
            }
          } else {
            const assistantText = result.content.map(c => c.text || '').join('')
            const currentModelName = availableProviders.flatMap(p => p.models || []).find(m => m.id === modelId)?.name || ''
            apiMessages.current.push({ role: 'assistant', content: result.content, model: currentModelName })
            // Add message, expand panel, then scroll to top of assistant response
            setMessages(prev => [...prev, { role: 'assistant', text: assistantText, model: currentModelName }])
            if (!chatFullSize) setChatFullSize(true)
            await window.electronAPI?.resizeChatWindow?.({ width: 380, height: 550 })
            scrollToLastAssistant()

            // Save thread + generate title
            const now = Date.now()
            const thread = {
              id: currentThread?.id || generateId(),
              title: currentThread?.title || 'New Chat',
              messages: [...apiMessages.current],
              createdAt: currentThread?.createdAt || now,
              updatedAt: now,
            }
            await saveCurrentThread(thread)

            const titleMsgs = apiMessages.current.map(m => ({
              ...m,
              content: Array.isArray(m.content)
                ? m.content.filter(c => c.type !== 'image')
                : m.content,
            }))
            const title = await generateTitle(titleMsgs)
            if (title) {
              thread.title = title
              await saveCurrentThread(thread)
              setIsNewThread(false)
            }
          }
        } catch (err) {
          setIsLoading(false)
          const msg = typeof err === 'string' ? err : (err.message || 'Something went wrong')
          if (msg.includes('API key') || msg.includes('api key') || msg.includes('not found')) {
            pendingQuestion.current = q
            pendingImageRef.current = pendingImage
            pendingSnippetRef.current = pendingSnippet
            apiMessages.current.pop()
            if (refreshProviders) refreshProviders()
            setShowApiKeySetup(true)
          } else {
            setMessages(prev => [...prev, { role: 'assistant', text: `Error: ${msg}` }])
          }
        }
      })()
    }
  }, [showWelcome, availableProviders, provider, modelId])

  // Connected animation completion — fade out then dismiss
  useEffect(() => {
    if (showWelcome) {
      const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
      const timer = setTimeout(() => {
        setShowWelcome(false)
      }, reducedMotion ? 500 : 4500)
      return () => clearTimeout(timer)
    }
  }, [showWelcome])

  // Track scroll position (always active)
  const expandBtnRef = useRef(null)
  const headerIconsRef = useRef(null)
  const scrollDownBtnRef = useRef(null)

  const handleScroll = useCallback(() => {
    if (suppressScrollHandler.current) return
    const el = messagesContainerRef.current
    if (!el) return
    const threshold = 30
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < threshold
    setIsAtBottom(atBottom)
  }, [])

  // Scroll-driven view mode via wheel event (fires on non-key windows).
  // Only when pinned + window blurred.
  useEffect(() => {
    if (!isPinned) return
    const panel = panelRef.current
    if (!panel) return

    const handleWheel = (e) => {
      if (!isWindowBlurred || viewModeActiveRef.current) return
      const delta = Math.abs(e.deltaY)
      if (delta < 1) return

      // Measure heights once on first wheel
      if (!chromeHeights.current.header && headerRef.current && bottomZoneRef.current) {
        chromeHeights.current.header = headerRef.current.offsetHeight
        chromeHeights.current.bottom = bottomZoneRef.current.offsetHeight
      }

      const hH = chromeHeights.current.header
      const bH = chromeHeights.current.bottom
      if (!hH || !bH) return

      scrollAccum.current = Math.min(scrollAccum.current + delta, 80)
      const progress = Math.min(scrollAccum.current / 80, 1)

      // Hide scroll-to-bottom button during slide
      if (scrollDownBtnRef.current) scrollDownBtnRef.current.style.display = 'none'

      const hdr = headerRef.current
      const btm = bottomZoneRef.current
      if (hdr) {
        const slide = progress * hH
        hdr.style.transform = `translateY(${-slide}px)`
        hdr.style.marginBottom = `${-slide}px`
        hdr.style.opacity = String(1 - progress)
        hdr.style.pointerEvents = 'none'
      }
      if (btm) {
        const slide = progress * bH
        btm.style.transform = `translateY(${slide}px)`
        btm.style.marginTop = `${-slide}px`
        btm.style.opacity = String(1 - progress)
        btm.style.pointerEvents = 'none'
      }

      if (progress >= 1) {
        viewModeActiveRef.current = true
        if (expandBtnRef.current) expandBtnRef.current.style.display = ''
        if (headerIconsRef.current) headerIconsRef.current.style.display = ''
        // Extra padding so messages aren't hidden behind gradient edges
        if (messagesContainerRef.current) {
          messagesContainerRef.current.style.paddingTop = '48px'
          messagesContainerRef.current.style.paddingBottom = '40px'
        }
      }
    }

    panel.addEventListener('wheel', handleWheel, { passive: true })
    return () => panel.removeEventListener('wheel', handleWheel)
  }, [isPinned, isWindowBlurred])

  const scrollToBottom = useCallback(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [])

  // Reset on unpin or expand button click
  const resetViewMode = useCallback(() => {
    const wasActive = viewModeActiveRef.current
    scrollAccum.current = 0
    lastScrollTop.current = messagesContainerRef.current?.scrollTop || 0
    viewModeActiveRef.current = false
    chromeHeights.current = { header: 0, bottom: 0 }
    if (headerRef.current) headerRef.current.style.cssText = ''
    if (bottomZoneRef.current) bottomZoneRef.current.style.cssText = ''
    if (expandBtnRef.current) expandBtnRef.current.style.display = 'none'
    if (headerIconsRef.current) headerIconsRef.current.style.display = 'none'
    if (scrollDownBtnRef.current) scrollDownBtnRef.current.style.display = ''
    if (messagesContainerRef.current) {
      messagesContainerRef.current.style.paddingTop = ''
      messagesContainerRef.current.style.paddingBottom = ''
    }
    if (wasActive) {
      setTimeout(() => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'instant' })
        inputRef.current?.focus()
      }, 100)
    }
  }, [])

  useEffect(() => {
    if (!isPinned) resetViewMode()
  }, [isPinned])

  const handleViewHintClick = useCallback(() => {
    resetViewMode()
    onExitViewMode?.()
  }, [onExitViewMode, resetViewMode])

  // Wait for all message images to load + layout to settle before measuring for scroll.
  // Data URL images may report complete=true before layout; double rAF ensures paint.
  const whenLayoutStable = useCallback((fn) => {
    const el = messagesContainerRef.current
    if (!el) { fn(); return }
    const images = el.querySelectorAll('img.msg-image')
    const unloaded = [...images].filter(img => !img.complete)
    const afterLayout = () => requestAnimationFrame(() => requestAnimationFrame(fn))
    if (unloaded.length) {
      Promise.all(unloaded.map(img => new Promise(r => { img.onload = r; img.onerror = r })))
        .then(afterLayout)
    } else {
      afterLayout()
    }
  }, [])

  const scrollToLastAssistant = useCallback(() => {
    if (!lastAssistantRef.current || !messagesContainerRef.current) return
    const el = messagesContainerRef.current
    el.scrollTop = 0
    whenLayoutStable(() => {
      if (!lastAssistantRef.current) return
      const msgRect = lastAssistantRef.current.getBoundingClientRect()
      const containerRect = el.getBoundingClientRect()
      el.scrollTop = msgRect.top - containerRect.top
    })
  }, [whenLayoutStable])

  // Scroll so the loading indicator ("Glimpsing...") is just visible at the bottom
  const scrollToRevealLoading = useCallback(() => {
    if (!lastAssistantRef.current || !messagesContainerRef.current) return
    const el = messagesContainerRef.current
    el.scrollTop = 0
    whenLayoutStable(() => {
      if (!lastAssistantRef.current) return
      const msgRect = lastAssistantRef.current.getBoundingClientRect()
      const containerRect = el.getBoundingClientRect()
      const targetScroll = msgRect.top - containerRect.top - containerRect.height + msgRect.height + 40
      el.scrollTop = Math.max(0, targetScroll)
    })
  }, [whenLayoutStable])

  // (scroll-to-message is handled directly by ChatOnlyApp via DOM query)

  const saveCurrentThread = useCallback(async (thread) => {
    // Save images to disk and replace base64 blocks with file references
    const savedMessages = await Promise.all(thread.messages.map(async (m, idx) => ({
      ...m,
      content: await Promise.all(m.content.map(async (c) => {
        if (c.type === 'image' && c.source?.type === 'base64') {
          const result = await window.electronAPI?.saveThreadImage(
            thread.id, idx, c.source.data, c.source.media_type
          )
          if (result?.success) {
            return { type: 'image', source: { type: 'file', path: result.path, media_type: c.source.media_type } }
          }
          return { type: 'text', text: '[screenshot]' } // fallback
        }
        return c // file references and text blocks pass through
      })),
    })))

    const savedThread = { ...thread, messages: savedMessages }
    await window.electronAPI?.saveThread(savedThread)

    // Update both currentThread and apiMessages with file refs so base64
    // images are only saved to disk once. File images are stripped to
    // [screenshot] only at the chatWithAI() call site via getApiSafeMessages().
    setCurrentThread(savedThread)
    apiMessages.current = savedMessages

    refreshThreads()
    window.electronAPI?.refreshTrayMenu?.()
  }, [setCurrentThread, refreshThreads])

  const generateTitle = useCallback(async (msgs) => {
    if (!window.electronAPI?.generateTitle) return null
    try {
      const result = await window.electronAPI.generateTitle(msgs, provider, modelId)
      if (result.success) return result.title
    } catch {}
    return null
  }, [provider, modelId])

  const sendMessage = async (overrideText) => {
    const text = (overrideText || input).trim()
    const hasAttachment = textContext || (screenshotAttached && croppedImage)
    if ((!text && !hasAttachment) || isLoading) return

    // No API keys configured → show setup
    if (!availableProviders.length) {
      pendingQuestion.current = text
      setInput('')
      if (!chatFullSize) setChatFullSize(true)
      // Show user's message in chat
      const msgEntry = { role: 'user', text }
      if (textContext) {
        msgEntry.snippet = textContext
        pendingSnippetRef.current = textContext
        setTextContext('')
      }
      if (croppedImage) {
        const composite = await getCompositeImage?.(croppedImage)
        msgEntry.image = composite || croppedImage
        pendingImageRef.current = msgEntry.image
        setScreenshotAttached(false)
      }
      setMessages([msgEntry])
      setIsLoading(true)
      setTimeout(() => {
        setIsLoading(false)
        setShowApiKeySetup(true)
        if (!chatFullSize) setChatFullSize(true)
      }, 1000)
      return
    }

    setInput('')
    const contentBlocks = []

    // Auto-attach: first message, new screenshot, or annotations changed
    const noMessagesSentYet = apiMessages.current.length === 0
    const willAttachImage = croppedImage && (noMessagesSentYet || screenshotAttached)
    let imageForChat = croppedImage
    if (willAttachImage) {
      // Use annotated composite if available — pass croppedImage directly
      // to avoid stale closure in getCompositeImage's useCallback
      const composite = await getCompositeImage?.(croppedImage)
      if (composite) imageForChat = composite
      const mediaType = imageForChat.startsWith('data:image/jpeg') ? 'image/jpeg' : 'image/png'
      contentBlocks.push({
        type: 'image',
        source: {
          type: 'base64',
          media_type: mediaType,
          data: imageForChat.split(',')[1],
        },
      })
    }

    // Build API text with context
    let apiText = text || (textContext ? 'What is this?' : 'What do you see?')
    const sentSnippet = textContext || null
    if (textContext) {
      apiText = `[Referenced text: "${textContext}"]\n\n${text || 'What is this?'}`
      setTextContext('')
    }
    if (willAttachImage && annotationCount > 0) {
      apiText = `[Note: The user has drawn annotations on the screenshot to highlight areas of interest. Pay close attention to the marked/highlighted regions.]\n\n${apiText}`
    }
    contentBlocks.push({ type: 'text', text: apiText })

    const userApiMsg = { role: 'user', content: contentBlocks }
    apiMessages.current.push(userApiMsg)

    // UI message shows clean text only
    const uiMsg = {
      role: 'user',
      text,
      image: willAttachImage ? imageForChat : null,
      snippet: sentSnippet,
    }
    setMessages(prev => [...prev, uiMsg])
    setIsLoading(true)

    // Scroll to reveal "Glimpsing..." loading indicator
    setTimeout(() => scrollToRevealLoading(), 50)

    if (willAttachImage) {
      lastSentImageRef.current = croppedImage
      setScreenshotAttached(false)
      // Pin out to standalone chat — let IT make the API call.
      // Send currentThread.messages (preserves file refs for UI thumbnails)
      // plus the new user message.
      if (onSentWithImage) {
        const now = Date.now()
        onSentWithImage({
          id: currentThread?.id || generateId(),
          title: currentThread?.title || 'New Chat',
          messages: [...(currentThread?.messages || []), userApiMsg],
          createdAt: currentThread?.createdAt || now,
          updatedAt: now,
        })
        return // Don't call API from overlay — standalone will handle it
      }
    }

    const isFirstMessage = apiMessages.current.length === 1
    const sendThreadId = currentThread?.id || generateId()
    // Deep-clone messages before the await. If user switches threads,
    // apiMessages.current gets overwritten but this snapshot survives intact
    // with original base64 image data.
    const snapshotMessages = apiMessages.current.map(m => ({
      ...m,
      content: (m.content || []).map(c =>
        c.source ? { ...c, source: { ...c.source } } : { ...c }
      ),
    }))
    const snapshotTitle = currentThread?.title || 'New Chat'
    const snapshotCreatedAt = currentThread?.createdAt || Date.now()

    try {
      const result = await window.electronAPI.chatWithAI(getApiSafeMessages(), provider, modelId)

      // Thread changed while waiting — use snapshot to save the complete
      // conversation (user message + image + AI response) via saveCurrentThread,
      // which persists images and navigates back via setCurrentThread.
      // Thread switched while waiting — use ref (not stale closure)
      if (currentThreadIdRef.current !== sendThreadId) {
        setIsLoading(false)
        if (result.success) {
          const currentModelName = availableProviders.flatMap(p => p.models || []).find(m => m.id === modelId)?.name || ''
          snapshotMessages.push({ role: 'assistant', content: result.content, model: currentModelName })
          const thread = {
            id: sendThreadId,
            title: snapshotTitle,
            messages: snapshotMessages,
            createdAt: snapshotCreatedAt,
            updatedAt: Date.now(),
          }
          await saveCurrentThread(thread)
          if (isFirstMessage) {
            const title = await generateTitle(snapshotMessages.map(m => ({
              ...m, content: Array.isArray(m.content) ? m.content.filter(c => c.type !== 'image') : m.content,
            })))
            if (title) { thread.title = title; await saveCurrentThread(thread) }
          }
          setIsNewThread(false)
        }
        return
      }

      // Still on same thread — normal flow
      setIsLoading(false)

      if (result.success) {
        const assistantText = result.content.map(c => c.text || '').join('')
        const currentModelName = availableProviders.flatMap(p => p.models || []).find(m => m.id === modelId)?.name || ''
        const assistantApiMsg = { role: 'assistant', content: result.content, model: currentModelName }
        apiMessages.current.push(assistantApiMsg)
        // Add message, expand panel, then scroll to top of assistant response
        setMessages(prev => [...prev, { role: 'assistant', text: assistantText, model: currentModelName }])
        if (!chatFullSize) setChatFullSize(true)
        await window.electronAPI?.resizeChatWindow?.({ width: 380, height: 550 })
        scrollToLastAssistant()

        const now = Date.now()
        const thread = {
          id: sendThreadId,
          title: snapshotTitle,
          messages: [...apiMessages.current],
          createdAt: snapshotCreatedAt,
          updatedAt: now,
        }
        await saveCurrentThread(thread)

        if (isFirstMessage) {
          // Strip images to save tokens for title generation
          const titleMsgs = apiMessages.current.map(m => ({
            ...m,
            content: Array.isArray(m.content)
              ? m.content.filter(c => c.type !== 'image')
              : m.content,
          }))
          const title = await generateTitle(titleMsgs)
          if (title) {
            thread.title = title
            await saveCurrentThread(thread)
            setIsNewThread(false)
          }
        }
      } else {
        if (result.code === 'auth_error' || result.error?.includes('No API key')) {
          // Save pending state so message auto-sends after key setup
          const lastUserMsg = apiMessages.current[apiMessages.current.length - 1]
          if (lastUserMsg?.role === 'user') {
            const textBlock = (lastUserMsg.content || []).find(c => c.type === 'text')
            const imageBlock = (lastUserMsg.content || []).find(c => c.type === 'image')
            pendingQuestion.current = textBlock?.text || ''
            if (imageBlock) pendingImageRef.current = `data:${imageBlock.source?.media_type || 'image/png'};base64,${imageBlock.source?.data}`
            apiMessages.current.pop()
          }
          if (refreshProviders) refreshProviders()
          setShowApiKeySetup(true)
        } else {
          setMessages(prev => [...prev, { role: 'assistant', text: `Error: ${result.error || 'Something went wrong'}` }])
        }
      }
    } catch (err) {
      const msg = typeof err === 'string' ? err : (err.message || 'Something went wrong')
      if (msg.includes('API key') || msg.includes('api key') || msg.includes('not found')) {
        // Save pending state so message auto-sends after key setup
        const lastUserMsg = apiMessages.current[apiMessages.current.length - 1]
        if (lastUserMsg?.role === 'user') {
          const textBlock = (lastUserMsg.content || []).find(c => c.type === 'text')
          const imageBlock = (lastUserMsg.content || []).find(c => c.type === 'image')
          pendingQuestion.current = textBlock?.text || ''
          if (imageBlock) pendingImageRef.current = `data:${imageBlock.source?.media_type || 'image/png'};base64,${imageBlock.source?.data}`
          apiMessages.current.pop()
        }
        if (refreshProviders) refreshProviders()
        setShowApiKeySetup(true)
      } else {
        setMessages(prev => [...prev, { role: 'assistant', text: `Error: ${msg}` }])
      }
    }

    setIsLoading(false)
  }

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
    if (e.key === 'Escape') {
      inputRef.current?.blur()
    }
  }

  const threadTitle = currentThread?.title || 'New Chat'
  const showScrollDown = !isAtBottom && !isLoading && !viewModeActiveRef.current
  const [eyebrowWiggle, setEyebrowWiggle] = useState(false)
  const [eyeAnim, setEyeAnim] = useState('') // 'blink' | 'draw' | ''
  const [titleAnim, setTitleAnim] = useState(0)
  const triggerTitleAnim = () => setTitleAnim(k => k + 1)


  // Draggable panel — use refs + direct DOM + rAF for smooth 60fps (no React re-render)
  const dragOffsetRef = useRef({ x: 0, y: 0 })
  const panelRef = useRef(null)
  const isDragging = useRef(false)
  const dragStart = useRef({ x: 0, y: 0 })
  const dragRaf = useRef(null)
  const dragPending = useRef({ x: 0, y: 0 })

  // Resizable panel
  const [sizeOffset, setSizeOffset] = useState({ w: 0, h: 0 })
  const isResizingPanel = useRef(false)
  const resizeStart = useRef({ x: 0, y: 0, w: 0, h: 0 })
  const resizeEdge = useRef(null)

  const handleHeaderMouseDown = (e) => {
    if (e.target.closest('button') || e.target.closest('[data-no-drag]')) return
    // In standalone/pinned mode, use Tauri native window drag
    if (chatFullSize) {
      if (window.__TAURI_INTERNALS__) {
        import('@tauri-apps/api/window').then(({ getCurrentWindow }) => {
          getCurrentWindow().startDragging()
        })
      }
      return
    }
    isDragging.current = true
    dragStart.current = { x: e.clientX - dragOffsetRef.current.x, y: e.clientY - dragOffsetRef.current.y }
    // Promote to GPU layer + disable content interaction for smooth dragging
    if (panelRef.current) {
      panelRef.current.style.willChange = 'transform'
      panelRef.current.classList.add('panel-dragging')
    }

    const handleMouseMove = (ev) => {
      if (!isDragging.current) return
      dragPending.current = { x: ev.clientX - dragStart.current.x, y: ev.clientY - dragStart.current.y }
      if (!dragRaf.current) {
        dragRaf.current = requestAnimationFrame(() => {
          dragRaf.current = null
          const { x, y } = dragPending.current
          dragOffsetRef.current = { x, y }
          if (panelRef.current) {
            panelRef.current.style.transform = `translate(${x}px, ${y}px)`
          }
        })
      }
    }
    const handleMouseUp = () => {
      isDragging.current = false
      if (dragRaf.current) { cancelAnimationFrame(dragRaf.current); dragRaf.current = null }
      if (panelRef.current) {
        panelRef.current.style.willChange = ''
        panelRef.current.classList.remove('panel-dragging')
      }
      window.removeEventListener('mousemove', handleMouseMove)
      window.removeEventListener('mouseup', handleMouseUp)
    }
    window.addEventListener('mousemove', handleMouseMove)
    window.addEventListener('mouseup', handleMouseUp)
  }

  const handleResizeMouseDown = (edge) => (e) => {
    e.stopPropagation()
    e.preventDefault()
    isResizingPanel.current = true
    resizeEdge.current = edge
    resizeStart.current = { x: e.clientX, y: e.clientY, w: sizeOffset.w, h: sizeOffset.h }

    const handleMouseMove = (ev) => {
      if (!isResizingPanel.current) return
      const dx = ev.clientX - resizeStart.current.x
      const dy = ev.clientY - resizeStart.current.y
      const newOffset = { ...sizeOffset }

      if (edge === 'left') newOffset.w = resizeStart.current.w - dx
      else if (edge === 'right') newOffset.w = resizeStart.current.w + dx
      if (edge === 'top') newOffset.h = resizeStart.current.h - dy
      else if (edge === 'bottom') newOffset.h = resizeStart.current.h + dy

      // Clamp: min width 300, max 600; min height 200
      newOffset.w = Math.max(-80, Math.min(220, newOffset.w))
      newOffset.h = Math.max(-120, Math.min(300, newOffset.h))
      setSizeOffset(newOffset)
    }
    const handleMouseUp = () => {
      isResizingPanel.current = false
      window.removeEventListener('mousemove', handleMouseMove)
      window.removeEventListener('mouseup', handleMouseUp)
    }
    window.addEventListener('mousemove', handleMouseMove)
    window.addEventListener('mouseup', handleMouseUp)
  }

  const panelStyle = {
    ...style,
    width: 380 + sizeOffset.w,
    height: (style.height || 320) + sizeOffset.h,
    transform: `translate(${dragOffsetRef.current.x}px, ${dragOffsetRef.current.y}px)`,
  }

  return (
    <div
      ref={panelRef}
      className={`chat-panel ${isNewThread ? 'chat-panel-new' : ''} ${isPinned ? 'chat-panel-pinned pinned-panel' : ''}`}
      style={panelStyle}
      onMouseDown={(e) => e.stopPropagation()}
    >
      {/* Resize handles */}
      <div className="panel-resize-edge left" onMouseDown={handleResizeMouseDown('left')} />
      <div className="panel-resize-edge right" onMouseDown={handleResizeMouseDown('right')} />
      <div className="panel-resize-edge top" onMouseDown={handleResizeMouseDown('top')} />
      <div className="panel-resize-edge bottom" onMouseDown={handleResizeMouseDown('bottom')} />

      {/* Header — drag handle */}
      <div ref={headerRef} className="chat-header" onMouseDown={handleHeaderMouseDown} {...(chatFullSize ? {'data-tauri-drag-region': ''} : {})}>
        <span
            className={`glimpse-icon-fixed ${boardActive ? '' : `chat-header-eye ${eyeAnim === 'draw' ? 'logo-draw-only' : eyebrowWiggle ? 'logo-single-blink' : ''}`}`}
            onClick={(e) => {
              e.stopPropagation()
              if (chatFullSize && onToggleBoard) {
                onToggleBoard()
                return
              }
              if (!boardActive && !isLoading && !eyeAnim) {
                setEyebrowWiggle(false)
                void e.currentTarget.offsetWidth
                setEyebrowWiggle(true)
                setTimeout(() => setEyebrowWiggle(false), 500)
              }
            }}
            style={{ cursor: 'pointer' }}
          >
            {boardActive ? <BoardIcon size={24} /> : <GlimpseIcon size={26} focused={isPinned} />}
          </span>
        <div className="chat-header-info" style={{ position: 'relative' }}>
          <button
            className="chat-header-title-btn"
            onClick={() => { if (!threadMenuOpen) refreshThreads(); setThreadMenuOpen(!threadMenuOpen) }}
            aria-label="Switch thread"
            aria-expanded={threadMenuOpen}
            aria-haspopup="menu"
          >
            <span className={`chat-header-title ${titleAnim ? 'title-reveal' : ''}`} key={titleAnim}>{threadTitle}</span>
            <svg className={`chat-header-chevron ${threadMenuOpen ? 'open' : ''}`} viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2.5">
              <path d="M6 9l6 6 6-6" />
            </svg>
          </button>
          {threadMenuOpen && (
            <>
              <div className="thread-menu-popup header-popup" role="menu" aria-label="Thread history">
                {recentThreads.filter(t => t.id !== currentThread?.id).length > 0 ? (
                  <>
                    {recentThreads.filter(t => t.id !== currentThread?.id).map(t => (
                      <button key={t.id} className="thread-menu-item" role="menuitem" onClick={() => { onThreadChange(t); setThreadMenuOpen(false); triggerTitleAnim() }} title={t.title}>
                        <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" /></svg>
                        <span>{t.title}</span>
                      </button>
                    ))}
                    <div className="thread-menu-divider" />
                    <button className="thread-menu-item thread-menu-clear" role="menuitem" onClick={() => { onClearAllThreads(); setThreadMenuOpen(false) }}>
                      <span>Clear all chats</span>
                    </button>
                  </>
                ) : (
                  <div className="thread-menu-empty">No other chats</div>
                )}
              </div>
            </>
          )}
        </div>
        <Tooltip text="New chat">
          <button
            className={`chat-header-new`}
            onClick={(e) => {
              onNewThread(); setEyeAnim('draw'); setTimeout(() => setEyeAnim(''), 850); triggerTitleAnim()
              const btn = e.currentTarget; btn.classList.add('press'); setTimeout(() => btn.classList.remove('press'), 150)
            }}
            aria-label="New chat"
          >
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M12 5v14M5 12h14" />
            </svg>
          </button>
        </Tooltip>
        {(onTogglePin || onPin) && (
          <>
          <Tooltip text={isPinned ? 'Unpin' : 'Pin to screen'}>
            <button
              className={`chat-header-pin ${isPinned ? 'pinned' : ''}`}
              onClick={() => {
                const handler = onTogglePin || (() => onPin({ screenshotAttached }))
                handler()
                // Eye blink on pin
                if (!isPinned) { setEyeAnim('blink'); setTimeout(() => setEyeAnim(''), 900) }
              }}
              disabled={isLoading}
              aria-label={isPinned ? 'Unpin' : 'Pin to screen'}
            >
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 17v5" /><path d="M5 17h14v-1.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V6h1a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4h1v4.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24z" />
              </svg>
            </button>
          </Tooltip>
          </>
        )}
      </div>

      {/* Floating eye + pin in view mode (header slides away) */}
      {isPinned && (
        <div ref={headerIconsRef} className="view-mode-header-icons" style={{ display: 'none' }}>
          <span className="glimpse-icon-fixed chat-header-eye">
            <GlimpseIcon size={26} focused={true} />
          </span>
          {(onTogglePin || onPin) && (
            <button
              className={`chat-header-pin pinned`}
              onClick={() => {
                const handler = onTogglePin || (() => onPin({ screenshotAttached }))
                handler()
              }}
              aria-label="Unpin"
            >
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 17v5" /><path d="M5 17h14v-1.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V6h1a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4h1v4.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24z" />
              </svg>
            </button>
          )}
        </div>
      )}

      {/* Messages */}
      <div className="chat-messages-wrapper">
        {showApiKeySetup ? (
          <ApiKeySetup onSkip={() => {
            setShowApiKeySetup(false)
            setMessages([])
            pendingQuestion.current = null
            pendingImageRef.current = null
            pendingSnippetRef.current = null
            setChatFullSize(false)
            if (onMinimize) onMinimize()
          }} onDone={async () => {
            // Await providers BEFORE changing state — otherwise React flushes
            // an intermediate render with (showApiKeySetup=false, providers=[], showWelcome=false)
            // which triggers the "No API keys found" useEffect and clears pendingQuestion.
            if (refreshProviders) await refreshProviders()
            setShowApiKeySetup(false)
            setShowWelcome(true)
          }} />
        ) : showWelcome ? (
          <div className="api-key-welcome connected-anim">
            <div className="c-eye-wrapper">
              <div className="c-eye">
                <svg className="c-closed" viewBox="60 140 420 280" width="100" height="67" aria-hidden="true">
                  <path className="brow" d="M98 212C152 174 365 158 420 248" fill="none" stroke="#6C63FF" strokeWidth="20" strokeLinecap="round"/>
                  <path className="spiral" d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="#6C63FF" strokeWidth="22" strokeLinecap="round"/>
                </svg>
                <svg className="c-awake" viewBox="60 140 420 280" width="100" height="67" aria-hidden="true">
                  <path className="brow" d="M98 212C152 174 365 158 420 248" fill="none" stroke="#6C63FF" strokeWidth="20" strokeLinecap="round"/>
                  <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="#6C63FF" strokeWidth="22" strokeLinecap="round"/>
                </svg>
              </div>
            </div>
            <span className="c-text">Connected. Happy Glimpsing!</span>
          </div>
        ) : (
          <>
            <div
              className="chat-messages"
              ref={messagesContainerRef}
              onScroll={handleScroll}
            >
              {messages.map((msg, i) => {
                const isLastAssistant = msg.role === 'assistant' && i === messages.length - 1
                return (
                  <div
                    key={i}
                    className={`chat-msg ${msg.role}`}
                    data-msg-index={i}
                    ref={isLastAssistant ? lastAssistantRef : null}
                  >
                    {msg.role === 'assistant' ? (
                      <>
                      <div className="msg-text"><Markdown remarkPlugins={[remarkGfm]} components={{
                        a: ({ href, children }) => (
                          <a href={href} onClick={(e) => { e.preventDefault(); window.electronAPI?.openExternal(href) }}>{children}</a>
                        ),
                        code: ({ className, children, node }) => {
                          const text = String(children).replace(/\n$/, '')
                          // Detect fenced code block: has language-* className
                          const isBlock = /language-/.test(className || '')
                          if (!isBlock) {
                            return (
                              <code
                                className="inline-code-copy"
                                title="Click to copy"
                                onClick={() => {
                                  navigator.clipboard.writeText(text)
                                  const el = document.activeElement
                                  if (el) { el.classList.add('code-copied'); setTimeout(() => el.classList.remove('code-copied'), 800) }
                                }}
                              >{children}</code>
                            )
                          }
                          const lang = className?.replace('language-', '') || ''
                          return (
                            <div className="code-block-wrapper">
                              {lang && <div className="code-block-header">
                                <span className="code-block-lang">{lang}</span>
                                <button className="code-block-copy" onClick={(e) => {
                                  navigator.clipboard.writeText(text)
                                  const btn = e.currentTarget
                                  btn.classList.add('copied')
                                  setTimeout(() => btn.classList.remove('copied'), 800)
                                }} aria-label="Copy code">
                                  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                                </button>
                              </div>}
                              {!lang && <button className="code-block-copy code-block-copy-float" onClick={(e) => {
                                navigator.clipboard.writeText(text)
                                const btn = e.currentTarget
                                btn.classList.add('copied')
                                setTimeout(() => btn.classList.remove('copied'), 800)
                              }} aria-label="Copy code">
                                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                              </button>}
                              <pre><code>{children}</code></pre>
                            </div>
                          )
                        },
                        pre: ({ children }) => {
                          // If code component already rendered a wrapper, unwrap
                          if (children?.props?.className === 'code-block-wrapper') return children
                          // Plain code block without language — wrap it ourselves
                          const text = typeof children?.props?.children === 'string' ? children.props.children.replace(/\n$/, '') : ''
                          return (
                            <div className="code-block-wrapper">
                              <button className="code-block-copy code-block-copy-float" onClick={(e) => {
                                navigator.clipboard.writeText(text)
                                const btn = e.currentTarget
                                btn.classList.add('copied')
                                setTimeout(() => btn.classList.remove('copied'), 800)
                              }} aria-label="Copy code">
                                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                              </button>
                              <pre><code>{children?.props?.children}</code></pre>
                            </div>
                          )
                        },
                        blockquote: ({ children }) => {
                          const ref = React.createRef()
                          return (
                            <blockquote className="bq-copyable" ref={ref}>
                              {children}
                              <button className="bq-copy-btn" onClick={() => {
                                const clone = ref.current?.cloneNode(true)
                                clone?.querySelector('.bq-copy-btn')?.remove()
                                const text = clone?.innerText?.trim()
                                if (text) {
                                  navigator.clipboard.writeText(text)
                                  const btn = ref.current?.querySelector('.bq-copy-btn')
                                  if (btn) { btn.classList.add('bq-copied'); setTimeout(() => btn.classList.remove('bq-copied'), 800) }
                                }
                              }} aria-label="Copy text">
                                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                              </button>
                            </blockquote>
                          )
                        },
                      }}>{msg.text}</Markdown></div>
                      {msg.model && <div className="msg-model-tag">{msg.model}</div>}
                      </>
                    ) : (
                      <>
                        {msg.image && (
                          <img
                            src={msg.image}
                            alt="screenshot"
                            className="msg-image msg-image-clickable"
                            onClick={() => {
                              // Collect all images in thread for arrow-key navigation
                              const imageMessages = messages.map((m, idx) => ({ m, idx })).filter(({ m }) => m.image)
                              const allImages = imageMessages.map(({ m }) => ({
                                path: m.imagePath || null,
                                dataUrl: (!m.imagePath && m.image) ? m.image : null
                              }))
                              const messageIndices = imageMessages.map(({ idx }) => idx)
                              const currentIndex = imageMessages.findIndex(({ m }) => m === msg)
                              window.electronAPI?.showImageViewer?.(
                                msg.imagePath || null,
                                (!msg.imagePath && msg.image) ? msg.image : null,
                                allImages,
                                currentIndex,
                                messageIndices
                              )
                            }}
                          />
                        )}
                        {msg.snippet && (
                          <ExpandableSnippet text={msg.snippet} />
                        )}
                        <div className="msg-text">{msg.text}</div>
                      </>
                    )}
                  </div>
                )
              })}
              {isLoading && (
                <div className="chat-msg assistant" ref={lastAssistantRef}>
                  <div className="thinking" role="status" aria-label="Processing your request">
                    <div className="scan-stage-sm">
                      <svg className="scan-ghost-sm" viewBox="60 140 420 280" width="28" height="19" aria-hidden="true">
                        <path d="M98 212C152 174 365 158 420 248" fill="none" stroke="#6C63FF" strokeWidth="20" strokeLinecap="round"/>
                        <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="#6C63FF" strokeWidth="22" strokeLinecap="round"/>
                      </svg>
                      <svg className="scan-reveal-sm" viewBox="60 140 420 280" width="28" height="19" aria-hidden="true">
                        <path d="M98 212C152 174 365 158 420 248" fill="none" stroke="#6C63FF" strokeWidth="20" strokeLinecap="round"/>
                        <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="#6C63FF" strokeWidth="22" strokeLinecap="round"/>
                      </svg>
                      <div className="scan-frame-sm" />
                    </div>
                    <span className="scan-label">Glimpsing...</span>
                  </div>
                </div>
              )}
              <div ref={messagesEndRef} />
            </div>

            {/* Scroll to bottom arrow */}
            {showScrollDown && (
              <button
                ref={scrollDownBtnRef}
                className="scroll-to-bottom"
                onClick={scrollToBottom}
              >
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M7 13l5 5 5-5M7 6l5 5 5-5" />
                </svg>
              </button>
            )}
          </>
        )}
        </div>

      {/* Bottom zone: input + actions — collapses in view mode */}
      <div
        ref={bottomZoneRef}
        className="chat-bottom-zone"
      >
      {/* Input */}
      <div className="chat-input-area">
        <div className="chat-input-box">
          {screenshotAttached && croppedImage && (
            <div className="input-attachment-cue">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" />
                <circle cx="12" cy="13" r="4" />
              </svg>
              <span>Screenshot attached</span>
              {onDismissScreenshot && (
                <button className="attachment-dismiss" onClick={() => {
                  onDismissScreenshot()
                  setTimeout(() => inputRef.current?.focus(), 50)
                }} aria-label="Remove screenshot">×</button>
              )}
            </div>
          )}
          {textContext && (
            <div className="text-context-wrapper">
              <ExpandableSnippet text={textContext} onDismiss={() => setTextContext('')} />
            </div>
          )}
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            onFocus={() => window.electronAPI?.inputFocus?.()}
            placeholder={isNewThread ? (croppedImage ? 'Ask about this screenshot...' : 'Start a conversation...') : 'Continue discussion...'}
            rows={2}
            disabled={showApiKeySetup}
            aria-label="Message input"
          />
          <button className="chat-send-arrow" onClick={() => sendMessage()} disabled={isLoading || (!input.trim() && !textContext && !(screenshotAttached && croppedImage)) || showApiKeySetup} aria-label="Send message">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 19V5M5 12l7-7 7 7" />
            </svg>
          </button>
        </div>
      </div>

      {/* Bottom bar */}
      <div className="thread-actions">
        <Tooltip text="Settings">
          <button
            className="thread-action-settings"
            aria-label="Settings"
            onClick={() => {
              const panel = document.querySelector('.chat-panel')
              const r = panel?.getBoundingClientRect()
              window.electronAPI?.openSettings(r ? { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) } : null)
            }}
          >
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
            </svg>
          </button>
        </Tooltip>
        {onClose && (chatFullSize || !croppedImage) && (
          <button className="thread-action-link thread-action-esc" onClick={onClose} aria-label="Close panel">
            <kbd className="thread-action-kbd">Esc</kbd> to close
          </button>
        )}
        <span className="thread-actions-spacer" />
        {(() => {
          const allModels = availableProviders.flatMap(p => p.models?.map(m => ({ ...m, provider: p.id, providerName: p.name })) || [])
          const currentModel = allModels.find(m => m.id === modelId) || allModels[0]
          const displayName = currentModel?.name || 'AI'
          if (allModels.length > 0) {
            return (
              <div className="model-selector" ref={modelSelectorRef}>
                <button
                  className="thread-action-link model-link"
                  aria-label="Select model"
                  aria-expanded={modelMenuOpen}
                  aria-haspopup="menu"
                  onClick={() => {
                    if (!modelMenuOpen) {
                      const r = modelSelectorRef.current?.getBoundingClientRect()
                      if (r) setModelMenuPos({ bottom: window.innerHeight - r.top + 4, right: window.innerWidth - r.right })
                    }
                    setModelMenuOpen(!modelMenuOpen)
                  }}
                >
                  {displayName}
                  <svg className={`model-chevron ${modelMenuOpen ? 'open' : ''}`} viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <path d="M6 9l6 6 6-6" />
                  </svg>
                </button>
                {modelMenuOpen && modelMenuPos && (() => {
                  return ReactDOM.createPortal(
                    <div className="model-dropdown" role="menu" aria-label="Model selection" style={{ position: 'fixed', bottom: modelMenuPos.bottom, right: modelMenuPos.right }}>
                      {availableProviders.map((p, pi) => (
                        <div key={p.id}>
                          {availableProviders.length > 1 && <div className={`model-dropdown-section ${pi > 0 ? 'model-dropdown-section-divider' : ''}`}>{p.name}</div>}
                          {p.models?.map(m => (
                            <button
                              key={m.id}
                              className={`model-dropdown-item ${m.id === modelId ? 'active' : ''}`}
                              role="menuitem"
                              aria-current={m.id === modelId ? 'true' : undefined}
                              onClick={() => {
                                setProvider(p.id)
                                setModelId(m.id)
                                setModelMenuOpen(false)
                              }}
                            >
                            {m.name}
                          </button>
                        ))}
                      </div>
                    ))}
                    </div>,
                    document.body
                  )
                })()}
              </div>
            )
          }
          return <span className="thread-action-model">{displayName}</span>
        })()}
      </div>
      </div>{/* end .chat-bottom-zone */}

      {/* Bottom frosted bar with pill — visible in view mode */}
      {isPinned && (
        <div ref={expandBtnRef} className="view-mode-bottom" style={{ display: 'none' }}>
          <button
            className="view-mode-pill"
            onClick={handleViewHintClick}
            aria-label="Show input"
          >
            Continue discussion...
          </button>
        </div>
      )}
    </div>
  )
}
