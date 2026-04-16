import React, { useState, useEffect, useRef, useCallback } from 'react'
import ChatPanel from './ChatPanel'
import EditToolbar from './EditToolbar'
import DrawingCanvas from './DrawingCanvas'
import useThreadManager from './useThreadManager'
import './app.css'

export default function App() {
  const [screenImage, setScreenImage] = useState(null)
  const screenImageRef = useRef(null)
  const [selection, setSelection] = useState(null)
  const [isSelecting, setIsSelecting] = useState(false)
  const [startPos, setStartPos] = useState(null)
  const [chatVisible, setChatVisible] = useState(false)
  const [croppedImage, setCroppedImage] = useState(null)
  const [windowBounds, setWindowBounds] = useState([])
  const [hoveredWindow, setHoveredWindow] = useState(null)
  const [displayInfo, setDisplayInfo] = useState(null)
  const displayInfoRef = useRef(null)
  const [windowOffset, setWindowOffset] = useState({ x: 0, y: 0 })
  const windowOffsetRef = useRef({ x: 0, y: 0 })

  // Shared thread/provider state
  const tm = useThreadManager()

  const [chatFullSize, setChatFullSize] = useState(false)
  const [isExiting, setIsExiting] = useState(false)
  const [chatMinimized, setChatMinimized] = useState(false)
  const userMinimizedRef = useRef(localStorage.getItem('chat-minimized') === 'true')
  const chatWasOpenRef = useRef(false)
  const compactRef = useRef(true)  // persists compact flag from decideChatState across handlers
  const [activeTool, setActiveTool] = useState(null)
  const [activeColor, setActiveColor] = useState('#e5243a')
  const [activeSize, setActiveSize] = useState(4)
  const [annotations, setAnnotations] = useState([])
  const [undoStack, setUndoStack] = useState([])
  const [selectedAnnotation, setSelectedAnnotation] = useState(null)
  const [mosaicMode, setMosaicMode] = useState('brush')
  const [arrowStyle, setArrowStyle] = useState('arrow')

  // Wrap setAnnotations to track undo/redo
  const updateAnnotations = useCallback((updater) => {
    setAnnotations(prev => {
      const next = typeof updater === 'function' ? updater(prev) : updater
      setUndoStack(stack => [...stack, prev])
      return next
    })
  }, [])

  const undo = useCallback(() => {
    setUndoStack(stack => {
      if (stack.length === 0) return stack
      const prev = stack[stack.length - 1]
      setAnnotations(prev)
      setSelectedAnnotation(null)
      return stack.slice(0, -1)
    })
  }, [])

  const clearAll = useCallback(() => {
    if (annotations.length === 0) return
    setUndoStack(stack => [...stack, annotations])
    setAnnotations([])
    setSelectedAnnotation(null)
  }, [annotations])

  const overlayRef = useRef(null)

  useEffect(() => {
    if (!window.electronAPI) return

    const resetState = () => {
      setScreenImage(null)
      setSelection(null)
      setChatVisible(false)
      setChatFullSize(false)
      setIsSelecting(false)
      setHoveredWindow(null)
      setFrozenChatPos(null)
      setCopyFeedback(false)
      setSaveFeedback(false)
      setIsExiting(false)
      setAnnotations([])
      setUndoStack([])
      setActiveTool(null)
    }

    // Reset screenshot/UI state but keep chat thread (messages, chatVisible, chatFullSize)
    const resetStateKeepThread = () => {
      setScreenImage(null)
      setSelection(null)
      setIsSelecting(false)
      setHoveredWindow(null)
      setFrozenChatPos(null)
      setCopyFeedback(false)
      setSaveFeedback(false)
      setIsExiting(false)
      setAnnotations([])
      setUndoStack([])
      setActiveTool(null)
    }

    const removeScreenCaptured = window.electronAPI.onScreenCaptured((dataUrl, bounds, dispInfo, offset, preSelection, startNewThread, compact) => {
      // Swift decides thread state — JS just executes
      if (startNewThread) {
        resetState()
        tm.handleNewThread()
      } else {
        resetStateKeepThread()
        // Reload latest thread from disk — may have been updated by standalone chat
        tm.loadLatestThread()
      }
      setScreenImage(dataUrl)
      screenImageRef.current = dataUrl
      tm.refreshProviders()
      setDisplayInfo(dispInfo || null)
      displayInfoRef.current = dispInfo || null
      setWindowOffset(offset || { x: 0, y: 0 })
      windowOffsetRef.current = offset || { x: 0, y: 0 }
      const off = offset || { x: 0, y: 0 }
      setWindowBounds((bounds || []).map(win => ({
        ...win,
        x: win.x - off.x,
        y: win.y - off.y,
      })))
      // Persist compact flag for mouseUp/applySelection handlers
      compactRef.current = compact
      // Apply pre-computed selection from native overlay (if present)
      if (preSelection && preSelection.w > 10 && preSelection.h > 10) {
        setSelection(preSelection)
        setIsSelecting(false)
        setChatVisible(true)
        if (compact) {
          // New thread — compact
          setChatMinimized(true)
          setChatFullSize(false)
        } else {
          // Continuing existing conversation — expanded, preserve minimize state
          setChatMinimized(userMinimizedRef.current)
          setChatFullSize(true)
        }
        setTimeout(() => cropSelection(preSelection, dataUrl, dispInfo, offset), 50)
      }
      // Signal Swift after React renders + image decodes.
      setTimeout(() => {
        const img = new Image()
        img.onload = () => window.electronAPI?.overlayRendered?.()
        img.onerror = () => window.electronAPI?.overlayRendered?.()
        img.src = dataUrl
      }, 50)
      window.focus()
    })

    const removeNewCapture = window.electronAPI.onNewCapture((dataUrl, dispInfo) => {
      resetState()
      setScreenImage(dataUrl)
      setDisplayInfo(dispInfo || null)
    })

    const removeReset = window.electronAPI.onResetOverlay?.(() => {
      resetState()
      if (document.visibilityState === 'visible') {
        window.__TAURI_INTERNALS__?.invoke('overlay_pong').catch(() => {})
      }
    })

    const removeResetKeepThread = window.electronAPI.onResetOverlayKeepThread?.(() => {
      resetStateKeepThread()
    })

    // Native selection handoff: selection rect pre-computed by Swift CAShapeLayer overlay.
    // Fires after screen-captured, so screenImage is already set.
    const removeApplySelection = window.electronAPI.onApplySelection?.((sel) => {
      if (sel && sel.w > 10 && sel.h > 10) {
        setSelection(sel)
        setIsSelecting(false)
        // Crop + show chat — same as mouseUp with valid selection
        setTimeout(() => {
          cropSelection(sel, screenImageRef.current, displayInfoRef.current, windowOffsetRef.current)
          setChatVisible(true)
          setChatFullSize(!compactRef.current)
        }, 50)
      }
    })

    return () => {
      removeScreenCaptured?.()
      removeNewCapture?.()
      removeReset?.()
      removeResetKeepThread?.()
      removeApplySelection?.()
    }
  }, [])

  const closeWithAnimation = useCallback(() => {
    if (isExiting) return
    setIsExiting(true)
    setTimeout(() => {
      window.electronAPI?.closeOverlay()
    }, 200)
  }, [isExiting])

  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') {
        closeWithAnimation()
      }
      // Cmd+Z / Ctrl+Z = undo, Cmd+Shift+Z / Ctrl+Shift+Z = redo
      if ((e.metaKey || e.ctrlKey) && e.key === 'z' && !e.shiftKey) {
        e.preventDefault()
        undo()
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [closeWithAnimation, undo])

  // Compose screenshot + annotations (compressed for AI chat)
  const getCompositeImage = useCallback(async (imgOverride) => {
    const img = imgOverride || croppedImage
    if (!img) return null
    try {
      // Convert data URL to blob for createImageBitmap (reliable decode)
      const resp = await fetch(img)
      const blob = await resp.blob()
      const bmp = await createImageBitmap(blob)

      const canvas = document.createElement('canvas')
      canvas.width = bmp.width
      canvas.height = bmp.height
      const ctx = canvas.getContext('2d')
      ctx.drawImage(bmp, 0, 0)
      bmp.close()

      const drawingCanvas = document.querySelector('.drawing-canvas')
      if (drawingCanvas) {
        ctx.drawImage(drawingCanvas, 0, 0, canvas.width, canvas.height)
      }

      const result = canvas.toDataURL('image/png')
      return result
    } catch(e) {
      return null
    }
  }, [croppedImage])

  // High-res composite for save/copy (full resolution from original screenshot)
  const getHiResComposite = useCallback(() => {
    return new Promise((resolve) => {
      if (!screenImage || !selection) return resolve(null)
      const img = new Image()
      img.onload = async () => {
        try { await img.decode() } catch(e) {}
        const displayW = displayInfo?.width || window.innerWidth
        const displayH = displayInfo?.height || window.innerHeight
        const scaleX = img.naturalWidth / displayW
        const scaleY = img.naturalHeight / displayH

        const sx = (selection.x + windowOffset.x) * scaleX
        const sy = (selection.y + windowOffset.y) * scaleY
        const sw = selection.w * scaleX
        const sh = selection.h * scaleY

        const canvas = document.createElement('canvas')
        canvas.width = sw
        canvas.height = sh
        const ctx = canvas.getContext('2d')
        ctx.drawImage(img, sx, sy, sw, sh, 0, 0, sw, sh)

        // Draw annotations scaled to full resolution
        const drawingCanvas = document.querySelector('.drawing-canvas')
        if (drawingCanvas) {
          ctx.drawImage(drawingCanvas, 0, 0, sw, sh)
        }

        resolve(canvas.toDataURL('image/png'))
      }
      img.src = screenImage
    })
  }, [screenImage, selection, displayInfo, windowOffset])

  const [copyFeedback, setCopyFeedback] = useState(false)

  const handleCopy = useCallback(async () => {
    setSelectedAnnotation(null)
    // Wait one frame for React to clear selection handles before compositing
    await new Promise(r => requestAnimationFrame(r))
    const img = await getHiResComposite()
    if (img) {
      await window.electronAPI?.copyImage(img)
      setCopyFeedback(true)
      // Exit and show toast
      window.electronAPI?.closeOverlay()
      window.electronAPI?.showToast('Copied to clipboard')
    }
  }, [getHiResComposite])

  const [saveFeedback, setSaveFeedback] = useState(false)

  const handleSave = useCallback(async () => {
    setSelectedAnnotation(null)
    await new Promise(r => requestAnimationFrame(r))
    const img = await getHiResComposite()
    if (img) {
      const result = await window.electronAPI?.saveImage(img)
      if (result?.success) {
        setSaveFeedback(true)
        const folder = result.filePath?.split('/').slice(-2, -1)[0]
        window.electronAPI?.closeOverlay()
        window.electronAPI?.showToast(folder ? `Saved to ${folder}` : 'Saved')
      }
    }
  }, [getHiResComposite])

  const cropSelection = useCallback(async (sel, imgDataUrl, dispInfo, offset) => {
    if (!sel || !imgDataUrl) {
      return
    }

    try {
      // Use fetch + createImageBitmap for reliable pixel decode.
      // WKWebView's Image element can fire onload before file:// pixel data
      // is fully decoded, causing drawImage to read black pixels.
      const resp = await fetch(imgDataUrl)
      const blob = await resp.blob()
      const bmp = await createImageBitmap(blob)

      const displayW = dispInfo?.width || window.innerWidth
      const displayH = dispInfo?.height || window.innerHeight
      const off = offset || { x: 0, y: 0 }
      const scaleX = bmp.width / displayW
      const scaleY = bmp.height / displayH

      const canvas = document.createElement('canvas')
      const sx = (sel.x + off.x) * scaleX
      const sy = (sel.y + off.y) * scaleY
      const sw = sel.w * scaleX
      const sh = sel.h * scaleY

      // Resize if too large (keep under ~4MB for API limit)
      const MAX_DIM = 1200
      let outW = sw
      let outH = sh
      if (outW > MAX_DIM || outH > MAX_DIM) {
        const ratio = Math.min(MAX_DIM / outW, MAX_DIM / outH)
        outW = Math.round(outW * ratio)
        outH = Math.round(outH * ratio)
      }

      canvas.width = outW
      canvas.height = outH
      const ctx = canvas.getContext('2d')
      ctx.drawImage(bmp, sx, sy, sw, sh, 0, 0, outW, outH)
      bmp.close()
      setCroppedImage(canvas.toDataURL('image/jpeg', 0.85))
    } catch(e) {
    }
  }, [])

  const findWindowAtPoint = useCallback((x, y) => {
    for (const win of windowBounds) {
      if (x >= win.x && x <= win.x + win.w && y >= win.y && y <= win.y + win.h) {
        return win
      }
    }
    return null
  }, [windowBounds])

  const [isMovingSelection, setIsMovingSelection] = useState(false)
  const [isResizingSelection, setIsResizingSelection] = useState(false)
  const moveStart = useRef(null)
  const resizeEdge = useRef(null)

  const getSelectionEdge = (e) => {
    if (!selection) return null
    const margin = 6
    const { x, y, w, h } = selection
    const cx = e.clientX, cy = e.clientY
    const onLeft = Math.abs(cx - x) < margin
    const onRight = Math.abs(cx - (x + w)) < margin
    const onTop = Math.abs(cy - y) < margin
    const onBottom = Math.abs(cy - (y + h)) < margin
    const inX = cx >= x - margin && cx <= x + w + margin
    const inY = cy >= y - margin && cy <= y + h + margin

    if (onTop && onLeft && inX && inY) return 'nw'
    if (onTop && onRight && inX && inY) return 'ne'
    if (onBottom && onLeft && inX && inY) return 'sw'
    if (onBottom && onRight && inX && inY) return 'se'
    if (onTop && inX) return 'n'
    if (onBottom && inX) return 's'
    if (onLeft && inY) return 'w'
    if (onRight && inY) return 'e'
    return null
  }

  const getEdgeCursor = (edge) => {
    const map = { nw: 'nwse-resize', se: 'nwse-resize', ne: 'nesw-resize', sw: 'nesw-resize', n: 'ns-resize', s: 'ns-resize', w: 'ew-resize', e: 'ew-resize' }
    return map[edge] || 'default'
  }

  const handleMouseDown = (e) => {
    if (e.target.closest('.chat-panel')) return
    if (e.target.closest('.edit-toolbar')) return
    if (e.target.closest('.drawing-canvas')) return
    if (e.target.closest('.model-dropdown')) return
    if (e.target.closest('.thread-menu-popup')) return

    // Check resize edges first
    if (selection && !activeTool && annotations.length === 0) {
      const edge = getSelectionEdge(e)
      if (edge) {
        setIsResizingSelection(true)
        resizeEdge.current = edge
        moveStart.current = { x: e.clientX, y: e.clientY, sel: { ...selection } }
        return
      }
    }

    // If clicking inside existing selection, start moving it
    if (selection && e.clientX >= selection.x && e.clientX <= selection.x + selection.w
        && e.clientY >= selection.y && e.clientY <= selection.y + selection.h) {
      setIsMovingSelection(true)
      moveStart.current = { x: e.clientX, y: e.clientY, sel: { ...selection } }
      return
    }

    // Remember if chat was open before re-selecting
    chatWasOpenRef.current = chatVisible && !chatMinimized
    setFrozenChatPos(null)

    // Start tracking — will distinguish click vs drag on mouseUp
    setIsSelecting(true)
    setStartPos({ x: e.clientX, y: e.clientY })
    setSelection(null)
    setChatVisible(false)
    if (!chatWasOpenRef.current) setChatFullSize(false)
    setAnnotations([])
    setUndoStack([])
    setActiveTool(null)
    setSelectedAnnotation(null)
  }

  const rafRef = useRef(null)
  const selectionRef = useRef(null) // current selection during drag (avoids setState)
  const maskRectRef = useRef(null)
  const borderRef = useRef(null)
  const dimsRef = useRef(null)

  const updateSelectionDOM = (sel) => {
    // Update DOM directly without React re-render
    if (maskRectRef.current) {
      maskRectRef.current.setAttribute('x', sel.x)
      maskRectRef.current.setAttribute('y', sel.y)
      maskRectRef.current.setAttribute('width', sel.w)
      maskRectRef.current.setAttribute('height', sel.h)
    }
    if (borderRef.current) {
      borderRef.current.style.left = sel.x + 'px'
      borderRef.current.style.top = sel.y + 'px'
      borderRef.current.style.width = sel.w + 'px'
      borderRef.current.style.height = sel.h + 'px'
      borderRef.current.style.display = sel.w > 10 && sel.h > 10 ? 'block' : 'none'
    }
    if (dimsRef.current) {
      dimsRef.current.textContent = `${Math.round(sel.w)} × ${Math.round(sel.h)}`
    }
  }

  const handleMouseMove = (e) => {
    // During active drag operations (resize, move, new selection), process every
    // mousemove immediately — direct DOM updates are cheap and skipping events
    // causes visible lag (rectangle trails cursor). Browser batches to vsync anyway.
    const isDragging = isResizingSelection || isMovingSelection || (isSelecting && startPos)
    if (!isDragging) {
      // rAF throttle for non-drag operations (hover detection, cursor updates)
      if (rafRef.current) return
      rafRef.current = requestAnimationFrame(() => { rafRef.current = null })
    }

    // Resizing existing selection
    if (isResizingSelection && moveStart.current) {
      const dx = e.clientX - moveStart.current.x
      const dy = e.clientY - moveStart.current.y
      const s = moveStart.current.sel
      const edge = resizeEdge.current
      let { x, y, w, h } = s

      const moveTop = edge === 'n' || edge === 'nw' || edge === 'ne'
      const moveBottom = edge === 's' || edge === 'sw' || edge === 'se'
      const moveLeft = edge === 'w' || edge === 'nw' || edge === 'sw'
      const moveRight = edge === 'e' || edge === 'ne' || edge === 'se'

      if (moveTop) { y = s.y + dy; h = s.h - dy }
      if (moveBottom) { h = s.h + dy }
      if (moveLeft) { x = s.x + dx; w = s.w - dx }
      if (moveRight) { w = s.w + dx }

      if (w < 20) { w = 20; if (moveLeft) x = s.x + s.w - 20 }
      if (h < 20) { h = 20; if (moveTop) y = s.y + s.h - 20 }

      const sel = { x, y, w, h }
      selectionRef.current = sel
      updateSelectionDOM(sel)
      return
    }

    // Moving existing selection
    if (isMovingSelection && moveStart.current) {
      const dx = e.clientX - moveStart.current.x
      const dy = e.clientY - moveStart.current.y
      const s = moveStart.current.sel
      const sel = {
        x: Math.max(0, Math.min(s.x + dx, window.innerWidth - s.w)),
        y: Math.max(0, Math.min(s.y + dy, window.innerHeight - s.h)),
        w: s.w,
        h: s.h,
      }
      selectionRef.current = sel
      updateSelectionDOM(sel)
      return
    }

    // Update cursor when hovering near selection edges
    if (selection && !activeTool && annotations.length === 0 && !isSelecting) {
      const edge = getSelectionEdge(e)
      if (edge) {
        document.body.style.cursor = getEdgeCursor(edge)
        return
      } else if (e.clientX >= selection.x && e.clientX <= selection.x + selection.w
          && e.clientY >= selection.y && e.clientY <= selection.y + selection.h) {
        document.body.style.cursor = 'move'
        return
      } else {
        document.body.style.cursor = ''
      }
    }

    if (isSelecting && startPos) {
      const dx = Math.abs(e.clientX - startPos.x)
      const dy = Math.abs(e.clientY - startPos.y)

      if (dx > 5 || dy > 5) {
        if (hoveredWindow) setHoveredWindow(null)
        const x = Math.min(startPos.x, e.clientX)
        const y = Math.min(startPos.y, e.clientY)
        const sel = { x, y, w: dx, h: dy }
        selectionRef.current = sel
        // Direct DOM update — no React re-render during drag
        updateSelectionDOM(sel)
        // Only setState once to make mask visible (first time)
        if (!selection) setSelection(sel)
      }
      return
    }

    if (!selection && !chatVisible) {
      const win = findWindowAtPoint(e.clientX, e.clientY)
      setHoveredWindow(win)
    }
  }

  const handleMouseUp = (e) => {
    if (e.target.closest('.edit-toolbar')) return
    if (e.target.closest('.chat-panel')) return

    // Finish resizing selection
    if (isResizingSelection) {
      setIsResizingSelection(false)
      resizeEdge.current = null
      moveStart.current = null
      document.body.style.cursor = ''
      const finalSel = selectionRef.current || selection
      if (selectionRef.current) {
        setSelection(selectionRef.current)
        selectionRef.current = null
      }
      if (finalSel) cropSelection(finalSel, screenImageRef.current, displayInfoRef.current, windowOffsetRef.current)
      return
    }

    // Finish moving selection
    if (isMovingSelection) {
      setIsMovingSelection(false)
      moveStart.current = null
      document.body.style.cursor = ''
      const finalSel = selectionRef.current || selection
      if (selectionRef.current) {
        setSelection(selectionRef.current)
        selectionRef.current = null
      }
      if (finalSel) cropSelection(finalSel, screenImageRef.current, displayInfoRef.current, windowOffsetRef.current)
      return
    }

    if (!isSelecting) return
    setIsSelecting(false)
    setStartPos(null)

    // Commit ref to state (final position after drag)
    const finalSel = selectionRef.current || selection
    if (selectionRef.current) {
      setSelection(selectionRef.current)
      selectionRef.current = null
    }

    // Dragged a selection
    if (finalSel && finalSel.w > 10 && finalSel.h > 10) {
      setHoveredWindow(null)
      setChatVisible(true)
      setChatFullSize(!compactRef.current)
      setChatMinimized(chatWasOpenRef.current ? false : (userMinimizedRef.current || tm.isNewThread))
      cropSelection(finalSel, screenImageRef.current, displayInfoRef.current, windowOffsetRef.current)
      return
    }

    // It was a click (no drag)
    setSelection(null)
    const win = findWindowAtPoint(e.clientX, e.clientY)
    if (win) {
      const sel = { x: win.x, y: win.y, w: win.w, h: win.h }
      setSelection(sel)
      setHoveredWindow(null)
      setChatVisible(true)
      setChatFullSize(!compactRef.current)
      setChatMinimized(chatWasOpenRef.current ? false : (userMinimizedRef.current || tm.isNewThread))
      cropSelection(sel, screenImageRef.current, displayInfoRef.current, windowOffsetRef.current)
    } else {
      closeWithAnimation()
    }
  }



  const handleMinimizeChat = () => {
    setChatMinimized(true)
    userMinimizedRef.current = true
    localStorage.setItem('chat-minimized', 'true')
  }

  const handleRestoreChat = () => {
    setChatMinimized(false)
    userMinimizedRef.current = false
    localStorage.setItem('chat-minimized', 'false')
  }

  const [frozenChatPos, setFrozenChatPos] = useState(null)

  // Pin out from overlay → standalone chat (reused by dismiss, send, and pin button)
  const pinOutFromOverlay = useCallback((opts = {}) => {
    const { includeCroppedImage = false, pinned = true, threadOverride = null, pendingSend = false } = opts
    const panel = document.querySelector('.chat-panel')
    const r = panel?.getBoundingClientRect()
    const bounds = r ? { x: r.left, y: r.top, width: r.width, height: r.height } : null
    const messagesEl = panel?.querySelector('.chat-messages')
    const scrollTop = messagesEl?.scrollTop ?? null
    window.electronAPI?.pinChat({
      thread: threadOverride || tm.currentThread,
      croppedImage: includeCroppedImage ? croppedImage : null,
      pinned,
      pendingSend,
      scrollTop,
    }, bounds)
  }, [tm.currentThread, croppedImage])

  const handleDismissScreenshot = () => {
    pinOutFromOverlay({ pinned: false })
  }

  const getChatPosition = () => {
    const panelWidth = 380
    const gap = 16
    const margin = 12
    const screenW = window.innerWidth
    const screenH = window.innerHeight
    const compactHeight = 320
    const expandedMax = 550

    if (!selection) return { left: 0, bottom: margin, top: undefined, maxHeight: chatFullSize ? expandedMax : compactHeight }

    const selTop = selection.y
    const selBottom = selection.y + selection.h
    const selMidY = selTop + selection.h / 2

    let pos = {}

    if (selMidY > screenH * 0.4) {
      const bottom = Math.max(margin, screenH - selBottom)
      const availHeight = screenH - bottom - margin
      const maxHeight = chatFullSize ? Math.min(expandedMax, availHeight) : Math.min(compactHeight, availHeight)
      pos = { bottom, top: undefined, maxHeight }
    } else {
      const top = Math.max(margin, selTop)
      const availHeight = screenH - top - margin
      const maxHeight = chatFullSize ? Math.min(expandedMax, availHeight) : Math.min(compactHeight, availHeight)
      pos = { top, bottom: undefined, maxHeight }
    }

    const rightSpace = screenW - (selection.x + selection.w)
    if (rightSpace >= panelWidth + gap) {
      return { left: selection.x + selection.w + gap, ...pos }
    }

    return { left: Math.max(margin, selection.x - panelWidth - gap), ...pos }
  }

  if (!screenImage) {
    return null // Invisible until screenshot data arrives
  }

  const chatPos = frozenChatPos || getChatPosition()
  const hasConversation = chatVisible

  return (
    <div
      ref={overlayRef}
      className={`overlay ${isExiting ? 'overlay-exiting' : ''} ${isMovingSelection ? 'overlay-moving' : ''} ${isResizingSelection ? 'overlay-resizing' : ''}`}
      style={screenImage ? { backgroundImage: `url(${screenImage})`, backgroundSize: '100% 100%' } : undefined}
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
    >
      <div className="overlay-mask">
        {selection && selection.w > 0 && selection.h > 0 && (
          <svg width="100%" height="100%" className="mask-svg">
            <defs>
              <mask id="selectionMask">
                <rect width="100%" height="100%" fill="white" />
                <rect ref={maskRectRef} x={selection.x} y={selection.y} width={selection.w} height={selection.h} fill="black" />
              </mask>
            </defs>
            <rect width="100%" height="100%" fill="rgba(4, 8, 16, 0.20)" mask="url(#selectionMask)" />
          </svg>
        )}
        {!selection && hoveredWindow && (
          <svg width="100%" height="100%" className="mask-svg">
            <defs>
              <mask id="hoverMask">
                <rect width="100%" height="100%" fill="white" />
                <rect x={hoveredWindow.x} y={hoveredWindow.y} width={hoveredWindow.w} height={hoveredWindow.h} fill="black" />
              </mask>
            </defs>
            <rect width="100%" height="100%" fill="rgba(4, 8, 16, 0.20)" mask="url(#hoverMask)" />
          </svg>
        )}
        {!selection && !hoveredWindow && <div className="full-dim" />}
      </div>

      {selection && selection.w > 0 && selection.h > 0 && !isSelecting && !activeTool && annotations.length === 0 && (
        <div
          className="selection-move-handle"
          style={{ left: selection.x, top: selection.y, width: selection.w, height: selection.h }}
        >
          <div className="sel-handle sel-nw" />
          <div className="sel-handle sel-n" />
          <div className="sel-handle sel-ne" />
          <div className="sel-handle sel-w" />
          <div className="sel-handle sel-e" />
          <div className="sel-handle sel-sw" />
          <div className="sel-handle sel-s" />
          <div className="sel-handle sel-se" />
        </div>
      )}

      {!selection && hoveredWindow && (
        <div
          className="window-hover-border"
          style={{ left: hoveredWindow.x, top: hoveredWindow.y, width: hoveredWindow.w, height: hoveredWindow.h }}
        >
          <div className="window-hover-label">
            {hoveredWindow.owner}{hoveredWindow.name ? ` — ${hoveredWindow.name}` : ''}
          </div>
        </div>
      )}

      {selection && (
        <div
          ref={borderRef}
          className="selection-border"
          style={{ left: selection.x, top: selection.y, width: selection.w, height: selection.h, display: selection.w > 10 && selection.h > 10 ? 'block' : 'none' }}
        >
          <div className="selection-dimensions" ref={dimsRef}>
            {Math.round(selection.w)} × {Math.round(selection.h)}
          </div>
        </div>
      )}

      {/* Drawing canvas overlay */}
      {selection && selection.w > 0 && chatVisible && (
        <DrawingCanvas
          selection={selection}
          activeTool={activeTool}
          activeColor={activeColor}
          activeSize={activeSize}
          annotations={annotations}
          setAnnotations={setAnnotations}
          commitAnnotations={updateAnnotations}
          selectedIndex={selectedAnnotation}
          setSelectedIndex={setSelectedAnnotation}
          mosaicMode={mosaicMode}
          arrowStyle={arrowStyle}
          screenImage={screenImage}
          windowOffset={windowOffset}
          displayInfo={displayInfo}
        />
      )}

      {/* Edit toolbar — shown when selection exists */}
      {selection && selection.w > 0 && chatVisible && (
        <EditToolbar
          selection={selection}
          chatPos={chatPos}
          chatHeight={chatPos.maxHeight}
          activeTool={activeTool}
          setActiveTool={setActiveTool}
          activeColor={activeColor}
          setActiveColor={setActiveColor}
          activeSize={activeSize}
          setActiveSize={setActiveSize}
          selectedIndex={selectedAnnotation}
          annotations={annotations}
          setAnnotations={updateAnnotations}
          mosaicMode={mosaicMode}
          setMosaicMode={setMosaicMode}
          arrowStyle={arrowStyle}
          setArrowStyle={setArrowStyle}
          undo={undo}
          clearAll={clearAll}
          canUndo={undoStack.length > 0}
          onCopy={handleCopy}
          onSave={handleSave}
          copyFeedback={copyFeedback}
          saveFeedback={saveFeedback}
          chatMinimized={chatMinimized}
          onToggleChat={chatMinimized ? handleRestoreChat : handleMinimizeChat}
          onClose={closeWithAnimation}
        />
      )}

      {!chatVisible && !selection && (
        <div className="screenshot-mode-toast">
          Screenshot Mode
        </div>
      )}

      {hasConversation && !chatMinimized && (
        <ChatPanel
          style={{ left: chatPos.left, bottom: chatPos.bottom, top: chatPos.top, height: chatPos.maxHeight }}
          croppedImage={croppedImage}
          getCompositeImage={getCompositeImage}
          currentThread={tm.currentThread}
          setCurrentThread={tm.setCurrentThread}
          recentThreads={tm.recentThreads}
          onThreadChange={(thread) => {
            tm.handleThreadChange(thread)
            if (thread?.messages?.length > 0) {
              setChatFullSize(true)
              setChatMinimized(false)
            } else {
              setChatFullSize(false)
              setChatMinimized(true)
            }
          }}
          onNewThread={tm.handleNewThread}
          onClearAllThreads={tm.handleClearAllThreads}
          onDismissScreenshot={handleDismissScreenshot}
          annotationCount={annotations.length}
          chatFullSize={chatFullSize}
          setChatFullSize={setChatFullSize}
          isNewThread={tm.isNewThread}
          setIsNewThread={tm.setIsNewThread}
          refreshThreads={tm.refreshThreads}
          refreshProviders={tm.refreshProviders}
          onClose={closeWithAnimation}
          onMinimize={handleMinimizeChat}
          onPin={({ screenshotAttached: attached } = {}) => pinOutFromOverlay({ includeCroppedImage: attached, pinned: true })}
          onSentWithImage={(threadSnapshot) => pinOutFromOverlay({ pinned: false, threadOverride: threadSnapshot, pendingSend: true })}
          provider={tm.provider}
          setProvider={tm.setProvider}
          modelId={tm.modelId}
          setModelId={tm.setModelId}
          availableProviders={tm.availableProviders}
        />
      )}

    </div>
  )
}
