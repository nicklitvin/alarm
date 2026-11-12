import {
  alarmTitle, clock, countdown, dayDescription, dueDescription, durationName, isOverdue, nextAlarm, timeOf, timeParts, upNext, type UpNextItem,
} from '../logic/model'
import { useStore, type Link } from '../logic/store'

const linkFor = (item: UpNextItem): Link => {
  switch (item.kind) {
    case 'alarmSoon': case 'nextAlarm': return { tab: 'alarms', id: item.alarm.id }
    case 'timer': return { tab: 'timers' }
    case 'todo': return { tab: 'todos', id: item.todo.id }
  }
}

/** Lock screen + home screen widgets, using the same data and rules as the app's widgets. */
export function Widgets() {
  const { data, update, now, open, setAskOpen } = useStore()
  const next = nextAlarm(data.alarms, now)
  const within24h = next && next.date - now <= 24 * 3600_000 ? next : undefined
  const items = upNext(data.alarms, data.todos, data.timers, now, data.settings.alarmHeadsUpMinutes)
  const d = new Date(now)

  const dismiss = (id: string, date: number) => update((s) => ({ ...s, alarms: s.alarms.map((a) => (a.id === id ? (a.weekdays.length ? { ...a, skippedOccurrence: date } : { ...a, isEnabled: false }) : a)) }))
  const complete = (id: string) => update((s) => ({ ...s, todos: s.todos.map((t) => (t.id === id ? { ...t, isDone: true, completedAt: Date.now() } : t)) }))

  const row = (item: UpNextItem, compact = false) => {
    const key = item.kind + ('alarm' in item ? item.alarm.id : item.kind === 'timer' ? item.timer.id : item.todo.id)
    let icon = '⏰', title = '', sub = '', subRed = false, trailing = null as React.ReactNode
    switch (item.kind) {
      case 'alarmSoon':
        title = `${alarmTitle(item.alarm)} · ${timeOf(item.date)}`; sub = `Rings in ${Math.max(1, Math.ceil((item.date - now) / 60000))} min`
        trailing = <button className="mini" onClick={(e) => { e.stopPropagation(); dismiss(item.alarm.id, item.date) }}>Dismiss</button>
        break
      case 'timer': {
        const t = item.timer
        icon = t.state === 'ringing' ? '🔔' : '⏱'; title = t.label || durationName(t.duration)
        sub = t.state === 'running' && t.fireDate > now ? clock((t.fireDate - now) / 1000) : t.state === 'paused' ? `Paused · ${clock(t.remaining)}` : "Time's up"
        break
      }
      case 'todo': {
        const t = item.todo
        icon = ''; title = t.title; subRed = isOverdue(t, now)
        sub = t.due ? `${subRed ? 'Overdue · ' : 'Due '}${dueDescription(t.due, now)}` : t.details
        break
      }
      case 'nextAlarm':
        icon = '⏰'; title = `${alarmTitle(item.alarm)} · ${dueDescription(item.date, now)}`; sub = `in ${countdown(now, item.date)}`
        break
    }
    return (
      <div className="widget-row" key={key} onClick={(e) => { e.stopPropagation(); open(linkFor(item)) }}>
        {item.kind === 'todo'
          ? <button className={`check ${subRed ? 'overdue' : ''}`} style={{ width: 20, height: 20 }} aria-label="Complete" onClick={(e) => { e.stopPropagation(); complete(item.todo.id) }} />
          : <span style={{ width: 20, textAlign: 'center' }}>{icon}</span>}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="t ellipsis" style={{ fontSize: compact ? 13 : 14 }}>{title}</div>
          {sub && <div className={`s ellipsis ${subRed ? 'red' : ''}`}>{sub}</div>}
        </div>
        {!compact && trailing}
      </div>
    )
  }

  const first = items[0]
  return (
    <>
      <div>
        <h2>Lock Screen</h2>
        <div className="lock">
          <div className="date">{d.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' })}</div>
          <div className="acc-inline">{within24h ? `⏰ ${dayDescription(within24h.date, now) === 'Today' ? '' : d.toLocaleDateString([], { weekday: 'short' }) + ' '}${timeOf(within24h.date)}` : 'zzz  No alarm today'}</div>
          <div className="big-time">{timeParts(d.getHours(), d.getMinutes()).time}</div>
          <div className="lock-row">
            <button className="acc-circle" onClick={() => open(next ? { tab: 'alarms', id: next.alarm.id } : { tab: 'alarms' })} aria-label="Next alarm">
              {within24h ? <div><div style={{ fontSize: 11 }}>⏰</div><div style={{ fontSize: 17 }}>{timeParts(new Date(within24h.date).getHours(), new Date(within24h.date).getMinutes()).time}</div><div style={{ fontSize: 9, opacity: 0.8 }}>{timeParts(new Date(within24h.date).getHours(), 0).period}</div></div>
                : <div style={{ fontSize: 22 }}>zzz</div>}
            </button>
            <button className="acc-rect" onClick={() => open(first ? linkFor(first) : { tab: 'todos' })}>
              {first ? <>{row(first, true)}</> : <><b>Up Next</b><span className="t">All clear</span></>}
            </button>
          </div>
        </div>
        <p>Lock screen widgets show zzz when no alarm rings in the next 24 hours.</p>
      </div>

      <div>
        <h2>Home Screen</h2>
        <div className="home">
          <div className="widgets">
            <div className="widget" onClick={() => open(next ? { tab: 'alarms', id: next.alarm.id } : { tab: 'alarms' })}>
              <div className="wh"><span>⏰</span><span className="muted" style={{ fontSize: 12 }}>{next ? dayDescription(next.date, now) : ''}</span></div>
              {next ? (
                <>
                  <div className="big">{timeParts(new Date(next.date).getHours(), new Date(next.date).getMinutes()).time}<small> {timeParts(new Date(next.date).getHours(), 0).period}</small></div>
                  <div style={{ fontSize: 14, fontWeight: 500 }} className="ellipsis">{alarmTitle(next.alarm)}</div>
                  <div className="muted" style={{ fontSize: 12 }}>in {countdown(now, next.date)}</div>
                </>
              ) : <div className="big" style={{ fontSize: 20 }}>No Alarms</div>}
            </div>
            <div className="widget" onClick={() => open(first ? linkFor(first) : { tab: 'todos' })}>
              <div className="wh"><span>Up Next</span></div>
              {first ? row(first, true) : <div style={{ marginTop: 10 }}><b>All clear</b></div>}
              <div className="foot"><span>{items.length > 1 ? `+${items.length - 1} more` : ''}</span>
                <button className="ask" aria-label="Ask Assistant" onClick={(e) => { e.stopPropagation(); setAskOpen(true) }}>✦</button></div>
            </div>
            <div className="widget medium" onClick={() => open(first ? linkFor(first) : { tab: 'todos' })}>
              <div className="wh"><span>✦ Up Next</span></div>
              {items.length === 0 ? <div style={{ marginTop: 10 }}><b>All clear</b><div className="muted" style={{ fontSize: 12 }}>Nothing coming up.</div></div> : items.slice(0, 2).map((i) => row(i))}
              <div className="foot"><span>{items.length > 2 ? `+${items.length - 2} more` : ''}</span>
                <button className="ask" aria-label="Ask Assistant" onClick={(e) => { e.stopPropagation(); setAskOpen(true) }}>✦</button></div>
            </div>
          </div>
        </div>
        <p>Tap a widget item to open it in the phone. Tap a to-do's circle to complete it, or ✦ to ask the assistant from the top of the screen.</p>
      </div>
    </>
  )
}
