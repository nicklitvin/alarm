import { useEffect, useRef, useState } from 'react'
import { SwipeRow } from '../components/SwipeRow'
import { BottomAction, DeadlineInputs, Section, Sheet, Switch, TabHeader, TimeOfDayChips } from '../components/ui'
import { dueDescription, isOverdue, moveTodo, nextQuickTime, roundTo5, sortIndexForNew, todoSections, uid, type Todo } from '../logic/model'
import { useStore } from '../logic/store'

// A flat list on the gray background: each to-do is a checkbox and its text. New To-Do adds an
// empty row at the end (no pop-up); Return or tapping elsewhere finishes typing.
export function TodoTab() {
  const { data, update, now, pending, clearPending } = useStore()
  const [editing, setEditing] = useState<Todo | null>(null)
  const [editingDue, setEditingDue] = useState<Todo | null>(null)
  const [adding, setAdding] = useState(false)

  useEffect(() => {
    if (pending?.tab !== 'todos' || !pending.id) return
    const todo = data.todos.find((t) => t.id === pending.id)
    if (todo) setEditing(todo)
    clearPending()
  }, [pending, data.todos, clearPending])

  const sections = todoSections(data.todos)
  const open = [...sections.todos, ...sections.deadlines]
  const done = data.todos.filter((t) => t.isDone).sort((a, b) => (b.completedAt ?? 0) - (a.completedAt ?? 0))
  const overdue = open.filter((t) => isOverdue(t, now)).length
  const toggle = (id: string) => update((d) => ({
    ...d, todos: d.todos.map((t) => (t.id === id ? { ...t, isDone: !t.isDone, completedAt: t.isDone ? undefined : Date.now() } : t)),
  }))

  // Press and hold an open to-do, then drag it onto another to move it there.
  const [drag, setDrag] = useState<{ id: string; overId: string | null } | null>(null)
  const dragRef = useRef(drag)
  dragRef.current = drag
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
        update((s) => {
          // Only to-dos without a deadline are arranged by hand; deadlines stay soonest first.
          const places = moveTodo(s.todos.filter((t) => !t.isDone && t.due === undefined), id, overId)
          return { ...s, todos: s.todos.map((t) => (places.has(t.id) ? { ...t, sortIndex: places.get(t.id) } : t)) }
        })
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
  const order = sections.todos.map((t) => t.id)
  const dragClass = (t: Todo) => {
    if (!drag) return ''
    if (drag.id === t.id) return 'lifted'
    if (drag.overId !== t.id) return ''
    return order.indexOf(drag.id) < order.indexOf(t.id) ? 'drop-after' : 'drop-before'
  }

  const row = (t: Todo, draggable = false) => (
    <TodoRow key={t.id} todo={t} now={now} onToggle={() => toggle(t.id)} onDue={() => setEditingDue(t)} onDetails={() => setEditing(t)}
      dragClass={draggable ? dragClass(t) : ''} onHold={draggable ? () => setDrag({ id: t.id, overId: null }) : undefined}
      onDelete={() => update((d) => ({ ...d, todos: d.todos.filter((x) => x.id !== t.id) }))} />
  )

  return (
    <>
      <TabHeader title="To-Do" tab="todos" detail={open.length ? (overdue ? `${overdue} overdue · ${open.length} left` : `${open.length} left`) : null} />
      {data.todos.length === 0 && <div className="talk-empty"><div className="big">☑︎</div><h3>Nothing To Do</h3></div>}
      <div className="todo-flat">
        {sections.todos.map((t) => row(t, true))}
      </div>
      {sections.deadlines.length > 0 && (
        <div className="todo-flat">
          <div className="todo-flat-header"><span>Deadlines</span></div>
          {sections.deadlines.map((t) => row(t))}
        </div>
      )}
      {done.length > 0 && (
        <div className="todo-flat">
          <div className="todo-flat-header"><span>Completed</span>
            <button className="text-btn" onClick={() => update((d) => ({ ...d, todos: d.todos.filter((t) => !t.isDone) }))}>Clear</button></div>
          {done.map((t) => row(t))}
        </div>
      )}
      <BottomAction label="New To-Do" onClick={() => setAdding(true)} />
      {adding && <NewTodoSheet onClose={() => setAdding(false)} />}
      {editing && <TodoEditor todo={editing} onClose={() => setEditing(null)} />}
      {editingDue && <DueSheet todo={editingDue} onClose={() => setEditingDue(null)} />}
    </>
  )
}

