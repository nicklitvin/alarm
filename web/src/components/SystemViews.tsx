import { useState, type ReactNode } from 'react'
import {
  alarmTitle, clock, countdown, dayDescription, dueDescription, durationName, isOverdue, leadTimeName, nextAlarm, nextFire,
  timeOf, timeParts, upNext, upNextLayout, type Alarm, type TimerItem, type Todo, type UpNextItem,
} from '../logic/model'
import { useStore, type Link } from '../logic/store'
import { useAsk } from '../tabs/TalkTab'

// Previews of everything the app shows outside itself: widgets, lock screen, notifications,
// Live Activities, Control Center and the ringing alarm. They use the preview's real data and
// their buttons work, but nothing here is a real iOS surface.

const SECTIONS: { id: string; label: string; view: () => ReactNode }[] = [
  { id: 'home', label: 'Home Screen', view: () => <HomeScreen /> },
  { id: 'lock', label: 'Lock Screen', view: () => <LockScreen /> },
  { id: 'notifications', label: 'Notifications', view: () => <Notifications /> },
  { id: 'live', label: 'Live Activity', view: () => <LiveActivity /> },
  { id: 'control', label: 'Control Center', view: () => <ControlCenter /> },
  { id: 'ringing', label: 'Alarm Ringing', view: () => <Ringing /> },
]

const linkFor = (item: UpNextItem): Link => {
  switch (item.kind) {
    case 'alarmSoon': case 'nextAlarm': return { tab: 'alarms' }
    case 'timer': return { tab: 'timers' }
    case 'todo': return { tab: 'todos' }
  }
}

/** Shared data and actions for all the views. */
function useSystem() {
  const store = useStore()
  const { data, update, now } = store
  const next = nextAlarm(data.alarms, now)
  const within24h = next && next.date - now <= 24 * 3600_000 ? next : undefined
  const items = upNext(data.alarms, data.todos, data.timers, now, data.settings)
  const dismiss = (id: string, date: number) => update((s) => ({
    ...s, alarms: s.alarms.map((a) => (a.id === id ? (a.weekdays.length ? { ...a, skippedOccurrence: date } : { ...a, isEnabled: false }) : a)),
  }))
  const complete = (id: string) => update((s) => ({ ...s, todos: s.todos.map((t) => (t.id === id ? { ...t, isDone: true, completedAt: Date.now() } : t)) }))
  const snooze = (id: string, by: number) => update((s) => ({ ...s, todos: s.todos.map((t) => (t.id === id ? { ...t, due: Date.now() + by, isDone: false } : t)) }))
  const setTimer = (id: string, change: (t: TimerItem) => TimerItem | null) =>
    update((s) => ({ ...s, timers: s.timers.flatMap((t) => (t.id === id ? (change(t) ?? []) : [t])) }))
  return { ...store, next, within24h, items, dismiss, complete, snooze, setTimer }
}

/** Every system view, one after another in a long list. */
export function SystemViews() {
  return (
    <div className="system-list">
      {SECTIONS.map((section) => (
        <section key={section.id} id={section.id} className="system-section">
          <h2>{section.label}</h2>
          {section.view()}
        </section>
      ))}
    </div>
  )
}

// MARK: - Shared row

function Row({ item, compact = false, light = false }: { item: UpNextItem; compact?: boolean; light?: boolean }) {
  const { now, open, dismiss, complete } = useSystem()
  let icon = '⏰', title = '', sub = '', subRed = false, trailing: ReactNode = null
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
      title = `${alarmTitle(item.alarm)} · ${dueDescription(item.date, now)}`; sub = `in ${countdown(now, item.date)}`
      break
  }
  const done = item.kind === 'todo' && item.todo.isDone
  return (
    <div className={`widget-row ${light ? 'on-wallpaper' : ''}`} onClick={(e) => { e.stopPropagation(); open(linkFor(item)) }}>
      {item.kind === 'todo'
        ? <button className={`check ${done ? 'done' : subRed ? 'overdue' : ''}`} style={{ width: 20, height: 20, fontSize: 11 }} aria-label="Complete"
            onClick={(e) => { e.stopPropagation(); complete(item.todo.id) }}>{done ? '✓' : ''}</button>
        : <span style={{ width: 20, textAlign: 'center' }}>{icon}</span>}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="t ellipsis" style={{ fontSize: compact ? 13 : 14, textDecoration: done ? 'line-through' : undefined, opacity: done ? 0.6 : 1 }}>{title}</div>
        {sub && <div className={`s ellipsis ${subRed ? 'red' : ''}`}>{sub}</div>}
      </div>
      {!compact && trailing}
    </div>
  )
}

