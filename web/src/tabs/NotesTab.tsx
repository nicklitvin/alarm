import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { SwipeRow } from '../components/SwipeRow'
import { Alert, BottomAction, Section, TabHeader } from '../components/ui'
import { checklistProgress, checklistReturn, lineBounds, lineKind, noteCopyText, notePreview, noteTitle, reorderNotes, sortNotes, toggleItem, toggleList, autoBullet, uid, type Note } from '../logic/model'
import { useStore } from '../logic/store'

const progressLabel = (n: Note) => {
  const p = checklistProgress(n.body)
  return p ? <span style={{ color: p.done === p.total ? 'var(--orange)' : undefined }}> · ☑ {p.done}/{p.total}</span> : null
}

const ago = (ms: number, now: number) => {
  const m = Math.round((now - ms) / 60000)
  if (m < 1) return 'now'
  if (m < 60) return `${m} min ago`
  const h = Math.round(m / 60)
  if (h < 24) return `${h} hr ago`
  const d = Math.round(h / 24)
  return d === 1 ? 'yesterday' : `${d} days ago`
}

function useCopy() {
  const [copied, setCopied] = useState<string | null>(null)
  const copy = (note: Note) => {
    navigator.clipboard?.writeText(noteCopyText(note)).catch(() => {})
    setCopied(note.id)
    setTimeout(() => setCopied((c) => (c === note.id ? null : c)), 1500)
  }
  return { copied, copy }
}

export function NotesTab() {
  const { data, update, now, pending, clearPending } = useStore()
  const [openID, setOpenID] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  /** A note picked up by press-and-hold, and the note it's currently over. */
  const [drag, setDrag] = useState<{ id: string; overId: string | null } | null>(null)
  const dragRef = useRef(drag)
  dragRef.current = drag
  const { copied, copy } = useCopy()
  const sort = data.settings.notesSort

  useEffect(() => {
    if (pending?.tab !== 'notes' || !pending.id) return
    if (data.notes.some((n) => n.id === pending.id)) setOpenID(pending.id)
    clearPending()
  }, [pending, data.notes, clearPending])

  const setNotes = (change: (notes: Note[]) => Note[]) => update((d) => ({ ...d, notes: change(d.notes) }))
  const q = query.trim().toLowerCase()
  const visible = sortNotes(data.notes, sort).filter((n) => !q || n.title.toLowerCase().includes(q) || n.body.toLowerCase().includes(q))

  // While a note is held: track which note the pointer is over, and drop it there on release.
  useEffect(() => {
    if (!drag) return
    const over = (e: PointerEvent) => {
      const id = (document.elementFromPoint(e.clientX, e.clientY)?.closest('.swipe[data-id]') as HTMLElement | null)?.dataset.id ?? null
      setDrag((d) => (d && d.overId !== id ? { ...d, overId: id } : d))
    }
    const drop = () => {
      const d = dragRef.current
      if (d?.overId && d.overId !== d.id) {
        const { id, overId } = d
        update((s) => ({ ...s, notes: reorderNotes(s.notes, id, overId, s.settings.notesSort), settings: { ...s.settings, notesSort: 'manual' } }))
      }
      setDrag(null)
    }
    document.addEventListener('pointermove', over)
    document.addEventListener('pointerup', drop)
    document.body.style.userSelect = 'none'
    return () => {
      document.removeEventListener('pointermove', over)
      document.removeEventListener('pointerup', drop)
      document.body.style.userSelect = ''
    }
  }, [drag?.id, update]) // eslint-disable-line react-hooks/exhaustive-deps

  if (openID) {
    const note = data.notes.find((n) => n.id === openID)
    if (note) return <NoteEditor note={note} onBack={() => {
      if (!note.title.trim() && !note.body.trim()) setNotes((ns) => ns.filter((n) => n.id !== note.id))
      setOpenID(null)
    }} />
  }

  const newNote = () => {
    const top = Math.min(0, ...data.notes.map((n) => n.sortIndex)) - 1
    const note: Note = { id: uid(), title: '', body: '', createdAt: Date.now(), updatedAt: Date.now(), isPinned: false, sortIndex: top }
    setNotes((ns) => [...ns, note])
    setOpenID(note.id)
  }

  const info = (n: Note) => (
    <div className="grow">
      <div className="ellipsis" style={{ fontWeight: 600 }}>{noteTitle(n)}</div>
      <div className="sub ellipsis">{ago(n.updatedAt, now)}{progressLabel(n)} <span style={{ color: 'var(--tertiary)' }}>{notePreview(n)}</span></div>
    </div>
  )

  // Swipe left to delete, right to pin. Press and hold to pick a note up and drag it elsewhere.
  const order = visible.map((n) => n.id)
  const dragClass = (n: Note) => {
    if (!drag) return ''
    if (drag.id === n.id) return 'lifted'
    if (drag.overId !== n.id || q) return ''
    return order.indexOf(drag.id) < order.indexOf(n.id) ? 'drop-after' : 'drop-before'
  }
  const row = (n: Note) => (
    <SwipeRow key={n.id} dataId={n.id} className={dragClass(n)} onClick={() => setOpenID(n.id)}
      onHold={q ? undefined : () => setDrag({ id: n.id, overId: null })}
      leading={{ label: n.isPinned ? 'Unpin' : 'Pin', color: 'var(--orange)', onAction: () => setNotes((ns) => ns.map((x) => (x.id === n.id ? { ...x, isPinned: !x.isPinned } : x))) }}
      trailing={{ label: 'Delete', color: 'var(--red)', onAction: () => setNotes((ns) => ns.filter((x) => x.id !== n.id)) }}>
      {info(n)}
      <button className="copy-btn" aria-label="Copy All" onClick={(e) => { e.stopPropagation(); copy(n) }}>{copied === n.id ? '✓' : '⧉'}</button>
    </SwipeRow>
  )

  const pinned = visible.filter((n) => n.isPinned)
  const others = visible.filter((n) => !n.isPinned)
  return (
    <>
      <TabHeader title="Notes" tab="notes" detail={data.notes.length ? `${data.notes.length} note${data.notes.length === 1 ? '' : 's'}` : null} />
      <div style={{ padding: '0 20px 10px', position: 'sticky', top: 52, zIndex: 19, background: 'var(--bg-grouped)' }}>
        <div className="field"><span className="muted">⌕</span><input placeholder="Search Notes" value={query} onChange={(e) => setQuery(e.target.value)} /></div>
      </div>
      {pinned.length > 0 && <Section header="Pinned">{pinned.map(row)}</Section>}
      {others.length > 0 && <Section header={pinned.length ? 'Notes' : undefined}>{others.map(row)}</Section>}
      {data.notes.length === 0 && <div className="talk-empty" style={{ paddingTop: 80 }}><div className="big">🗒</div><h3>No Notes</h3>Tap New Note below.</div>}
      {data.notes.length > 0 && visible.length === 0 && <div className="talk-empty" style={{ paddingTop: 60 }}>No results for “{query}”</div>}
      <BottomAction label="New Note" onClick={newNote} />
    </>
  )
}

