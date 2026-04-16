import React, { useState, useEffect, useRef, useCallback } from 'react'
import ChatPanel from './ChatPanel'
import ImageBoard from './ImageBoard'
import useThreadManager from './useThreadManager'
import './app.css'

function extractChatCards(threads) {
  return threads.map(t => {
    const msgs = t.messages || []
    let preview = ''
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role === 'assistant') {
        const text = (msgs[i].content || []).filter(c => c.type === 'text').map(c => c.text || '').join(' ')
        preview = text.length > 120 ? text.slice(0, 120) + '…' : text
        break
      }
    }
    let imageCount = 0
    for (const m of msgs) {
      for (const c of (m.content || [])) {
        if (c.type === 'image') imageCount++
      }
    }
    return { id: t.id, title: t.title, updatedAt: t.updatedAt, createdAt: t.createdAt, messageCount: msgs.length, imageCount, preview, _thread: t }
  })
}

export default function ChatOnlyApp() {
  const [initialContext, setInitialContext] = useState({ text: '', seq: 0 })
  const [isPinned, setIsPinned] = useState(false)
  const [isWindowBlurred, setIsWindowBlurred] = useState(false)
  const isPinnedRef = useRef(false)
  const [croppedImage, setCroppedImage] = useState(null)
  const [autoSendPending, setAutoSendPending] = useState(false)
  const skipNextScrollRef = useRef(false)
  // Board view state
  const [viewMode, setViewMode] = useState('chat') // 'chat' | 'board' | 'viewer'
  const [boardImages, setBoardImages] = useState([])
  const [boardThreads, setBoardThreads] = useState([])
  const [boardTab, setBoardTab] = useState('chats')
  const [viewerImageIndex, setViewerImageIndex] = useState(0)
  const [highlightImagePath, setHighlightImagePath] = useState(null)
  const chatSizeBeforeBoard = useRef(null)
  const viewModeRef = useRef('chat')
  const tm = useThreadManager()

  useEffect(() => {
    window.electronAPI?.onTextContext?.((text) => setInitialContext({ text: text?.trim() || '', seq: Date.now() }))
    window.electronAPI?.onClearTextContext?.(() => setInitialContext(prev => ({ text: '', seq: prev.seq + 1 })))
    window.electronAPI?.onPinState?.((state) => {
      setIsPinned(state)
      isPinnedRef.current = state
      if (!state) setIsWindowBlurred(false)
      // pin-state fires on every showChat() — reset board view so we don't reopen into it
      if (viewModeRef.current !== 'chat') {
        setViewMode('chat')
        viewModeRef.current = 'chat'
      }
    })
    window.electronAPI?.onViewMode?.((entering) => {
      if (entering && isPinnedRef.current) setIsWindowBlurred(true)
    })
    window.electronAPI?.onSetCroppedImage?.((img) => setCroppedImage(img))
    window.electronAPI?.onClearScreenshot?.(() => {
      setCroppedImage(null)
      // Reset to chat view when window is hidden (hideChat emits clear-screenshot).
      // If on board/viewer, snap back to chat so next open doesn't land on board.
      if (viewModeRef.current !== 'chat') {
        setViewMode('chat')
        viewModeRef.current = 'chat'
        const h = chatSizeBeforeBoard.current || window.innerHeight
        window.electronAPI?.resizeChatWindow?.({ width: 380, height: h, force: true, anchorX: 'center' })
      }
    })
    // Swift decides thread state via decideChatState() — emits start-new-thread if needed
    window.electronAPI?.onStartNewThread?.(() => tm.handleNewThread())
    // Receive full thread data from pin (no disk read needed)
    window.electronAPI?.onLoadThreadData?.((data) => {
      if (data) {
        // Always reset to chat view — pin/thread-load should never land on board
        if (viewModeRef.current !== 'chat') {
          setViewMode('chat')
          viewModeRef.current = 'chat'
        }
        // Pin sends { thread, croppedImage, scrollTop }, open-thread sends thread directly
        // Use setCurrentThread (not handleThreadChange) to avoid resizeChatWindow —
        // in chat-only mode the panel fills the window, Swift controls the size.
        const thread = data.thread || data
        // Preserve scroll position from overlay chat
        if (data.scrollTop != null) {
          skipNextScrollRef.current = data.scrollTop
        }
        tm.setCurrentThread(thread)
        if (thread?.messages?.length > 0) tm.setIsNewThread(false)
        if (data.croppedImage) setCroppedImage(data.croppedImage)

        // Direct scroll restore for same-thread pin-out (thread ID unchanged = effect won't fire)
        if (data.scrollTop != null) {
          setTimeout(() => {
            const el = document.querySelector('.chat-messages')
            if (el) {
              const wrapper = el.closest('.chat-messages-wrapper')
              if (wrapper) wrapper.style.transition = 'none'
              el.scrollTop = data.scrollTop
              requestAnimationFrame(() => {
                el.scrollTop = data.scrollTop
                requestAnimationFrame(() => {
                  if (wrapper) wrapper.style.transition = ''
                })
              })
            }
          }, 150)
        }
      }
    })
    window.electronAPI?.onAutoSend?.(() => { setAutoSendPending(true) })
    // Listen for "View in board" from native image viewer
    const handleOpenBoardToImage = async (e) => {
      const imagePath = e.detail
      const [images, threads] = await Promise.all([
        window.electronAPI?.getAllImages?.() || [],
        window.electronAPI?.getThreads?.() || [],
      ])
      setBoardImages(images)
      setBoardThreads(extractChatCards(threads))
      chatSizeBeforeBoard.current = window.innerHeight
      setHighlightImagePath(imagePath)
      setBoardTab('images')
      setViewMode('board')
      viewModeRef.current = 'board'
      window.electronAPI?.resizeChatWindow?.({ width: 560, height: window.innerHeight, force: true, anchorX: 'center' })
    }
    window.addEventListener('glimpse:open-board-to-image', handleOpenBoardToImage)
    // Listen to window blur — focus does NOT reset blur state.
    // Only expand button or unpin resets it (via onExitViewMode).
    const handleBlur = () => { if (isPinnedRef.current) setIsWindowBlurred(true) }
    window.addEventListener('blur', handleBlur)
    return () => window.removeEventListener('blur', handleBlur)
  }, [])

  const handleToggleBoard = useCallback(async () => {
    if (viewModeRef.current === 'chat') {
      const [images, threads] = await Promise.all([
        window.electronAPI?.getAllImages?.() || [],
        window.electronAPI?.getThreads?.() || [],
      ])
      setBoardImages(images)
      setBoardThreads(extractChatCards(threads))
      chatSizeBeforeBoard.current = window.innerHeight
      // Swap view + resize simultaneously — board renders at 380px and reflows as window widens
      setViewMode('board')
      viewModeRef.current = 'board'
      window.electronAPI?.resizeChatWindow?.({ width: 560, height: window.innerHeight, force: true, anchorX: 'center' })
    } else {
      // Swap view + resize simultaneously — chat reflows as window narrows
      setViewMode('chat')
      viewModeRef.current = 'chat'
      setBoardTab('chats')
      const h = chatSizeBeforeBoard.current || window.innerHeight
      window.electronAPI?.resizeChatWindow?.({ width: 380, height: h, force: true, anchorX: 'center' })
    }
  }, [])

  const handleViewImage = useCallback((index) => {
    setViewerImageIndex(index)
    setViewMode('viewer')
    viewModeRef.current = 'viewer'
  }, [])

  const handleChatCardClick = useCallback((chatCard) => {
    setViewMode('chat')
    viewModeRef.current = 'chat'
    const h = chatSizeBeforeBoard.current || window.innerHeight
    window.electronAPI?.resizeChatWindow?.({ width: 380, height: h, force: true, anchorX: 'center' })
    tm.handleThreadChange(chatCard._thread)
    setTimeout(() => {
      const el = document.querySelector('.chat-messages')
      if (el) el.scrollTop = el.scrollHeight
    }, 200)
  }, [tm])

  const handleViewAllChats = useCallback(async () => {
    const [images, threads] = await Promise.all([
      window.electronAPI?.getAllImages?.() || [],
      window.electronAPI?.getThreads?.() || [],
    ])
    setBoardImages(images)
    setBoardThreads(extractChatCards(threads))
    setBoardTab('chats')
    chatSizeBeforeBoard.current = window.innerHeight
    setViewMode('board')
    viewModeRef.current = 'board'
    window.electronAPI?.resizeChatWindow?.({ width: 560, height: window.innerHeight, force: true, anchorX: 'center' })
  }, [])

  // Standalone thread switch: expand when switching to thread with messages
  const handleStandaloneThreadChange = useCallback((thread) => {
    tm.handleThreadChange(thread)
    if (thread?.messages?.length > 0) {
      window.electronAPI?.resizeChatWindow?.({ width: 380, height: 550 })
    }
  }, [tm])

  const handleBackToBoard = useCallback(() => {
    setViewMode('board')
    viewModeRef.current = 'board'
  }, [])

  const scrollToMessage = useCallback((msgIndex) => {
    let attempts = 0
    const tryScroll = () => {
      const container = document.querySelector('.chat-messages')
      const target = container?.querySelector(`[data-msg-index="${msgIndex}"]`)
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'center' })
        target.classList.remove('msg-highlight') // reset if re-triggered
        void target.offsetWidth // force reflow for re-animation
        target.classList.add('msg-highlight')
      } else if (attempts < 30) {
        attempts++
        setTimeout(tryScroll, 100)
      }
    }
    // Initial delay for React mount + thread load
    setTimeout(tryScroll, 300)
  }, [])

  const handleFindInChat = useCallback((threadId, messageIndex) => {
    setViewMode('chat')
    viewModeRef.current = 'chat'
    const h = chatSizeBeforeBoard.current || window.innerHeight
    window.electronAPI?.resizeChatWindow?.({ width: 380, height: h, force: true, anchorX: 'center' })
    const thread = tm.recentThreads.find(t => t.id === threadId)
    if (thread) tm.handleThreadChange(thread)
    scrollToMessage(messageIndex)
  }, [tm, scrollToMessage])

  const handleQuoteInNewChat = useCallback(() => {
    setViewMode('chat')
    viewModeRef.current = 'chat'
    const h = chatSizeBeforeBoard.current || window.innerHeight
    window.electronAPI?.resizeChatWindow?.({ width: 380, height: h, force: true, anchorX: 'center' })
  }, [])

  const handleClose = () => {
    // Reset view mode so next open starts as chat
    setViewMode('chat')
    viewModeRef.current = 'chat'
    window.electronAPI?.closeChatWindow?.()
  }

  const handleExitViewMode = useCallback(() => {
    setIsWindowBlurred(false)
    window.electronAPI?.inputFocus?.()
  }, [])

  // ESC navigation: viewer→board→chat→close
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') {
        e.preventDefault()
        e.stopPropagation()
        if (viewModeRef.current === 'viewer') {
          handleBackToBoard()
        } else if (viewModeRef.current === 'board') {
          handleToggleBoard()
        } else {
          handleClose()
        }
      }
    }
    window.addEventListener('keydown', handleKeyDown, true)
    return () => window.removeEventListener('keydown', handleKeyDown, true)
  }, [])

  // Signal main process that React has rendered
  useEffect(() => {
    window.electronAPI?.chatReady?.()
  }, [])

  if (!tm.currentThread) return null

  return (
    <div className="chat-only-app">
      <div className={`chat-only-inner ${isPinned ? 'pinned' : ''}`}>
      {viewMode === 'chat' ? (
        <ChatPanel
          style={{}}
          croppedImage={croppedImage}
          getCompositeImage={null}
          onDismissScreenshot={() => setCroppedImage(null)}
          currentThread={tm.currentThread}
          setCurrentThread={tm.setCurrentThread}
          recentThreads={tm.recentThreads}
          onThreadChange={handleStandaloneThreadChange}
          onNewThread={tm.handleNewThread}
          onClearAllThreads={tm.handleClearAllThreads}
          chatFullSize={true}
          setChatFullSize={() => {}}
          isNewThread={tm.isNewThread}
          setIsNewThread={tm.setIsNewThread}
          refreshThreads={tm.refreshThreads}
          refreshProviders={tm.refreshProviders}
          onClose={handleClose}
          onMinimize={handleClose}
          provider={tm.provider}
          setProvider={tm.setProvider}
          modelId={tm.modelId}
          setModelId={tm.setModelId}
          availableProviders={tm.availableProviders}
          annotationCount={0}
          initialContext={initialContext}
          isPinned={isPinned}
          isWindowBlurred={isWindowBlurred}
          onExitViewMode={handleExitViewMode}
          skipNextScrollRef={skipNextScrollRef}
          onTogglePin={() => window.electronAPI?.togglePin?.()}
          onToggleBoard={handleToggleBoard}
          onViewAllChats={handleViewAllChats}
          boardActive={false}
          autoSendPending={autoSendPending}
          onAutoSendConsumed={() => setAutoSendPending(false)}
        />
      ) : (
        <ImageBoard
          images={boardImages}
          boardThreads={boardThreads}
          boardTab={boardTab}
          onBoardTabChange={setBoardTab}
          onChatCardClick={handleChatCardClick}
          viewMode={viewMode}
          viewerImageIndex={viewerImageIndex}
          highlightImagePath={highlightImagePath}
          onHighlightConsumed={() => setHighlightImagePath(null)}
          onImageClick={handleViewImage}
          onBack={viewMode === 'viewer' ? handleBackToBoard : handleToggleBoard}
          onClose={handleClose}
          onFindInChat={handleFindInChat}
          onQuoteInNewChat={handleQuoteInNewChat}
          onToggleBoard={handleToggleBoard}
        />
      )}
      </div>
    </div>
  )
}