const Caption = ({ children }: { children: ReactNode }) => <p className="view-caption">{children}</p>

function bigTime(date: number) {
  const d = new Date(date)
  return timeParts(d.getHours(), d.getMinutes())
}

// MARK: - Home Screen

function HomeScreen() {
  const { now, next, items, open, dismiss } = useSystem()
  const first = items[0]
  const todoCount = items.filter((i) => i.kind === 'todo' && !i.todo.isDone).length
  const layout = upNextLayout(items, now)
  const featured = layout.alarm
  // Variant B: the next alarm on top (within 24 hours) with Dismiss on its line, then the rest;
  // the Live Talk waveform in the bottom-right corner. Every tap opens the tab.
  const alarmHeader = (stacked: boolean) => featured && (
    <div className={`v-top ${stacked ? 'stacked' : ''}`}>
      <div className="v-alarm" onClick={(e) => { e.stopPropagation(); open({ tab: 'alarms' }) }}>
        {/* One line on medium and large ("7:00 AM  ⏰ Wake up · Tomorrow"); stacked on small. */}
        {/* "⏰ 7:00 AM  in 2h 4m": the clock before the time, the label only if it has one. */}
        <div className={stacked ? '' : 'v-alarm-line'}>
          {!stacked && <span className="v-alarm-icon">⏰</span>}
          <div className="v-alarm-time">{bigTime(featured.date).time}<small> {bigTime(featured.date).period}</small></div>
          <div className="v-alarm-sub ellipsis">{featured.alarm.label.trim() ? `${featured.alarm.label.trim()} · ` : ''}in {countdown(now, featured.date)}</div>
        </div>
      </div>
      {/* One skipped ring per alarm: once dismissed, the ring after it can't be dismissed too. */}
      {(featured.alarm.skippedOccurrence ?? 0) <= now &&
        <button className="mini dismiss" onClick={(e) => { e.stopPropagation(); dismiss(featured.alarm.id, featured.date) }}>Dismiss</button>}
    </div>
  )
  const upNextWidget = (size: 'small' | 'medium' | 'large') => {
    // As many rows as fit, measuring each: one-line to-dos take less room than two-line rows.
    const space = (size === 'medium' ? 142 : 332) - (featured ? 66 : 22)
    const twoLines = (i: UpNextItem) => i.kind !== 'todo' || !!i.todo.due || !!i.todo.details.trim()
    const shown: UpNextItem[] = []
    let used = 0
    for (const r of layout.rows) {
      const h = twoLines(r) ? 37 : 26
      if (used + h > space && shown.length) break
      used += h
      shown.push(r)
    }
    if (size === 'small') {
      return (
        <div className="widget upnext small" onClick={() => open(featured ? { tab: 'alarms' } : first ? linkFor(first) : { tab: 'todos' })}>
          {featured ? (
            // Fills the widget like Next Alarm: day, big time, label, then a full-width Dismiss.
            <div className="small-alarm">
              <div className="wh"><span>⏰</span><span className="muted" style={{ fontSize: 12 }}>in {countdown(now, featured.date)}</span></div>
              <div className="big">{bigTime(featured.date).time}<small> {bigTime(featured.date).period}</small></div>
              {featured.alarm.label.trim() && <div className="muted ellipsis" style={{ fontSize: 14, fontWeight: 500 }}>{featured.alarm.label.trim()}</div>}
              {(featured.alarm.skippedOccurrence ?? 0) <= now &&
                <button className="dismiss-full" onClick={(e) => { e.stopPropagation(); dismiss(featured.alarm.id, featured.date) }}>Dismiss</button>}
            </div>
          ) : (
            <>
              <div className="wh"><span>Up Next{todoCount > 0 && <span className="count"> {todoCount} to-do{todoCount === 1 ? '' : 's'}</span>}</span></div>
              {first ? <Row item={first} compact /> : <div style={{ marginTop: 10 }}><b>All clear</b></div>}
            </>
          )}
        </div>
      )
    }
    return (
      <div className={`widget upnext ${size}`} onClick={() => open(featured ? { tab: 'alarms' } : first ? linkFor(first) : { tab: 'todos' })}>
        {featured && <>{alarmHeader(false)}<div className="v-divider" /></>}
        <div className={`wh ${featured ? 'small' : ''}`}><span>{featured ? 'To-Do' : 'Up Next'}{todoCount > 0 && <span className="count"> {todoCount} to-do{todoCount === 1 ? '' : 's'}</span>}</span></div>
        {shown.length === 0 ? <div style={{ marginTop: 6 }}>{featured ? <span className="muted" style={{ fontSize: 12 }}>Nothing to do.</span> : <><b>All clear</b><div className="muted" style={{ fontSize: 12 }}>Nothing coming up.</div></>}</div>
          : shown.map((i, n) => <div key={keyOf(i)} style={{ paddingRight: n === shown.length - 1 ? 40 : 0 }}><Row item={i} /></div>)}
        <button className="ask corner" aria-label="Open Talk" onClick={(e) => { e.stopPropagation(); open({ tab: 'talk' }) }}>〰︎</button>
      </div>
    )
  }
  return (
    <>
      <div className="home">
        <div className="widgets">
          <div className="widget" onClick={() => open(next ? { tab: 'alarms' } : { tab: 'alarms' })}>
            <div className="wh"><span>⏰</span><span className="muted" style={{ fontSize: 12 }}>{next ? dayDescription(next.date, now) : ''}</span></div>
            {next ? (
              <>
                <div className="big">{bigTime(next.date).time}<small> {bigTime(next.date).period}</small></div>
                <div style={{ fontSize: 14, fontWeight: 500 }} className="ellipsis">{alarmTitle(next.alarm)}</div>
                <div className="muted" style={{ fontSize: 12 }}>in {countdown(now, next.date)}</div>
              </>
            ) : <div className="big" style={{ fontSize: 20 }}>No Alarms</div>}
          </div>
          {upNextWidget('small')}
          {upNextWidget('medium')}
          {upNextWidget('large')}
        </div>
      </div>
      <Caption>Next Alarm (small) and Up Next (small, medium, large). Your next alarm always sits on top, however far away, with a Dismiss button for that ring; to-dos and timers follow. Tapping anything opens its tab, a to-do's circle checks it off, and the waveform button opens Talk.</Caption>
    </>
  )
}