function NoteEditor({ note, onBack }: { note: Note; onBack: () => void }) {
  const { update } = useStore()
  const { copied, copy } = useCopy()
  const [confirm, setConfirm] = useState<'clear' | 'delete' | null>(null)
  const [typing, setTyping] = useState(false)
  const body = useRef<HTMLTextAreaElement>(null)

  // The text area grows with its text, so the page scrolls along as you type (instead of the text
  // scrolling inside a small box), and the caret is kept in view.
  useEffect(() => {
    const t = body.current
    if (!t) return
    t.style.height = 'auto'
    t.style.height = `${t.scrollHeight}px`
    if (document.activeElement === t) {
      const scroller = t.closest('.app-body')
      const caretBottom = t.getBoundingClientRect().bottom
      const visibleBottom = (scroller?.getBoundingClientRect().bottom ?? window.innerHeight) - 120
      if (scroller && caretBottom > visibleBottom && t.selectionEnd === t.value.length) scroller.scrollTop += caretBottom - visibleBottom
    }
  }, [note.body])

  const edit = (changes: Partial<Note>) =>
    update((d) => ({ ...d, notes: d.notes.map((n) => (n.id === note.id ? { ...n, ...changes, updatedAt: Date.now() } : n)) }))
  // The cursor position to restore once React has put the new text in the textarea.
  const pendingCaret = useRef<number | null>(null)
  useLayoutEffect(() => {
    const t = body.current
    if (t && pendingCaret.current !== null) { t.focus(); t.setSelectionRange(pendingCaret.current, pendingCaret.current); pendingCaret.current = null }
  }, [note.body])
  const setBody = (text: string, caret: number) => {
    pendingCaret.current = caret
    edit({ body: text })
  }
  const makeList = (style: 'checklist' | 'bullets') => {
    const t = body.current
    if (!t) return
    const focused = document.activeElement === t
    let text = t.value
    let start = t.selectionStart, end = t.selectionEnd
    if (!focused) { if (text && !text.endsWith('\n')) text += '\n'; start = end = text.length }
    const r = toggleList(style, text, start, end)
    setBody(r.text, r.caret)
  }
  return (
    <>
      <div className="header plain" style={{ background: 'var(--bg)', justifyContent: 'space-between' }}>
        <button className="text-btn" style={{ fontSize: 17 }} onClick={onBack}>‹ Notes</button>
        <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
          <button className="icon-btn" aria-label={copied === note.id ? 'Copied' : 'Copy All'} title="Copy All" onClick={() => copy(note)}>{copied === note.id ? '✓' : '⧉'}</button>
          <button className="icon-btn" aria-label="Clear Note" title="Clear Note" disabled={!note.body} onClick={() => setConfirm('clear')}>⌫</button>
          <button className="icon-btn red" aria-label="Delete Note" title="Delete Note" onClick={() => setConfirm('delete')}>🗑︎</button>
        </div>
      </div>
      {confirm === 'clear' && <Alert title="Clear this note?" message="Everything you wrote is removed. The title stays." action="Clear"
        onCancel={() => setConfirm(null)} onConfirm={() => { edit({ body: '' }); setConfirm(null) }} />}
      {confirm === 'delete' && <Alert title="Delete this note?" message="This can't be undone." action="Delete"
        onCancel={() => setConfirm(null)} onConfirm={() => { update((d) => ({ ...d, notes: d.notes.filter((n) => n.id !== note.id) })); onBack() }} />}
      {/* Tapping the empty space below the text keeps writing at the end. */}
      <div className="note-editor" style={{ background: 'var(--bg)', minHeight: '100%' }}
        onFocus={() => setTyping(true)} onBlur={() => setTyping(false)}
        onClick={(e) => { if (e.target === e.currentTarget) { const t = body.current; t?.focus(); t?.setSelectionRange(t.value.length, t.value.length) } }}>
        <input autoFocus={!note.title && !note.body} placeholder="Title" value={note.title} onChange={(e) => edit({ title: e.target.value })} />
        {/* Checklist boxes and strikethrough are drawn by a copy of the text behind the (transparent) textarea. */}
        <div className="note-body">
          <div className="note-backdrop" aria-hidden>
            {note.body.split('\n').map((line, i) => {
              const kind = lineKind(line)
              return <div key={i}>{kind === 'plain' || kind === 'bullet' ? (line || '\u200b')
                : <><span className="box">{line[0]}</span> <span className={kind === 'checked' ? 'done' : ''}>{line.slice(2) || '\u200b'}</span></>}</div>
            })}
          </div>
          <textarea ref={body} placeholder="Start writing…" value={note.body} onChange={(e) => edit({ body: e.target.value })}
            onKeyDown={(e) => {
              const t = e.currentTarget
              if (t.selectionStart !== t.selectionEnd) return
              const r = e.key === 'Enter' ? checklistReturn(t.value, t.selectionStart) : e.key === ' ' ? autoBullet(t.value, t.selectionStart) : null
              if (!r) return
              e.preventDefault()
              setBody(r.text, r.caret)
            }}
            onClick={(e) => {
              // A click on a box (the first character of an item) checks it off.
              const t = e.currentTarget
              const at = t.selectionStart
              const [s] = lineBounds(t.value, at)
              if (t.selectionStart !== t.selectionEnd || at - s > 1) return
              const toggled = toggleItem(t.value, s)
              if (toggled !== null) setBody(toggled, s + 2)
            }} />
        </div>
      </div>
      {/* Floating above the keyboard: the checklist button, and while typing a checkmark that finishes. */}
      <div className="float-check-wrap">
        <button className="float-list" aria-label="Bulleted List" onMouseDown={(e) => e.preventDefault()} onClick={() => makeList('bullets')}>•≡</button>
        <button className="float-list" aria-label="Checklist" onMouseDown={(e) => e.preventDefault()} onClick={() => makeList('checklist')}>☑︎</button>
        {typing && <button className="float-check" aria-label="Done" onMouseDown={(e) => e.preventDefault()}
          onClick={() => (document.activeElement as HTMLElement | null)?.blur()}>✓</button>}
      </div>
    </>
  )
}
