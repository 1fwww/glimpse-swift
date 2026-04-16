import { useState, useCallback, useEffect, useRef } from 'react'

function newThread() {
  return { id: null, title: 'New Chat', messages: [], createdAt: Date.now(), updatedAt: Date.now() }
}

export default function useThreadManager() {
  const [currentThread, setCurrentThread] = useState(null)
  const currentThreadRef = useRef(null)
  const [recentThreads, setRecentThreads] = useState([])
  const [isNewThread, setIsNewThread] = useState(false)
  const [provider, setProviderState] = useState(() => localStorage.getItem('glimpse-provider') || 'claude')
  const [modelId, setModelIdState] = useState(() => localStorage.getItem('glimpse-model') || null)
  const [availableProviders, setAvailableProviders] = useState([])

  // Keep ref in sync for closures that can't depend on state
  useEffect(() => { currentThreadRef.current = currentThread }, [currentThread])

  const setProvider = useCallback((p) => { localStorage.setItem('glimpse-provider', p); setProviderState(p) }, [])
  const setModelId = useCallback((m) => { localStorage.setItem('glimpse-model', m); setModelIdState(m) }, [])

  // Load threads + providers on mount
  useEffect(() => {
    const load = () => {
      if (!window.electronAPI?.getThreads) {
        setTimeout(load, 100)
        return
      }
      window.electronAPI.getAvailableProviders?.().then(providers => {
        setAvailableProviders(providers || [])
        if (providers?.length > 0) {
          const allModels = providers.flatMap(p => p.models?.map(m => ({ ...m, providerId: p.id })) || [])
          const savedModel = localStorage.getItem('glimpse-model')
          const savedExists = allModels.find(m => m.id === savedModel)
          if (!savedExists) {
            setProvider(providers[0].id)
            setModelId(providers[0].models?.[0]?.id || null)
          }
        }
      })
      window.electronAPI.getThreads().then(threads => {
        setRecentThreads(threads || [])
        const mostRecent = threads?.[0]
        if (mostRecent) {
          setCurrentThread(mostRecent)
          setIsNewThread(false)
          // Notify Swift that an existing thread loaded — clears wasNewThread
          window.electronAPI?.notifyThreadLoaded?.()
        } else {
          setCurrentThread(newThread())
          setIsNewThread(true)
        }
      })
    }
    load()
  }, [])


  const handleThreadChange = useCallback((thread) => {
    setCurrentThread(thread)
    setIsNewThread(false)
    // Existing thread with messages → expanded, empty → compact
    if (thread?.messages?.length > 0) {
      window.electronAPI?.resizeChatWindow?.({ width: 380, height: 550, animate: false })
    } else {
      window.electronAPI?.resizeChatWindow?.({ width: 380, height: 412, animate: false })
    }
  }, [])

  const handleNewThread = useCallback(() => {
    setCurrentThread(newThread())
    setIsNewThread(true)
    // Notify Swift so next reopen starts compact
    window.electronAPI?.notifyNewThread?.()
  }, [])

  const handleSetCurrentThread = useCallback((thread) => {
    setCurrentThread(thread)
    window.electronAPI?.getThreads?.().then(threads => {
      setRecentThreads(threads || [])
    })
  }, [])

  const refreshThreads = useCallback(() => {
    window.electronAPI?.getThreads?.().then(threads => {
      setRecentThreads(threads || [])
    })
  }, [])

  // Load the most recent thread from disk (no stale check — Swift decides)
  const loadLatestThread = useCallback(() => {
    window.electronAPI?.getThreads?.().then(threads => {
      setRecentThreads(threads || [])
      const mostRecent = threads?.[0]
      if (mostRecent) {
        // Always update — thread may have new messages from standalone chat
        setCurrentThread(mostRecent)
        setIsNewThread(false)
      } else {
        setCurrentThread(newThread())
        setIsNewThread(true)
      }
    })
  }, [])

  const handleClearAllThreads = useCallback(async () => {
    for (const t of recentThreads) {
      await window.electronAPI?.deleteThread(t.id)
    }
    setRecentThreads([])
    setCurrentThread(newThread())
    setIsNewThread(true)
    window.electronAPI?.resizeChatWindow?.({ width: 380, height: 412, animate: false })
    window.electronAPI?.refreshTrayMenu?.()
  }, [recentThreads])

  const refreshProviders = useCallback(async () => {
    const providers = await window.electronAPI?.getAvailableProviders()
    setAvailableProviders(providers || [])
    if (providers?.length > 0) {
      const allModels = providers.flatMap(p => p.models?.map(m => ({ ...m, providerId: p.id })) || [])
      const savedModel = localStorage.getItem('glimpse-model')
      const savedExists = allModels.find(m => m.id === savedModel)
      if (!savedExists) {
        setProvider(providers[0].id)
        setModelId(providers[0].models?.[0]?.id || null)
      }
    }
  }, [])

  return {
    currentThread,
    setCurrentThread: handleSetCurrentThread,
    recentThreads,
    isNewThread,
    setIsNewThread,
    provider,
    setProvider,
    modelId,
    setModelId,
    availableProviders,
    handleThreadChange,
    handleNewThread,
    handleClearAllThreads,
    refreshThreads,
    loadLatestThread,
    refreshProviders,
  }
}