const keyOf = (i: UpNextItem) => i.kind + ('alarm' in i ? i.alarm.id : i.kind === 'timer' ? i.timer.id : i.todo.id)

// MARK: - Lock Screen

function LockScreen() {
  const { now, next, within24h, items, open, data } = useSystem()
  const [showZzz, setShowZzz] = useState(false)
  const soon = showZzz ? undefined : within24h
  const first = items[0]
  const d = new Date(now)
  const timer = data.timers.find((t) => t.state !== 'ringing')
  return (
    <>
      <div className="lock">
        <div className="date">{d.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' })}</div>
        <div className="acc-inline">{soon ? `⏰ ${dayDescription(soon.date, now) === 'Today' ? '' : new Date(soon.date).toLocaleDateString([], { weekday: 'short' }) + ' '}${timeOf(soon.date)}` : 'zzz  No alarm today'}</div>
        <div className="big-time">{timeParts(d.getHours(), d.getMinutes()).time}</div>
        <div className="lock-row">
          <button className="acc-circle" onClick={() => open(next ? { tab: 'alarms' } : { tab: 'alarms' })} aria-label="Next alarm">
            {soon ? <div><div style={{ fontSize: 11 }}>⏰</div><div style={{ fontSize: 17 }}>{bigTime(soon.date).time}</div><div style={{ fontSize: 9, opacity: 0.8 }}>{bigTime(soon.date).period}</div></div>
              : <div style={{ fontSize: 22 }}>zzz</div>}
          </button>
          <button className="acc-rect" onClick={() => open(first ? linkFor(first) : { tab: 'todos' })}>
            {first ? <Row item={first} compact light /> : <><b>Up Next</b><span className="t">All clear</span></>}
          </button>
        </div>
        <div className="lock-row" style={{ marginTop: 10 }}>
          <button className="acc-rect wide" onClick={() => open(next ? { tab: 'alarms' } : { tab: 'alarms' })}>
            {soon ? (
              <>
                <b>⏰ {alarmTitle(soon.alarm)}</b>
                <span className="t" style={{ fontSize: 26, fontWeight: 600 }}>{bigTime(soon.date).time} <small style={{ fontSize: 14 }}>{bigTime(soon.date).period}</small></span>
                <span className="s">{dayDescription(soon.date, now)} · in {countdown(now, soon.date)}</span>
              </>
            ) : <span style={{ display: 'flex', gap: 8, alignItems: 'center' }}><span style={{ fontSize: 24 }}>zzz</span><span className="s">{next ? 'No alarm in the next 24 hours' : 'No alarms'}</span></span>}
          </button>
        </div>
        {timer && <div style={{ marginTop: 14 }}><TimerLockActivity timer={timer} /></div>}
      </div>
      <div className="panel-actions">
        <button className={`pill ${showZzz ? 'active' : ''}`} onClick={() => setShowZzz(!showZzz)}>{showZzz ? 'Showing: no alarm within 24 h' : 'Show the zzz state'}</button>
      </div>
      <Caption>Inline text above the clock, Next Alarm (circular and rectangular) and Up Next (rectangular). They show zzz when no alarm rings in the next 24 hours.{timer ? ' The running timer shows as a Live Activity.' : ''}</Caption>
    </>
  )
}

// MARK: - Notifications

function Notifications() {
  const { data, now, open, dismiss, complete, snooze } = useSystem()
  const [expanded, setExpanded] = useState<'alarm' | 'todo' | null>(null)
  const s = data.settings

  // The heads-up for the next enabled alarm (or an example if there are none).
  const alarmWithRing = data.alarms
    .map((a) => ({ a, t: nextFire(a, now) }))
    .filter((x): x is { a: Alarm; t: number } => x.t !== undefined)
    .sort((x, y) => x.t - y.t)[0]
  const alarm = alarmWithRing?.a
  const ring = alarmWithRing?.t ?? now + 3600_000
  const todo: Todo | undefined = data.todos.find((t) => !t.isDone && t.due !== undefined)

  // Tapping opens the Alarms tab, where the Dismiss card is already showing.
  const tapAlarm = () => open({ tab: 'alarms' })

  return (
    <>
      <div className="lock notif-wall">
        <div className="date">{new Date(now).toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' })}</div>
        <div className="big-time" style={{ fontSize: 64 }}>{timeParts(new Date(now).getHours(), new Date(now).getMinutes()).time}</div>

        {/* Alarm heads-up */}
        <div className={`notif ${expanded === 'alarm' ? 'expanded' : ''}`}>
          <button className="notif-body" onClick={tapAlarm} onContextMenu={(e) => { e.preventDefault(); setExpanded('alarm') }}>
            <img src="/icon.png" alt="" />
            <div className="notif-text">
              <div className="notif-top"><b>Alarm in {ring - now < s.alarmHeadsUpMinutes * 60_000 ? `${Math.max(1, Math.ceil((ring - now) / 60_000))} min` : leadTimeName(s.alarmHeadsUpMinutes)}</b><span>now</span></div>
              {alarm?.label && <div className="notif-sub">{alarmTitle(alarm)}</div>}
              <div>Rings at {timeOf(ring)}</div>
            </div>
          </button>
          {expanded === 'alarm' && (
            <div className="notif-actions">
              <button className="red" onClick={() => { if (alarm) dismiss(alarm.id, ring); setExpanded(null) }}>🔕 Dismiss Alarm</button>
            </div>
          )}
        </div>

        {/* To-do due */}
        {todo && todo.due !== undefined && s.todoDueAlertEnabled && (
          <div className={`notif ${expanded === 'todo' ? 'expanded' : ''}`}>
            <button className="notif-body" onClick={() => open({ tab: 'todos', id: todo.id })} onContextMenu={(e) => { e.preventDefault(); setExpanded('todo') }}>
              <img src="/icon.png" alt="" />
              <div className="notif-text">
                <div className="notif-top"><b>{todo.title}</b><span>{isOverdue(todo, now) ? 'earlier' : dueDescription(todo.due, now)}</span></div>
                <div>Due now · {timeOf(todo.due)}{todo.details.trim() ? `\n${todo.details}` : ''}</div>
              </div>
            </button>
            {expanded === 'todo' && (
              <div className="notif-actions">
                <button onClick={() => { complete(todo.id); setExpanded(null) }}>✓ Mark as Done</button>
                <button onClick={() => { snooze(todo.id, 3600_000); setExpanded(null) }}>↻ Remind Me in 1 Hour</button>
                <button onClick={() => { snooze(todo.id, 24 * 3600_000); setExpanded(null) }}>☀︎ Remind Me Tomorrow</button>
              </div>
            )}
          </div>
        )}

        {/* Early reminder */}
        {todo && todo.due !== undefined && s.todoEarlyReminderMinutes > 0 && (
          <div className="notif">
            <button className="notif-body" onClick={() => open({ tab: 'todos', id: todo.id })}>
              <img src="/icon.png" alt="" />
              <div className="notif-text">
                <div className="notif-top"><b>{todo.title}</b><span>earlier</span></div>
                <div>Due in {leadTimeName(s.todoEarlyReminderMinutes)} · {dueDescription(todo.due, now)}</div>
              </div>
            </button>
          </div>
        )}
      </div>
      <Caption>
        Tap a notification to open it: the alarm one opens the Alarms tab, which already shows its Dismiss card.
        Right-click one to see the actions iOS shows when you press and hold it.
        Which notifications appear follows each tab's settings{!s.todoEarlyReminderMinutes ? ' (to-do early reminders are off)' : ''}.
        The alarm heads-up clears itself once that alarm rings.
        {!alarm && ' No alarms are set, so the alarm one is an example.'}
      </Caption>
    </>
  )
}

// MARK: - Live Activity

function TimerLockActivity({ timer }: { timer: TimerItem }) {
  const { now, setTimer } = useSystem()
  const left = timer.state === 'running' ? Math.max(0, (timer.fireDate - now) / 1000) : timer.remaining
  return (
    <div className="activity">
      <div style={{ flex: 1, minWidth: 0, textAlign: 'left' }}>
        <div className="orange" style={{ fontWeight: 600, fontSize: 14 }}>⏱ {timer.label || 'Timer'}</div>
        <div style={{ fontSize: 40, fontWeight: 300, fontVariantNumeric: 'tabular-nums' }}>{clock(left - 0.05)}</div>
      </div>
      <button className="activity-btn" aria-label={timer.state === 'paused' ? 'Resume' : 'Pause'}
        onClick={() => setTimer(timer.id, (t) => (t.state === 'paused'
          ? { ...t, state: 'running', fireDate: Date.now() + t.remaining * 1000 }
          : { ...t, state: 'paused', remaining: Math.max(0, (t.fireDate - Date.now()) / 1000) }))}>{timer.state === 'paused' ? '▶' : '❚❚'}</button>
      <button className="activity-btn" aria-label="Cancel" onClick={() => setTimer(timer.id, () => null)}>✕</button>
    </div>
  )
}

function LiveActivity() {
  const { data, now, setTimer, update } = useSystem()
  const real = data.timers.find((t) => t.state !== 'ringing')
  const timer: TimerItem = real ?? { id: 'example', label: 'Pasta', duration: 540, state: 'running', fireDate: now + 312_000, remaining: 540 }
  const left = timer.state === 'running' ? Math.max(0, (timer.fireDate - now) / 1000) : timer.remaining
  const startExample = () => update((d) => ({ ...d, timers: [...d.timers, { ...timer, id: Math.random().toString(36).slice(2), fireDate: Date.now() + 540_000 }] }))
  return (
    <>
      <div className="island-stage">
        <div className="island-label">Compact</div>
        <div className="di compact"><span className="orange">⏱</span><span className="di-gap" /><span className="orange tnum">{clock(left - 0.05)}</span></div>
        <div className="island-label">Minimal (with another activity)</div>
        <div className="di-row"><div className="di minimal-main" /><div className="di minimal"><span className="orange">⏱</span></div></div>
        <div className="island-label">Expanded (touch and hold)</div>
        <div className="di expanded">
          <div className="di-exp-top">
            <span className="orange" style={{ fontWeight: 600 }}>⏱ {timer.label || 'Timer'}</span>
            <span className="tnum" style={{ fontSize: 30, fontWeight: 600 }}>{clock(left - 0.05)}</span>
          </div>
          <div className="di-exp-buttons">
            <button onClick={() => real && setTimer(real.id, (t) => (t.state === 'paused'
              ? { ...t, state: 'running', fireDate: Date.now() + t.remaining * 1000 }
              : { ...t, state: 'paused', remaining: Math.max(0, (t.fireDate - Date.now()) / 1000) }))}>{timer.state === 'paused' ? '▶ Resume' : '❚❚ Pause'}</button>
            <button onClick={() => real && setTimer(real.id, () => null)}>✕ Cancel</button>
          </div>
        </div>
      </div>
      <div className="lock" style={{ marginTop: 14, padding: 16 }}>
        <TimerLockActivity timer={timer} />
      </div>
      {!real && <div className="panel-actions"><button className="pill" onClick={startExample}>Start a 9-minute example timer</button></div>}
      <Caption>A running timer in the Dynamic Island (compact, minimal, expanded) and on the lock screen, with Pause and Cancel. {real ? 'This is your running timer.' : 'No timer is running, so this is an example.'}</Caption>
    </>
  )
}

// MARK: - Control Center

function ControlCenter() {
  const ask = useAsk()
  // Like the Reminders quick add: a text box drops in from the top; after sending, the reply
  // shows in the same place. The app never opens.
  const [stage, setStage] = useState<'closed' | 'typing' | 'thinking' | 'reply'>('closed')
  const [draft, setDraft] = useState('')
  const [asked, setAsked] = useState('')
  const [reply, setReply] = useState('')
  const send = async () => {
    const text = draft.trim()
    if (!text) return
    setAsked(text)
    setDraft('')
    setStage('thinking')
    setReply(await ask(text))
    setStage('reply')
  }
  const close = () => { setStage('closed'); setDraft('') }
  return (
    <>
      <div className="cc">
        {stage !== 'closed' && (
          <div className="quick-prompt" role="dialog" aria-label="Ask Alarmie">
            <div className="qp-head"><img src="/icon.png" alt="" /><b>Alarmie</b></div>
            {stage === 'typing' ? (
              <>
                <div className="qp-question">What can I do for you?</div>
                <input autoFocus className="qp-input" placeholder="Request" value={draft} onChange={(e) => setDraft(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') send(); if (e.key === 'Escape') close() }} />
                <div className="qp-buttons">
                  <button onClick={close}>Cancel</button>
                  <button className="primary" disabled={!draft.trim()} onClick={send}>Done</button>
                </div>
              </>
            ) : (
              <>
                <div className="qp-asked">“{asked}”</div>
                <div className="qp-reply">{stage === 'thinking' ? <span className="qp-dots">•••</span> : reply}</div>
                {stage === 'reply' && (
                  <div className="qp-buttons single">
                    <button className="primary" onClick={close}>Done</button>
                  </div>
                )}
              </>
            )}
          </div>
        )}
        <div className="cc-grid">
          <div className="cc-tile cc-group">
            <span className="cc-dot on">✈︎</span><span className="cc-dot on blue">⇅</span><span className="cc-dot on blue">◉</span><span className="cc-dot on blue">ᛒ</span>
          </div>
          <div className="cc-tile cc-media"><div style={{ fontSize: 12, opacity: 0.6 }}>Not Playing</div><div style={{ fontSize: 22 }}>⏮ ▶ ⏭</div></div>
          <div className="cc-tile small">🔒</div>
          <div className="cc-tile small">⧉</div>
          <div className="cc-slider"><span>☀︎</span></div>
          <div className="cc-slider"><span>🔊</span></div>
          <div className="cc-tile small">🔦</div>
          <div className="cc-tile small">⏱</div>
          <button className="cc-tile small cc-app" onClick={() => setStage('typing')} aria-label="Ask Alarmie">〰︎</button>
          <div className="cc-tile small">📷</div>
          <div className="cc-tile small">🌙</div>
          <div className="cc-tile small">🧮</div>
        </div>
        <div className="cc-label">Ask Alarmie</div>
      </div>
      <Caption>Alarmie adds one control, Ask Alarmie (orange, bottom row). Like the Reminders quick add, tapping it drops a text box in from the top of the screen: type a request, tap Done, and the assistant's reply appears in the same box. The app doesn't open. The other tiles are stand-ins for system controls.</Caption>
    </>
  )
}

// MARK: - Alarm ringing

function Ringing() {
  const { data, now, next, open } = useSystem()
  const alarm = next?.alarm ?? data.alarms[0]
  const at = new Date(next?.date ?? now)
  const t = timeParts(at.getHours(), at.getMinutes())
  return (
    <>
      <div className="ringing">
        <div className="ring-top">⏰ Alarmie</div>
        <div className="ring-time">{t.time}</div>
        <div className="ring-label">{alarm ? alarmTitle(alarm) : 'Alarm'}</div>
        <div style={{ flex: 1 }} />
        <button className="ring-stop" onClick={() => open({ tab: 'alarms' })}>Stop</button>
      </div>
      <Caption>A ringing alarm is shown full screen by iOS (AlarmKit), even when the phone is locked or in Silent mode. Stop turns it off. In this preview it never actually rings.</Caption>
    </>
  )
}