/** New To-Do: a sheet like Add Alarm and New Timer, with Add To-Do at the bottom. */
function NewTodoSheet({ onClose }: { onClose: () => void }) {
  const { data, update, now } = useStore()
  const [title, setTitle] = useState('')
  const [details, setDetails] = useState('')
  const [hasDeadline, setHasDeadline] = useState(false)
  const [due, setDue] = useState(() => roundTo5(nextQuickTime(now, data.settings.todoQuickTimes)))
  const add = () => {
    if (!title.trim()) return
    update((d) => ({ ...d, todos: [...d.todos, { id: uid(), title: title.trim(), details: details.trim(), due: hasDeadline ? due : undefined, isDone: false, createdAt: Date.now(),
      sortIndex: sortIndexForNew(d.todos.filter((t) => !t.isDone), hasDeadline ? due : undefined) }] }))
    onClose()
  }
  return (
    <Sheet title="New To-Do" onClose={onClose} bottom={{ label: '＋ Add To-Do', onClick: add, disabled: !title.trim() }}>
      <Section>
        <div className="row"><input className="input" autoFocus style={{ fontWeight: 500 }} placeholder="Title" value={title}
          onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && add()} /></div>
        <div className="row"><input className="input" style={{ fontSize: 15, color: 'var(--secondary)' }} placeholder="Details (optional)" value={details} onChange={(e) => setDetails(e.target.value)} /></div>
      </Section>
      <Section footer={hasDeadline ? "You'll get a notification when it's due." : undefined}>
        <div className="row"><span className="grow">Deadline</span><Switch label="Deadline" on={hasDeadline} onChange={setHasDeadline} /></div>
        {hasDeadline && (
          <>
            <div className="row" style={{ display: 'block' }}><TimeOfDayChips value={due} onChange={setDue} /></div>
            <DeadlineInputs value={due} onChange={setDue} />
          </>
        )}
      </Section>
    </Sheet>
  )
}

/** Edit right in the list, like Reminders: tap to type, details underneath, 📅 opens the deadline sheet. */
function TodoRow({ todo, now, onToggle, onDelete, onDue, onDetails, onHold, dragClass = '' }: {
  todo: Todo; now: number; onToggle: () => void; onDelete: () => void; onDue: () => void; onDetails: () => void
  onHold?: () => void; dragClass?: string
}) {
  const { update } = useStore()
  const [editing, setEditing] = useState(false)
  const [title, setTitle] = useState(todo.title)
  const [details, setDetails] = useState(todo.details)
  const late = isOverdue(todo, now)

  useEffect(() => { if (!editing) { setTitle(todo.title); setDetails(todo.details) } }, [todo.title, todo.details, editing])

  const commit = () => {
    const t = title.trim()
    if (t && (t !== todo.title || details.trim() !== todo.details.trim())) {
      update((d) => ({ ...d, todos: d.todos.map((x) => (x.id === todo.id ? { ...x, title: t, details: details.trim() } : x)) }))
    } else if (!t) setTitle(todo.title)
    setEditing(false)
  }

  return (
    <SwipeRow className={`todo-item ${dragClass}`} dataId={todo.id} onHold={editing ? undefined : onHold} onClick={() => !editing && setEditing(true)}
      leading={{ label: todo.isDone ? 'Undo' : 'Done', color: 'var(--orange)', onAction: onToggle }}
      trailing={{ label: 'Delete', color: 'var(--red)', onAction: onDelete }}>
      <button className={`check ${todo.isDone ? 'done' : late ? 'overdue' : ''}`} aria-label={todo.isDone ? 'Mark as not done' : 'Mark as done'}
        onClick={(e) => { e.stopPropagation(); onToggle() }}>{todo.isDone ? '✓' : ''}</button>
      <div className="grow" onBlur={(e) => { if (editing && !e.currentTarget.parentElement?.contains(e.relatedTarget as Node)) commit() }}>
        {editing ? (
          <>
            <input className="todo-input" autoFocus value={title} placeholder="To-Do"
              onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && (e.currentTarget as HTMLInputElement).blur()} />
            <input className="todo-input details" value={details} placeholder="Add details"
              onChange={(e) => setDetails(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && (e.currentTarget as HTMLInputElement).blur()} />
          </>
        ) : (
          <>
            <div style={{ textDecoration: todo.isDone ? 'line-through' : undefined, color: todo.isDone ? 'var(--secondary)' : undefined }}>{todo.title}</div>
            {todo.details.trim() && <div className="sub">{todo.details}</div>}
          </>
        )}
        {todo.due && !todo.isDone && (
          <button className={`sub due ${late ? 'red' : ''}`} style={{ fontSize: 12 }} onClick={(e) => { e.stopPropagation(); onDue() }}>
            <span>{late ? '⚠︎' : '🕒'}</span>{dueDescription(todo.due, now)}
          </button>
        )}
      </div>
      {editing && (
        <button className="cal-btn" aria-label="Deadline and more" onMouseDown={(e) => e.preventDefault()}
          onClick={(e) => { e.stopPropagation(); commit(); onDetails() }}>📅</button>
      )}
    </SwipeRow>
  )
}

