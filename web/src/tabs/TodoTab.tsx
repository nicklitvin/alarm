import { useEffect, useState } from 'react'
import { SwipeRow } from '../components/SwipeRow'
import { BottomAction, DeadlineInputs, Section, Sheet, SuggestionChips, Switch, TabHeader, TimeOfDayChips } from '../components/ui'
import { dueDescription, dueSuggestions, isOverdue, roundTo5, sortTodos, uid, type Todo } from '../logic/model'
import { useStore } from '../logic/store'

export function TodoTab() {
  const { data, update, now, pending, clearPending } = useStore()
  const [editing, setEditing] = useState<Todo | null>(null)
  const [composing, setComposing] = useState(false)

  useEffect(() => {
    if (pending?.tab !== 'todos' || !pending.id) return
    const todo = data.todos.find((t) => t.id === pending.id)
    if (todo) setEditing(todo)
    clearPending()
  }, [pending, data.todos, clearPending])

  const open = sortTodos(data.todos.filter((t) => !t.isDone))
  const done = data.todos.filter((t) => t.isDone).sort((a, b) => (b.completedAt ?? 0) - (a.completedAt ?? 0))
  const day = (ms: number) => new Date(ms).toDateString()
  const tomorrow = new Date(now + 86_400_000).toDateString()
  const groups = [
    { title: 'Overdue', items: open.filter((t) => isOverdue(t, now)), red: true },
    { title: 'Today', items: open.filter((t) => t.due && !isOverdue(t, now) && day(t.due) === day(now)) },
    { title: 'Tomorrow', items: open.filter((t) => t.due && day(t.due) === tomorrow) },
    { title: 'Later', items: open.filter((t) => t.due && !isOverdue(t, now) && day(t.due) !== day(now) && day(t.due) !== tomorrow) },
    { title: '', items: open.filter((t) => !t.due) }, // no heading for to-dos without a deadline
  ].filter((g) => g.items.length)
  const overdue = open.filter((t) => isOverdue(t, now)).length
  const toggle = (id: string) => update((d) => ({
    ...d, todos: d.todos.map((t) => (t.id === id ? { ...t, isDone: !t.isDone, completedAt: t.isDone ? undefined : Date.now() } : t)),
  }))

  const row = (t: Todo) => {
    const late = isOverdue(t, now)
    return (
      <SwipeRow key={t.id} onClick={() => setEditing(t)}
        leading={{ label: t.isDone ? 'Undo' : 'Done', color: 'var(--orange)', onAction: () => toggle(t.id) }}
        trailing={{ label: 'Delete', color: 'var(--red)', onAction: () => update((d) => ({ ...d, todos: d.todos.filter((x) => x.id !== t.id) })) }}>
        <button className={`check ${t.isDone ? 'done' : late ? 'overdue' : ''}`} aria-label={t.isDone ? 'Mark as not done' : 'Mark as done'}
          onClick={(e) => { e.stopPropagation(); toggle(t.id) }}>{t.isDone ? '✓' : ''}</button>
        <div className="grow">
          <div style={{ textDecoration: t.isDone ? 'line-through' : undefined, color: t.isDone ? 'var(--secondary)' : undefined }}>{t.title}</div>
          {t.details.trim() && <div className="sub">{t.details}</div>}
          {t.due && !t.isDone && <div className={`sub due ${late ? 'red' : ''}`} style={{ fontSize: 12 }}><span>{late ? '⚠︎' : '🕒'}</span>{dueDescription(t.due, now)}</div>}
        </div>
      </SwipeRow>
    )
  }

  return (
    <>
      <TabHeader title="To-Do" tab="todos" detail={open.length ? (overdue ? `${overdue} overdue · ${open.length} left` : `${open.length} left`) : null} />
      {data.todos.length === 0 && !composing && <div className="talk-empty"><div className="big">☑︎</div><h3>Nothing To Do</h3>Tap New To-Do below.</div>}
      {groups.map((g) => <Section key={g.title || 'none'} header={g.title || undefined} headerClass={g.red ? 'red' : ''}>{g.items.map(row)}</Section>)}
      {done.length > 0 && (
        <Section header={<><span>Completed</span><button className="text-btn" style={{ fontSize: 13, textTransform: 'none' }} onClick={() => update((d) => ({ ...d, todos: d.todos.filter((t) => !t.isDone) }))}>Clear</button></>}>
          {done.map(row)}
        </Section>
      )}
      {composing ? <Composer onClose={() => setComposing(false)} /> : <BottomAction label="New To-Do" onClick={() => setComposing(true)} />}
      {editing && <TodoEditor todo={editing} onClose={() => setEditing(null)} />}
    </>
  )
}

