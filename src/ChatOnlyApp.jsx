import React, { useState, useEffect, useRef, useCallback } from 'react'
import ChatPanel from './ChatPanel'
import useThreadManager from './useThreadManager'
import './app.css'

export default function ChatOnlyApp() {
  const [initialContext, setInitialContext] = useState({ text: '', seq: 0 })
  const [isPinned, setIsPinned] = useState(false)
  const [isWindowBlurred, setIsWindowBlurred] = useState(false)
  const isPinnedRef = useRef(false)
  const [croppedImage, setCroppedImage] = useState(null)
  const [autoSendPending, setAutoSendPending] = useState(false)
  const skipNextScrollRef = useRef(false)
  const tm = useThreadManager()

  useEffect(() => {
    window.electronAPI?.onTextContext?.((text) => setInitialContext({ text: text?.trim() || '', seq: Date.now() }))
    window.electronAPI?.onClearTextContext?.(() => setInitialContext(prev => ({ text: '', seq: prev.seq + 1 })))
    window.electronAPI?.onPinState?.((state) => {
      setIsPinned(state)
      isPinnedRef.current = state
      if (!state) setIsWindowBlurred(false)
    })
    window.electronAPI?.onViewMode?.((entering) => {
      if (entering && isPinnedRef.current) setIsWindowBlurred(true)
    })
    window.electronAPI?.onSetCroppedImage?.((img) => setCroppedImage(img))
    window.electronAPI?.onClearScreenshot?.(() => setCroppedImage(null))
    // Swift decides thread state via decideChatState() — emits start-new-thread if needed
    window.electronAPI?.onStartNewThread?.(() => tm.handleNewThread())
    // Receive full thread data from pin (no disk read needed)
    window.electronAPI?.onLoadThreadData?.((data) => {
      if (data) {
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
    // Listen to window blur — focus does NOT reset blur state.
    // Only expand button or unpin resets it (via onExitViewMode).
    const handleBlur = () => { if (isPinnedRef.current) setIsWindowBlurred(true) }
    window.addEventListener('blur', handleBlur)
    return () => window.removeEventListener('blur', handleBlur)
  }, [])

  const handleClose = () => {
    window.electronAPI?.closeChatWindow?.()
  }

  const handleExitViewMode = useCallback(() => {
    setIsWindowBlurred(false)
    window.electronAPI?.inputFocus?.()
  }, [])

  // ESC to close — capture phase
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') {
        e.preventDefault()
        e.stopPropagation()
        handleClose()
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
      <ChatPanel
        style={{}}
        croppedImage={croppedImage}
        getCompositeImage={null}
        onDismissScreenshot={() => setCroppedImage(null)}
        currentThread={tm.currentThread}
        setCurrentThread={tm.setCurrentThread}
        recentThreads={tm.recentThreads}
        onThreadChange={tm.handleThreadChange}
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
        autoSendPending={autoSendPending}
        onAutoSendConsumed={() => setAutoSendPending(false)}
      />
      </div>
    </div>
  )
}
