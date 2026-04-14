import React, { useEffect, useMemo, useState, useRef, useCallback } from 'react'

// Eye icon using currentColor (inherits CSS color, works in both themes)
const EyeIcon = ({ size = 24 }) => (
  <svg viewBox="60 140 420 280" width={size} height={Math.round(size * 280 / 420)}>
    <path d="M180 195 C220 165, 320 155, 360 185" fill="none" stroke="currentColor" strokeWidth="20" strokeLinecap="round" />
    <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="currentColor" strokeWidth="22" strokeLinecap="round" />
  </svg>
)

function groupByDate(images) {
  const groups = []
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  const yesterday = today - 86400000

  let currentLabel = null
  let currentItems = []

  for (const img of images) {
    const ts = img.timestamp
    let label
    if (ts >= today) label = 'Today'
    else if (ts >= yesterday) label = 'Yesterday'
    else {
      const d = new Date(ts)
      label = d.toLocaleDateString('en-US', { month: 'long', day: 'numeric' })
    }

    if (label !== currentLabel) {
      if (currentItems.length) groups.push({ label: currentLabel, items: currentItems })
      currentLabel = label
      currentItems = []
    }
    currentItems.push(img)
  }
  if (currentItems.length) groups.push({ label: currentLabel, items: currentItems })
  return groups
}

function formatTime(ts) {
  return new Date(ts).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
}

function buildImageUrl(path) {
  if (!path || !window._glimpseAppSupportDir) return ''
  const fullPath = `${window._glimpseAppSupportDir}/${path}`
  return 'file://' + fullPath.split('/').map(s => encodeURIComponent(s)).join('/')
}

