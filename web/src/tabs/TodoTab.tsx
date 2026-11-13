import { useEffect, useState } from 'react'
import { SwipeRow } from '../components/SwipeRow'
import { BottomAction, DeadlineInputs, Section, Sheet, Switch, TabHeader, TimeOfDayChips } from '../components/ui'
import { dueDescription, isOverdue, nextQuickTime, roundTo5, sortTodos, uid, type Todo } from '../logic/model'
import { useStore } from '../logic/store'

// A flat list on the gray background: each to-do is a checkbox and its text. New To-Do adds an
// empty row at the end (no pop-up); Return or tapping elsewhere finishes typing.
export function TodoTab() {
  const { data, update, now, pending, clearPending } = useStore()
  const [editing, setEditing] = useState<Todo | null>(null)
  const [adding, setAdding] = useState(false)

  useEffect(() => {
    if (pending?.tab !== 'todos' || !pending.id) return
    const todo = data.todos.find((t) => t.id === pending.id)
    if (todo) setEditing(todo)
    clearPending()
  }, [pending, data.todos, clearPending])

  const open = sortTodos(data.todos.filter((t) => !t.isDone))
  const done = data.todos.filter((t) => t.isDone).sort((a, b) => (b.completedAt ?? 0) - (a.completedAt ?? 0))
  const overdue = open.filter((t) => isOverdue(t, now)).length
  const toggle = (id: string) => update((d) => ({
    ...d, todos: d.todos.map((t) => (t.id === id ? { ...t, isDone: !t.isDone, completedAt: t.isDone ? undefined : Date.now() } : t)),
  }))

  const row = (t: Todo, compact = false) => (
    <TodoRow key={t.id} todo={t} now={now} compact={compact} onToggle={() => toggle(t.id)} onDetails={() => setEditing(t)}
      onDelete={() => update((d) => ({ ...d, todos: d.todos.filter((x) => x.id !== t.id) }))} />
  )

  return (
    <>
      <TabHeader title="To-Do" tab="todos" detail={open.length ? (overdue ? `${overdue} overdue · ${open.length} left` : `${open.length} left`) : null} />
      {data.todos.length === 0 && !adding && <div className="talk-empty"><div className="big">☑︎</div><h3>Nothing To Do</h3>Tap New To-Do below.</div>}
      <div className="todo-flat">
        {open.map((t) => row(t))}
        {adding && <NewTodoRow onFinish={() => setAdding(false)} />}
      </div>
      {done.length > 0 && (
        <div className="todo-flat compact">
          <div className="todo-flat-header"><span>Completed</span>
            <button className="text-btn" onClick={() => update((d) => ({ ...d, todos: d.todos.filter((t) => !t.isDone) }))}>Clear</button></div>
          {done.map((t) => row(t, true))}
        </div>
      )}
      {!adding && <BottomAction label="New To-Do" onClick={() => setAdding(true)} />}
      {editing && <TodoEditor todo={editing} onClose={() => setEditing(null)} />}
    </>
  )
}

/** The empty row New To-Do adds. Saved when you finish typing; left empty, it goes away. */
function NewTodoRow({ onFinish }: { onFinish: () => void }) {
  const { update, now, data } = useStore()
  const [title, setTitle] = useState('')
  const [details, setDetails] = useState('')
  const [due, setDue] = useState<number | undefined>()
  const [picking, setPicking] = useState(false)
  const finish = () => {
    if (title.trim()) update((d) => ({ ...d, todos: [...d.todos, { id: uid(), title: title.trim(), details: details.trim(), due, isDone: false, createdAt: Date.now() }] }))
    onFinish()
  }
  return (
    <div className="todo-item" onBlur={(e) => { if (!picking && !e.currentTarget.contains(e.relatedTarget as Node)) finish() }}>
      <span className="check" style={{ opacity: 0.5 }} />
      <div className="grow">
        <input className="todo-input" autoFocus value={title} placeholder="New To-Do"
          onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && (e.currentTarget as HTMLInputElement).blur()} />
        <input className="todo-input details" value={details} placeholder="Add details"
          onChange={(e) => setDetails(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && (e.currentTarget as HTMLInputElement).blur()} />
        {due && <div className="sub due" style={{ fontSize: 12 }}><span>🕒</span>{dueDescription(due, now)}</div>}
      </div>
      <button className="cal-btn" aria-label="Deadline" onMouseDown={(e) => { e.preventDefault(); setPicking(true) }}>📅</button>
      {picking && <CustomDeadline value={due ?? nextQuickTime(now, data.settings.todoQuickTimes)}
        onPick={(v) => setDue(v)} onClose={() => setPicking(false)} />}
    </div>
  )
}

function CustomDeadline({ value, onPick, onClose }: { value: number; onPick: (v: number | undefined) => void; onClose: () => void }) {
  const [date, setDate] = useState(roundTo5(value))
  return (
    <Sheet title="Deadline" medium onClose={onClose} left={<button onClick={onClose}>Cancel</button>}
      right={<button onClick={() => { onPick(date); onClose() }}>Set</button>}>
      <Section><div style={{ padding: 12 }}><TimeOfDayChips value={date} onChange={setDate} /></div><DeadlineInputs value={date} onChange={setDate} /></Section>
    </Sheet>
  )
}

/** Edit right in the list, like Reminders: tap to type, details underneath, 📅 opens the deadline sheet. */
function TodoRow({ todo, now, compact, onToggle, onDelete, onDetails }: {
  todo: Todo; now: number; compact: boolean; onToggle: () => void; onDelete: () => void; onDetails: () => void
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
    <SwipeRow className={`todo-item ${compact ? 'compact' : ''}`} onClick={() => !editing && setEditing(true)}
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
          <button className={`sub due ${late ? 'red' : ''}`} style={{ fontSize: 12 }} onClick={(e) => { e.stopPropagation(); onDetails() }}>
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
