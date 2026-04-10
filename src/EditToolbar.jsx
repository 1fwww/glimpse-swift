import React, { useState, useRef, useMemo, useEffect } from 'react'

const tools = [
  { id: 'rect', label: 'Rectangle', icon: <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="3" y="3" width="18" height="18" rx="2" /></svg> },
  { id: 'ellipse', label: 'Ellipse', icon: <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5"><ellipse cx="12" cy="12" rx="10" ry="7" /></svg> },
  { id: 'arrow', label: 'Arrow', icon: <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M5 19L19 5M19 5H9M19 5v10" /></svg> },
  { id: 'line', label: 'Line', icon: <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M5 19L19 5" /></svg> },
  { id: 'pen', label: 'Draw', icon: <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M3 21l1-6L16.5 2.5a2 2 0 0 1 3 0l2 2a2 2 0 0 1 0 3L9 20l-6 1z" /><path d="M15 4l5 5" /><path d="M2 22c2-2 4-6 8-8" strokeDasharray="2 2" opacity="0.5" /></svg> },
  { id: 'text', label: 'Text', icon: <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5"><path d="M6 4h12M12 4v16" /><path d="M8 20h8" /></svg> },
  { id: 'mosaic', label: 'Mosaic', icon: <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x="2" y="2" width="5" height="5" fill="currentColor" opacity="0.7" /><rect x="9.5" y="2" width="5" height="5" fill="currentColor" opacity="0.3" /><rect x="17" y="2" width="5" height="5" fill="currentColor" opacity="0.7" /><rect x="2" y="9.5" width="5" height="5" fill="currentColor" opacity="0.3" /><rect x="9.5" y="9.5" width="5" height="5" fill="currentColor" opacity="0.7" /><rect x="17" y="9.5" width="5" height="5" fill="currentColor" opacity="0.3" /><rect x="2" y="17" width="5" height="5" fill="currentColor" opacity="0.7" /><rect x="9.5" y="17" width="5" height="5" fill="currentColor" opacity="0.3" /><rect x="17" y="17" width="5" height="5" fill="currentColor" opacity="0.7" /></svg> },
]

const colors = [
  { hex: '#DC3545', name: 'Red' },
  { hex: '#E08700', name: 'Amber' },
  { hex: '#06B6D4', name: 'Cyan' },
  { hex: '#1E40AF', name: 'Blue' },
  { hex: '#EC4899', name: 'Pink' },
  { hex: '#000000', name: 'Black' },
  { hex: '#ffffff', name: 'White' },
]
const sizes = [2, 4, 6]
const fontSizes = [8, 12, 16, 20, 28, 36, 48, 60, 72, 96]

const mosaicSizes = [16, 28, 44]

export default function EditToolbar({ selection, chatPos, chatHeight, activeTool, setActiveTool, activeColor, setActiveColor, activeSize, setActiveSize, selectedIndex, annotations, setAnnotations: commitAnnotations, mosaicMode, setMosaicMode, undo, clearAll, canUndo, onCopy, onSave, copyFeedback, saveFeedback, chatMinimized, onToggleChat, onClose }) {
  const [showOptions, setShowOptions] = useState(false)
  const [suppressAiTip, setSuppressAiTip] = useState(false)
  const lastStrokeSize = useRef(4)
  const lastFontSize = useRef(20)
  const lastMosaicSize = useRef(28)
  const [tooltip, setTooltip] = useState(null)
  const [tooltipX, setTooltipX] = useState(0)
  const saveBtnRef = useRef(null)
  const copyBtnRef = useRef(null)

  // Show tooltip on feedback state changes
  useEffect(() => {
    if (copyFeedback && copyBtnRef.current) {
      setTooltip('Copied to clipboard')
      setTooltipX(copyBtnRef.current.offsetLeft + copyBtnRef.current.offsetWidth / 2)
    }
  }, [copyFeedback])

  useEffect(() => {
    if (saveFeedback && saveBtnRef.current) {
      setTooltip('Saved')
      setTooltipX(saveBtnRef.current.offsetLeft + saveBtnRef.current.offsetWidth / 2)
    }
  }, [saveFeedback])
  const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 })
  const isDragging = useRef(false)
  const dragStart = useRef({ x: 0, y: 0 })

  // Position toolbar: below selection → above → inside bottom
  // Avoids overlapping with chat panel
  const position = useMemo(() => {
    if (!selection) return {}

    const screenW = window.innerWidth
    const screenH = window.innerHeight
    const toolbarH = 44
    const toolbarW = 500 // tools bar (with close) + AI icon + gap
    const gap = 10
    const notchSafeY = 52

    const selBottom = selection.y + selection.h
    const selTop = selection.y

    // Horizontal: center on selection, clamp to screen
    let left = selection.x + (selection.w - toolbarW) / 2
    left = Math.max(8, Math.min(left, screenW - toolbarW - 8))

    // Vertical: try below, then above (respecting notch), then inside
    let top
    if (selBottom + gap + toolbarH < screenH) {
      top = selBottom + gap
    } else if (selTop - gap - toolbarH >= notchSafeY) {
      top = selTop - gap - toolbarH
    } else {
      top = Math.max(notchSafeY, selBottom - gap - toolbarH)
    }

    // Check overlap with chat panel and adjust if needed
    if (chatPos) {
      const chatLeft = chatPos.left || 0
      const chatW = 380
      const chatTop = chatPos.top != null ? chatPos.top : (chatPos.bottom != null ? screenH - chatPos.bottom - (chatHeight || 320) : 0)
      const chatBottom = chatTop + (chatHeight || 320)

      const tbRight = left + toolbarW
      const tbBottom = top + toolbarH

      // Check if they overlap (both horizontally and vertically)
      const hOverlap = left < chatLeft + chatW && tbRight > chatLeft
      const vOverlap = top < chatBottom && tbBottom > chatTop

      if (hOverlap && vOverlap) {
        // Try moving toolbar above selection
        if (selTop - gap - toolbarH >= notchSafeY) {
          top = selTop - gap - toolbarH
        } else {
          // Shift toolbar horizontally away from chat
          if (chatLeft > screenW / 2) {
            // Chat is on right, push toolbar left
            left = Math.max(8, chatLeft - toolbarW - gap)
          } else {
            // Chat is on left, push toolbar right
            left = Math.min(screenW - toolbarW - 8, chatLeft + chatW + gap)
          }
        }
      }
    }

    return { left, top }
  }, [selection, chatPos, chatHeight])

  const handleToolbarMouseDown = (e) => {
    // Don't drag when clicking buttons
    if (e.target.closest('button')) {
      e.stopPropagation()
      return
    }
    e.stopPropagation()
    isDragging.current = true
    dragStart.current = { x: e.clientX - dragOffset.x, y: e.clientY - dragOffset.y }

    const handleMouseMove = (ev) => {
      if (!isDragging.current) return
      setDragOffset({
        x: ev.clientX - dragStart.current.x,
        y: ev.clientY - dragStart.current.y,
      })
    }
    const handleMouseUp = () => {
      isDragging.current = false
      window.removeEventListener('mousemove', handleMouseMove)
      window.removeEventListener('mouseup', handleMouseUp)
    }
    window.addEventListener('mousemove', handleMouseMove)
    window.addEventListener('mouseup', handleMouseUp)
  }

  if (!selection) return null

  return (
    <div
      className="edit-toolbar"
      style={{
        left: position.left,
        top: position.top,
        transform: `translate(${dragOffset.x}px, ${dragOffset.y}px)`,
      }}
      onMouseDown={handleToolbarMouseDown}
    >
      <div className="edit-toolbar-top">
      <div className="edit-toolbar-tools" onMouseLeave={() => setTooltip(null)}>
        <button
          className="edit-tool-btn"
          aria-label="Settings"
          onClick={(e) => {
            const panel = document.querySelector('.chat-panel')
            const el = panel || e.currentTarget.closest('.edit-toolbar')
            const r = el?.getBoundingClientRect()
            window.electronAPI?.openSettings(r ? { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) } : null)
          }}
          onMouseEnter={(e) => { setTooltip('Settings'); setTooltipX(e.currentTarget.offsetLeft + e.currentTarget.offsetWidth / 2) }}
        >
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="3" />
            <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
          </svg>
        </button>
        <span className="edit-toolbar-sep" />
        {tools.map(tool => (
          <button
            key={tool.id}
            className={`edit-tool-btn ${activeTool === tool.id ? 'active' : ''}`}
            aria-label={tool.label}
            aria-pressed={activeTool === tool.id}
            onClick={() => {
              const newTool = activeTool === tool.id ? null : tool.id
              // Save current size for the tool type we're leaving
              if (activeTool === 'text') lastFontSize.current = activeSize
              else if (activeTool === 'mosaic') lastMosaicSize.current = activeSize
              else if (activeTool) lastStrokeSize.current = activeSize
              // Restore size for the tool type we're entering
              if (newTool === 'text') setActiveSize(lastFontSize.current)
              else if (newTool === 'mosaic') setActiveSize(lastMosaicSize.current)
              else if (newTool) setActiveSize(lastStrokeSize.current)
              setActiveTool(newTool)
              setShowOptions(newTool !== null)
            }}
            onMouseEnter={(e) => { setTooltip(tool.label); setTooltipX(e.currentTarget.offsetLeft + e.currentTarget.offsetWidth / 2) }}
          >
            {tool.icon}
          </button>
        ))}

        <span className="edit-toolbar-sep" />

        <button
          className={`edit-tool-btn ${!canUndo ? 'disabled' : ''}`}
          aria-label="Undo"
          onClick={undo}
          onMouseEnter={(e) => { setTooltip('Undo'); setTooltipX(e.currentTarget.offsetLeft + e.currentTarget.offsetWidth / 2) }}
        >
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M3 10h10a5 5 0 0 1 0 10H9" /><path d="M7 6L3 10l4 4" />
          </svg>
        </button>
        <button
          className={`edit-tool-btn ${!canUndo ? 'disabled' : ''}`}
          aria-label="Clear all annotations"
          onClick={clearAll}
          onMouseEnter={(e) => { setTooltip('Clear all annotations'); setTooltipX(e.currentTarget.offsetLeft + e.currentTarget.offsetWidth / 2) }}
        >
          <span className="edit-tool-label">Reset</span>
        </button>

        <span className="edit-toolbar-sep" />

        <button
          ref={copyBtnRef}
          className={`edit-tool-btn edit-tool-primary ${copyFeedback ? 'copied' : ''}`}
          aria-label="Copy"
          onClick={onCopy}
          onMouseEnter={(e) => { setTooltip(copyFeedback ? 'Copied to clipboard' : 'Copy'); setTooltipX(e.currentTarget.offsetLeft + e.currentTarget.offsetWidth / 2) }}
        >
          {copyFeedback ? (
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#2DA44E" strokeWidth="2">
              <path d="M20 6L9 17l-5-5" />
            </svg>
          ) : (
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2">
              <rect x="9" y="9" width="13" height="13" rx="2" /><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
            </svg>
          )}
        </button>
        <button
          ref={saveBtnRef}
          className={`edit-tool-btn edit-tool-primary ${saveFeedback ? 'copied' : ''}`}
          aria-label="Save"
          onClick={onSave}
          onMouseEnter={(e) => { setTooltip(saveFeedback ? 'Saved' : 'Save'); setTooltipX(e.currentTarget.offsetLeft + e.currentTarget.offsetWidth / 2) }}
        >
          {saveFeedback ? (
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="#2DA44E" strokeWidth="2">
              <path d="M20 6L9 17l-5-5" />
            </svg>
          ) : (
            <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" />
            </svg>
          )}
        </button>

        <span className="edit-toolbar-sep" />

        <button
          className="edit-tool-btn edit-tool-cancel"
          aria-label="Cancel"
          onClick={onClose}
          onMouseEnter={(e) => { setTooltip('Cancel'); setTooltipX(e.currentTarget.offsetLeft + e.currentTarget.offsetWidth / 2) }}
        >
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M18 6L6 18M6 6l12 12" />
          </svg>
        </button>

        {/* Tooltip */}
        {tooltip && (
          <div
            className={`edit-toolbar-tooltip ${(copyFeedback || saveFeedback) && (tooltip === 'Copied to clipboard' || tooltip === 'Saved') ? 'tooltip-success' : ''}`}
            style={{ left: tooltipX }}
          >{tooltip}</div>
        )}
      </div>

      {/* AI chat toggle — visually separate circle */}
      <button
        className={`edit-ai-toggle ${!chatMinimized ? 'active' : ''}`}
        aria-label={chatMinimized ? 'Open AI chat' : 'Minimize chat'}
        onClick={() => { onToggleChat(); setSuppressAiTip(true); setTimeout(() => setSuppressAiTip(false), 3000) }}
        onMouseDown={(e) => e.stopPropagation()}
        {...(!suppressAiTip ? { 'data-tip': chatMinimized ? 'Ask AI' : 'Minimize chat' } : {})}
      >
        {chatMinimized ? (
          <svg className="edit-ai-eye" viewBox="60 140 420 280" width="30" height="20">
            <g className="edit-ai-brow">
              <path d="M98 212C152 174 365 158 420 248" fill="none" stroke="#6C63FF" strokeWidth="20" strokeLinecap="round" />
            </g>
            <path d="M262 374C228 373 176 360 128 321C176 276 314 200 390 270C462 336 350 379 322 374C248 361 262 276 322 279C378 282 363 346 322 332" fill="none" stroke="#6C63FF" strokeWidth="22" strokeLinecap="round" />
          </svg>
        ) : (
          <svg viewBox="0 0 24 24" width="24" height="24" fill="none">
            <rect x="4" y="10" width="16" height="4" rx="2" fill="#6c63ff" />
          </svg>
        )}
      </button>

      </div>{/* end edit-toolbar-top */}

      {/* Color + size/font options — shown when a tool is active OR annotation is selected */}
      {((showOptions && activeTool) || selectedIndex !== null) && activeTool === 'mosaic' && (
        <div className="edit-toolbar-options">
          <button
            className={`edit-mosaic-mode ${mosaicMode === 'brush' ? 'active' : ''}`}
            onClick={() => setMosaicMode('brush')}
            title="Brush"
          >
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.5">
              <path d="M3 17c3-3 5-8 9-8s4 4 6 4 3-2 3-2" />
            </svg>
          </button>
          <button
            className={`edit-mosaic-mode ${mosaicMode === 'rect' ? 'active' : ''}`}
            onClick={() => setMosaicMode('rect')}
            title="Rectangle"
          >
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.5">
              <rect x="3" y="3" width="18" height="18" rx="1" strokeDasharray="4 2" />
            </svg>
          </button>
          {mosaicMode === 'brush' && <>
            <span className="edit-toolbar-sep" />
            <div className="edit-size-picker">
              {mosaicSizes.map((s, i) => (
                <button
                  key={s}
                  className={`edit-size-btn ${activeSize === s ? 'active' : ''}`}
                  onClick={() => setActiveSize(s)}
                  title={['Small', 'Medium', 'Large'][i]}
                >
                  <span className="edit-size-line" style={{ height: [3, 5, 7][i] }} />
                </button>
              ))}
            </div>
          </>}
        </div>
      )}
      {((showOptions && activeTool && activeTool !== 'mosaic') || selectedIndex !== null) && (
        <div className="edit-toolbar-options">
          <div className="edit-color-picker">
            {colors.map(({ hex, name }) => {
              const isActive = selectedIndex !== null && annotations[selectedIndex]
                ? annotations[selectedIndex].color === hex
                : activeColor === hex
              return (
                <button
                  key={hex}
                  className={`edit-color-dot ${isActive ? 'active' : ''}`}
                  style={{ background: hex }}
                  aria-label={name}
                  aria-pressed={isActive}
                  onClick={() => {
                    setActiveColor(hex)
                    if (selectedIndex !== null) {
                      commitAnnotations(prev => prev.map((ann, i) =>
                        i === selectedIndex ? { ...ann, color: hex } : ann
                      ))
                    }
                  }}
                />
              )
            })}
          </div>
          {activeTool && activeTool !== 'mosaic' && <>
          <span className="edit-toolbar-sep" />
          {activeTool === 'text' ? (
            <select
              className="edit-font-size-select"
              value={activeSize}
              onChange={(e) => setActiveSize(Number(e.target.value))}
            >
              {fontSizes.map(s => (
                <option key={s} value={s}>{s}pt</option>
              ))}
            </select>
          ) : (
            <div className="edit-size-picker">
              {sizes.map((s, i) => (
                <button
                  key={s}
                  className={`edit-size-btn ${activeSize === s ? 'active' : ''}`}
                  onClick={() => setActiveSize(s)}
                  title={['Thin', 'Medium', 'Thick'][i]}
                >
                  <span className="edit-size-line" style={{ height: s }} />
                </button>
              ))}
            </div>
          )}
          </>}
        </div>
      )}
    </div>
  )
}
