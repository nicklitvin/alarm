import { useEffect, useRef, useState, type ReactNode } from 'react'

export interface SwipeAction {
  label: string
  color: string
  onAction: () => void
}

const ACTION_WIDTH = 84
const OPEN_THRESHOLD = 50
/** Swiping this far triggers the action straight away (like a full swipe on iOS). */
const FULL_SWIPE = 210

/**
 * A list row you can slide like on iPhone: slide left to reveal `trailing` (e.g. Delete),
 * slide right to reveal `leading` (e.g. Pin or Done). A long swipe performs the action.
 * Works with mouse drag and touch.
 */
export function SwipeRow({ children, trailing, leading, onClick, className = '' }: {
  children: ReactNode
  trailing?: SwipeAction
  leading?: SwipeAction
  onClick?: () => void
  className?: string
}) {
  const [offset, setOffset] = useState(0)
  const [dragging, setDragging] = useState(false)
  const start = useRef<{ x: number; y: number; base: number } | null>(null)
  const moved = useRef(false)
  const root = useRef<HTMLDivElement>(null)

  // Tapping anywhere else closes an open row.
  useEffect(() => {
    if (offset === 0) return
    const close = (e: PointerEvent) => { if (!root.current?.contains(e.target as Node)) setOffset(0) }
    document.addEventListener('pointerdown', close)
    return () => document.removeEventListener('pointerdown', close)
  }, [offset])

  const clamp = (x: number) => Math.max(trailing ? -FULL_SWIPE - 20 : 0, Math.min(leading ? FULL_SWIPE + 20 : 0, x))

  const onPointerDown = (e: React.PointerEvent) => {
    if ((e.target as HTMLElement).closest('button, input, a')) return // let inner buttons work normally
    start.current = { x: e.clientX, y: e.clientY, base: offset }
    moved.current = false
  }
  const onPointerMove = (e: React.PointerEvent) => {
    if (!start.current) return
    const dx = e.clientX - start.current.x
    const dy = e.clientY - start.current.y
    if (!moved.current) {
      if (Math.abs(dx) < 8 || Math.abs(dx) < Math.abs(dy)) return // vertical scroll, or not a swipe yet
      moved.current = true
      setDragging(true)
      ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    }
    setOffset(clamp(start.current.base + dx))
  }
  const onPointerUp = () => {
    if (!start.current) return
    start.current = null
    setDragging(false)
    if (!moved.current) return
    if (trailing && offset <= -FULL_SWIPE) { setOffset(0); trailing.onAction(); return }
    if (leading && offset >= FULL_SWIPE) { setOffset(0); leading.onAction(); return }
    setOffset(offset < -OPEN_THRESHOLD && trailing ? -ACTION_WIDTH : offset > OPEN_THRESHOLD && leading ? ACTION_WIDTH : 0)
  }
  const onContentClick = () => {
    if (moved.current) { moved.current = false; return } // end of a drag, not a tap
    if (offset !== 0) { setOffset(0); return }
    onClick?.()
  }

  return (
    <div className="swipe" ref={root}>
      {leading && offset > 0 && (
        <button className="swipe-action leading" style={{ background: leading.color, width: Math.max(ACTION_WIDTH, offset) }}
          onClick={() => { setOffset(0); leading.onAction() }}>{leading.label}</button>
      )}
      {trailing && offset < 0 && (
        <button className="swipe-action trailing" style={{ background: trailing.color, width: Math.max(ACTION_WIDTH, -offset) }}
          onClick={() => { setOffset(0); trailing.onAction() }}>{trailing.label}</button>
      )}
      <div className={`swipe-content row ${onClick ? 'tappable' : ''} ${className}`}
        style={{ transform: `translateX(${offset}px)`, transition: dragging ? 'none' : 'transform 0.22s ease' }}
        onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp} onPointerCancel={onPointerUp}
        onClick={onContentClick}>
        {children}
      </div>
    </div>
  )
}