export default function ImageBoard({
  images,
  viewMode,
  viewerImageIndex,
  highlightImagePath,
  onHighlightConsumed,
  onImageClick,
  onBack,
  onClose,
  onFindInChat,
  onQuoteInNewChat,
  onToggleBoard,
}) {
  // Highlight a specific image card when navigating from chat viewer "All images"
  useEffect(() => {
    if (viewMode !== 'board' || !highlightImagePath) return
    onHighlightConsumed?.()
    // Poll for the card to appear, then scroll + highlight
    let attempts = 0
    const tryHighlight = () => {
      const card = document.querySelector(`[data-image-path="${CSS.escape(highlightImagePath)}"]`)
      if (card) {
        card.scrollIntoView({ behavior: 'smooth', block: 'center' })
        card.classList.remove('card-highlight')
        void card.offsetWidth
        card.classList.add('card-highlight')
      } else if (attempts < 15) {
        attempts++
        setTimeout(tryHighlight, 100)
      }
    }
    setTimeout(tryHighlight, 200)
  }, [viewMode, highlightImagePath])

  // Arrow key navigation in viewer
  useEffect(() => {
    if (viewMode !== 'viewer') return
    const handleKey = (e) => {
      if (e.key === 'ArrowLeft' && viewerImageIndex > 0) {
        e.preventDefault()
        onImageClick(viewerImageIndex - 1)
      } else if (e.key === 'ArrowRight' && viewerImageIndex < images.length - 1) {
        e.preventDefault()
        onImageClick(viewerImageIndex + 1)
      }
    }
    window.addEventListener('keydown', handleKey)
    return () => window.removeEventListener('keydown', handleKey)
  }, [viewMode, viewerImageIndex, images.length, onImageClick])

  // Zoom/pan state — option 2: resize <img> element for sharp rendering
  const [zoom, setZoom] = useState(1)
  const isPanning = useRef(false)
  const lastMouse = useRef({ x: 0, y: 0 })
  const imageAreaRef = useRef(null)
  const imgRef = useRef(null)
  const naturalSize = useRef({ w: 0, h: 0 })

  const isZoomed = zoom > 1.01

  // Reset zoom when switching images
  useEffect(() => {
    setZoom(1)
    const el = imageAreaRef.current
    if (el) { el.scrollLeft = 0; el.scrollTop = 0 }
  }, [viewerImageIndex])

  // Capture natural image size on load
  const handleImageLoad = useCallback((e) => {
    naturalSize.current = { w: e.target.naturalWidth, h: e.target.naturalHeight }
  }, [])

  // Wheel/pinch zoom handler — resizes <img> element directly
  const handleWheel = useCallback((e) => {
    if (!e.ctrlKey && !isZoomed) return  // only intercept pinch or scroll-when-zoomed
    e.preventDefault()
    if (!e.ctrlKey && isZoomed) {
      // Two-finger scroll to pan when zoomed
      const container = imageAreaRef.current
      if (container) {
        container.scrollLeft += e.deltaX
        container.scrollTop += e.deltaY
      }
      return
    }
    if (e.ctrlKey) {
      // Pinch gesture
      const container = imageAreaRef.current
      const img = imgRef.current
      if (!container || !img) return

      // Cursor position relative to container
      const rect = container.getBoundingClientRect()
      const cursorX = e.clientX - rect.left + container.scrollLeft
      const cursorY = e.clientY - rect.top + container.scrollTop

      // Fraction of image under cursor (before zoom)
      const fracX = cursorX / img.offsetWidth
      const fracY = cursorY / img.offsetHeight

      const prev = zoom
      const next = Math.min(Math.max(prev * (1 - e.deltaY * 0.01), 1), 4)

      setZoom(next)

      // After zoom, adjust scroll so the point under cursor stays put
      requestAnimationFrame(() => {
        if (!container || !img) return
        const newCursorX = fracX * img.offsetWidth
        const newCursorY = fracY * img.offsetHeight
        container.scrollLeft = newCursorX - (e.clientX - rect.left)
        container.scrollTop = newCursorY - (e.clientY - rect.top)
      })
    }
    // When zoomed, normal scroll events just scroll the container natively (overflow: auto)
  }, [zoom, isZoomed])

  // Attach wheel handler (need passive: false for preventDefault on pinch)
  useEffect(() => {
    const el = imageAreaRef.current
    if (!el || viewMode !== 'viewer') return
    el.addEventListener('wheel', handleWheel, { passive: false })
    return () => el.removeEventListener('wheel', handleWheel)
  }, [viewMode, handleWheel])

  // Drag to pan when zoomed
  const handleMouseDown = useCallback((e) => {
    if (!isZoomed) return
    isPanning.current = true
    lastMouse.current = { x: e.clientX, y: e.clientY }
    e.preventDefault()
  }, [isZoomed])

  const handleMouseMove = useCallback((e) => {
    if (!isPanning.current) return
    const dx = e.clientX - lastMouse.current.x
    const dy = e.clientY - lastMouse.current.y
    lastMouse.current = { x: e.clientX, y: e.clientY }
    const el = imageAreaRef.current
    if (el) {
      el.scrollLeft -= dx
      el.scrollTop -= dy
    }
  }, [])

  const handleMouseUp = useCallback(() => {
    isPanning.current = false
  }, [])

  // Double-click to reset zoom
  const handleDoubleClick = useCallback(() => {
    setZoom(1)
    const el = imageAreaRef.current
    if (el) { el.scrollLeft = 0; el.scrollTop = 0 }
  }, [])

  const groups = useMemo(() => groupByDate(images), [images])
  const currentImage = images[viewerImageIndex]

  if (viewMode === 'viewer' && currentImage) {
    return (
      <div className="image-board" role="region" aria-label="Image viewer">
        {/* Viewer header */}
        <div className="board-header">
          <button className="board-back-btn" onClick={onBack} aria-label="Back to grid">
            <svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 4l-6 6 6 6" />
            </svg>
          </button>
          <span className="board-header-title">{viewerImageIndex + 1} of {images.length}</span>
          <div className="board-header-spacer" />
        </div>

        {/* Image viewer */}
        <div className="viewer-content">
          <div className="viewer-image-wrapper">
            <div
              className={`viewer-image-area ${isZoomed ? 'zoomed' : ''}`}
              ref={imageAreaRef}
              onMouseDown={handleMouseDown}
              onMouseMove={handleMouseMove}
              onMouseUp={handleMouseUp}
              onMouseLeave={handleMouseUp}
              onDoubleClick={handleDoubleClick}
            >
              <img
                className="viewer-image"
                ref={imgRef}
                src={buildImageUrl(currentImage.path)}
                alt={`Screenshot${currentImage.question ? ': ' + currentImage.question.slice(0, 80) : ''}`}
                draggable={false}
                onLoad={handleImageLoad}
                style={isZoomed ? {
                  width: `${zoom * 100}%`,
                  height: 'auto',
                  maxWidth: 'none',
                  maxHeight: 'none',
                } : undefined}
              />
            </div>
            {viewerImageIndex > 0 && (
              <button className="viewer-nav prev" onClick={() => onImageClick(viewerImageIndex - 1)} aria-label="Previous image">
                <svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M12 4l-6 6 6 6" />
                </svg>
              </button>
            )}
            {viewerImageIndex < images.length - 1 && (
              <button className="viewer-nav next" onClick={() => onImageClick(viewerImageIndex + 1)} aria-label="Next image">
                <svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M8 4l6 6-6 6" />
                </svg>
              </button>
            )}
          </div>

          {/* Context card */}
          <div className="viewer-context">
            {(currentImage.question || currentImage.answer) && (
              <div className="viewer-context-summary">
                {currentImage.question && (
                  <div className="viewer-context-q">
                    <span className="viewer-context-label">Q</span>
                    <span className="viewer-context-text">{currentImage.question}</span>
                  </div>
                )}
                {currentImage.answer && (
                  <div className="viewer-context-a">
                    <span className="viewer-context-label">A</span>
                    <span className="viewer-context-text">{currentImage.answer}</span>
                  </div>
                )}
              </div>
            )}
            <div className="viewer-actions">
              <button className="viewer-action-btn" onClick={() => onFindInChat(currentImage.threadId, currentImage.messageIndex)}>
                <svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
                  <path d="M3 8h10M9 4l4 4-4 4" />
                </svg>
                Find in chat
              </button>
              <span className="viewer-date">{formatTime(currentImage.timestamp)}</span>
            </div>
          </div>
        </div>
      </div>
    )
  }

  // Grid mode
  return (
    <div className="image-board" role="region" aria-label="Image gallery">
      {/* Board header */}
      <div className="board-header">
        <button
          className="glimpse-icon-fixed chat-header-eye board-active"
          onClick={(e) => { e.stopPropagation(); onToggleBoard() }}
          aria-label="Return to chat"
          style={{ color: 'var(--brand)' }}
        >
          <EyeIcon size={24} />
        </button>
        <span className="board-header-title">Images</span>
        <span className="board-image-count">&middot; {images.length}</span>
        <div className="board-header-spacer" />
      </div>

      {/* Grid or empty state */}
      {images.length === 0 ? (
        <div className="board-empty-state" role="status" aria-label="No screenshots yet">
          <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" style={{ opacity: 0.3 }} aria-hidden="true">
            <rect x="3" y="3" width="18" height="18" rx="3" />
            <circle cx="8.5" cy="8.5" r="1.5" />
            <path d="M21 15l-5-5L5 21" />
          </svg>
          <span className="board-empty-text">Your screenshots will appear here</span>
          <span className="board-empty-hint">Take a screenshot with &#8984;&#8679;Z and chat about it</span>
        </div>
      ) : (
        <div className="board-grid-area">
          {groups.map((group) => (
            <div className="board-time-group" key={group.label}>
              <div className="board-time-label">{group.label}</div>
              <div className="board-image-grid" role="list">
                {group.items.map((img) => {
                  const globalIndex = images.indexOf(img)
                  return (
                    <button
                      className="board-image-card"
                      key={img.path}
                      data-image-path={img.path}
                      onClick={() => onImageClick(globalIndex)}
                      role="listitem"
                      aria-label={`Screenshot from ${formatTime(img.timestamp)}`}
                    >
                      <img
                        className="board-image-thumb"
                        src={buildImageUrl(img.path)}
                        alt=""
                        draggable={false}
                      />
                      <span className="board-image-time">{formatTime(img.timestamp)}</span>
                    </button>
                  )
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
