import { useEffect, useState } from 'react'
import { BottomAction, Section, TabHeader } from '../components/ui'
import { noteCopyText, notePreview, noteTitle, sortNotes, uid, type Note } from '../logic/model'
import { useStore } from '../logic/store'

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
  const [reordering, setReordering] = useState(false)
  const [dragID, setDragID] = useState<string | null>(null)
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
  const canReorder = sort === 'manual' && !q

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

  const moveBefore = (dragged: string, target: string) => setNotes((ns) => {
    const order = sortNotes(ns, 'manual').map((n) => n.id).filter((id) => id !== dragged)
    order.splice(order.indexOf(target), 0, dragged)
    return ns.map((n) => ({ ...n, sortIndex: order.indexOf(n.id) }))
  })

  const row = (n: Note) => (
    <div key={n.id} className="row tappable" draggable={reordering}
      onDragStart={() => setDragID(n.id)} onDragOver={(e) => reordering && e.preventDefault()}
      onDrop={() => { if (dragID && dragID !== n.id) moveBefore(dragID, n.id); setDragID(null) }}
      onClick={() => !reordering && setOpenID(n.id)}>
      <div className="grow">
        <div className="ellipsis" style={{ fontWeight: 600 }}>{noteTitle(n)}</div>
        <div className="sub ellipsis">{ago(n.updatedAt, now)} <span style={{ color: 'var(--tertiary)' }}>{notePreview(n)}</span></div>
      </div>
      {reordering ? <span className="drag">≡</span> : (
        <>
          <button className="muted" title={n.isPinned ? 'Unpin' : 'Pin to top'} aria-label={n.isPinned ? 'Unpin' : 'Pin'}
            onClick={(e) => { e.stopPropagation(); setNotes((ns) => ns.map((x) => (x.id === n.id ? { ...x, isPinned: !x.isPinned } : x))) }} style={{ opacity: n.isPinned ? 1 : 0.25, filter: n.isPinned ? undefined : 'grayscale(1)' }}>📌</button>
          <button className="copy-btn" aria-label="Copy All" onClick={(e) => { e.stopPropagation(); copy(n) }}>{copied === n.id ? '✓' : '⧉'}</button>
        </>
      )}
    </div>
  )

  const pinned = visible.filter((n) => n.isPinned)
  const others = visible.filter((n) => !n.isPinned)
  return (
    <>
      <TabHeader title="Notes" tab="notes" detail={data.notes.length ? `${data.notes.length} note${data.notes.length === 1 ? '' : 's'}` : null}
        accessory={canReorder && data.notes.length > 1 ? <button className="text-btn" onClick={() => setReordering(!reordering)}>{reordering ? 'Done' : 'Reorder'}</button> : null} />
      <div style={{ padding: '0 20px 10px', position: 'sticky', top: 52, zIndex: 19, background: 'var(--bg-grouped)' }}>
        <div className="field"><span className="muted">⌕</span><input placeholder="Search Notes" value={query} onChange={(e) => setQuery(e.target.value)} /></div>
      </div>
      {reordering && <div className="section-footer" style={{ marginBottom: 10 }}>Drag notes to rearrange. Pinned notes stay on top.</div>}
      {pinned.length > 0 && <Section header="Pinned">{pinned.map(row)}</Section>}
      {others.length > 0 && <Section header={pinned.length ? 'Notes' : undefined}>{others.map(row)}</Section>}
      {data.notes.length === 0 && <div className="talk-empty" style={{ paddingTop: 80 }}><div className="big">🗒</div><h3>No Notes</h3>Tap New Note below.</div>}
      {data.notes.length > 0 && visible.length === 0 && <div className="talk-empty" style={{ paddingTop: 60 }}>No results for “{query}”</div>}
      {!reordering && <BottomAction label="New Note" onClick={newNote} />}
    </>
  )
}

function NoteEditor({ note, onBack }: { note: Note; onBack: () => void }) {
  const { update } = useStore()
  const { copied, copy } = useCopy()
  const edit = (changes: Partial<Note>) =>
    update((d) => ({ ...d, notes: d.notes.map((n) => (n.id === note.id ? { ...n, ...changes, updatedAt: Date.now() } : n)) }))
  return (
    <>
      <div className="header plain" style={{ background: 'var(--bg)', justifyContent: 'space-between' }}>
        <button className="text-btn" style={{ fontSize: 17 }} onClick={onBack}>‹ Notes</button>
        <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
          <button className="icon-btn" aria-label={copied === note.id ? 'Copied' : 'Copy All'} title="Copy All" onClick={() => copy(note)}>{copied === note.id ? '✓' : '⧉'}</button>
          <button className="icon-btn red" aria-label="Delete Note" title="Delete Note" onClick={() => {
            if (!confirm('Delete this note?')) return
            update((d) => ({ ...d, notes: d.notes.filter((n) => n.id !== note.id) }))
            onBack()
          }}>🗑︎</button>
        </div>
      </div>
      <div className="note-editor" style={{ background: 'var(--bg)', minHeight: '100%' }}>
        <input autoFocus={!note.title && !note.body} placeholder="Title" value={note.title} onChange={(e) => edit({ title: e.target.value })} />
        <div className="muted" style={{ fontSize: 12 }}>Edited {new Date(note.updatedAt).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })}</div>
        <textarea placeholder="Start writing…" value={note.body} onChange={(e) => edit({ body: e.target.value })} />
      </div>
    </>
  )
}