function Composer({ onClose }: { onClose: () => void }) {
  const { update, now } = useStore()
  const [title, setTitle] = useState('')
  const [details, setDetails] = useState('')
  const [due, setDue] = useState<number | undefined>()
  const [custom, setCustom] = useState(false)
  const add = () => {
    if (!title.trim()) return
    update((d) => ({ ...d, todos: [...d.todos, { id: uid(), title: title.trim(), details: details.trim(), due, isDone: false, createdAt: Date.now() }] }))
    onClose() // the panel closes once the to-do is added
  }
  return (
    <div className="composer">
      <SuggestionChips value={due} onChange={setDue} onCustom={() => setCustom(true)} />
      <div className="box">
        <input ref={(el) => el?.focus({ preventScroll: true })} placeholder="New To-Do" value={title} onChange={(e) => setTitle(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && add()} />
        <input className="details" placeholder="Details (optional)" value={details} onChange={(e) => setDetails(e.target.value)} />
      </div>
      <div style={{ display: 'flex', gap: 10 }}>
        <button className="btn gray" onClick={onClose}>Cancel</button>
        <button className="btn prominent" style={{ flex: 1 }} disabled={!title.trim()} onClick={add}>＋ Add{due ? ` · ${dueDescription(due, now)}` : ''}</button>
      </div>
      {custom && <CustomDeadline value={due ?? dueSuggestions(now)[0].date} onClose={() => setCustom(false)} onPick={setDue} />}
    </div>
  )
}

function CustomDeadline({ value, onPick, onClose }: { value: number; onPick: (v: number) => void; onClose: () => void }) {
  const [date, setDate] = useState(roundTo5(value))
  return (
    <Sheet title="Deadline" medium onClose={onClose} left={<button onClick={onClose}>Cancel</button>}
      right={<button onClick={() => { onPick(date); onClose() }}>Set</button>}>
      <Section><div style={{ padding: 12 }}><TimeOfDayChips value={date} onChange={setDate} /></div><DeadlineInputs value={date} onChange={setDate} /></Section>
    </Sheet>
  )
}

function TodoEditor({ todo, onClose }: { todo: Todo; onClose: () => void }) {
  const { update, now } = useStore()
  const [draft, setDraft] = useState(todo)
  const [hasDeadline, setHasDeadline] = useState(todo.due !== undefined)
  const [deadline, setDeadline] = useState(todo.due ?? dueSuggestions(now)[0].date)
  const save = (changes: Partial<Todo> = {}) => {
    const saved = { ...draft, ...changes, due: hasDeadline ? deadline : undefined, details: draft.details.trim() }
    update((d) => ({ ...d, todos: d.todos.map((t) => (t.id === saved.id ? saved : t)) }))
    onClose()
  }
  return (
    <Sheet title="Edit To-Do" onClose={onClose} left={<button onClick={onClose}>Cancel</button>}
      right={<button disabled={!draft.title.trim()} onClick={() => save()}>Save</button>}>
      <Section>
        <div className="row"><input className="input" style={{ fontWeight: 500 }} value={draft.title} onChange={(e) => setDraft({ ...draft, title: e.target.value })} /></div>
        <div className="row"><input className="input" style={{ fontSize: 15, color: 'var(--secondary)' }} placeholder="Details (optional)" value={draft.details} onChange={(e) => setDraft({ ...draft, details: e.target.value })} /></div>
      </Section>
      <Section footer={hasDeadline ? `You'll get a notification at ${dueDescription(deadline, now)}.` : undefined}>
        <div className="row"><span className="grow">Deadline</span><Switch label="Deadline" on={hasDeadline} onChange={setHasDeadline} /></div>
        {hasDeadline && (
          <>
            <div className="row" style={{ display: 'block' }}><SuggestionChips value={deadline} onChange={(v) => v && setDeadline(v)} /></div>
            <DeadlineInputs value={deadline} onChange={setDeadline} />
            <div className="row" style={{ display: 'block' }}><TimeOfDayChips value={deadline} onChange={setDeadline} /></div>
          </>
        )}
      </Section>
      <Section>
        {/* Both actions on one line */}
        <div className="row" style={{ padding: 0, gap: 0 }}>
          <button className="tappable orange" style={{ flex: 1, padding: 12 }}
            onClick={() => save({ isDone: !draft.isDone, completedAt: draft.isDone ? undefined : Date.now() })}>
            {draft.isDone ? '↺ Not Done' : '✓ Mark as Done'}
          </button>
          <span style={{ width: 0.5, alignSelf: 'stretch', margin: '8px 0', background: 'var(--separator)' }} />
          <button className="tappable red" style={{ flex: 1, padding: 12 }}
            onClick={() => { update((d) => ({ ...d, todos: d.todos.filter((t) => t.id !== todo.id) })); onClose() }}>🗑 Delete</button>
        </div>
      </Section>
    </Sheet>
  )
}