/** Tapping a to-do's time: a small sheet with just quick times, date and time. Saves as you go. */
function DueSheet({ todo, onClose }: { todo: Todo; onClose: () => void }) {
  const { data, update, now } = useStore()
  const live = data.todos.find((t) => t.id === todo.id) ?? todo
  const due = live.due ?? nextQuickTime(now, data.settings.todoQuickTimes)
  const setDue = (v: number) => update((d) => ({ ...d, todos: d.todos.map((t) => (t.id === todo.id ? { ...t, due: v } : t)) }))
  return (
    <Sheet title="" small onClose={onClose}>
      <Section>
        <div style={{ padding: 12 }}><TimeOfDayChips value={due} onChange={setDue} /></div>
        <DeadlineInputs value={due} onChange={setDue} />
      </Section>
    </Sheet>
  )
}

/** The 📅 sheet: deadline and the rest. Saves as you go; the trash icon deletes the to-do. */
function TodoEditor({ todo, onClose }: { todo: Todo; onClose: () => void }) {
  const { data, update, now } = useStore()
  const live = data.todos.find((t) => t.id === todo.id) ?? todo
  const [deadline, setDeadline] = useState(live.due ?? nextQuickTime(now, data.settings.todoQuickTimes))
  const change = (changes: Partial<Todo>) => update((d) => ({ ...d, todos: d.todos.map((t) => (t.id === todo.id ? { ...t, ...changes } : t)) }))
  const setDue = (v: number) => { setDeadline(v); change({ due: v }) }
  return (
    <Sheet title="Details" onClose={onClose}
      left={<button className="red" aria-label="Delete To-Do" onClick={() => { update((d) => ({ ...d, todos: d.todos.filter((t) => t.id !== todo.id) })); onClose() }}>🗑︎</button>}
      right={<button onClick={onClose}>Done</button>}>
      <Section>
        <div className="row"><input className="input" style={{ fontWeight: 500 }} value={live.title} onChange={(e) => change({ title: e.target.value })} /></div>
        <div className="row"><input className="input" style={{ fontSize: 15, color: 'var(--secondary)' }} placeholder="Details (optional)" value={live.details} onChange={(e) => change({ details: e.target.value })} /></div>
      </Section>
      <Section footer={live.due ? `You'll get a notification at ${dueDescription(live.due, now)}.` : undefined}>
        <div className="row"><span className="grow">Deadline</span>
          <Switch label="Deadline" on={live.due !== undefined} onChange={(on) => change({ due: on ? deadline : undefined })} /></div>
        {live.due !== undefined && (
          <>
            <DeadlineInputs value={live.due} onChange={setDue} />
            <div className="row" style={{ display: 'block' }}><TimeOfDayChips value={live.due} onChange={setDue} /></div>
          </>
        )}
      </Section>
    </Sheet>
  )
}
