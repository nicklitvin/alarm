import { useState, type ReactNode } from 'react'
import {
  alarmTitle, clock, countdown, dayDescription, dueDescription, durationName, isOverdue, leadTimeName, nextAlarm, nextFire,
  timeOf, timeParts, upNext, type Alarm, type TimerItem, type Todo, type UpNextItem,
} from '../logic/model'
import { useStore, type Link } from '../logic/store'

// Previews of everything the app shows outside itself: widgets, lock screen, notifications,
// Live Activities, Control Center and the ringing alarm. They use the preview's real data and
// their buttons work, but nothing here is a real iOS surface.

type View = 'home' | 'lock' | 'notifications' | 'live' | 'control' | 'ringing'

const VIEWS: { id: View; label: string }[] = [
  { id: 'home', label: 'Home Screen' },
  { id: 'lock', label: 'Lock Screen' },
  { id: 'notifications', label: 'Notifications' },
  { id: 'live', label: 'Live Activity' },
  { id: 'control', label: 'Control Center' },
  { id: 'ringing', label: 'Alarm Ringing' },
]

const linkFor = (item: UpNextItem): Link => {
  switch (item.kind) {
    case 'alarmSoon': case 'nextAlarm': return { tab: 'alarms' }
    case 'timer': return { tab: 'timers' }
    case 'todo': return { tab: 'todos', id: item.todo.id }
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

export function SystemViews() {
  const [view, setView] = useState<View>('home')
  return (
    <div>
      <div className="seg" role="tablist">
        {VIEWS.map((v) => (
          <button key={v.id} role="tab" aria-selected={view === v.id} className={view === v.id ? 'active' : ''} onClick={() => setView(v.id)}>{v.label}</button>
        ))}
      </div>
      {view === 'home' && <HomeScreen />}
      {view === 'lock' && <LockScreen />}
      {view === 'notifications' && <Notifications />}
      {view === 'live' && <LiveActivity />}
      {view === 'control' && <ControlCenter />}
      {view === 'ringing' && <Ringing />}
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
  const { now, next, items, open } = useSystem()
  const first = items[0]
  const upNextWidget = (size: 'small' | 'medium' | 'large') => {
    const rows = size === 'small' ? 1 : size === 'medium' ? 2 : 6
    return (
      <div className={`widget ${size}`} onClick={() => open(first ? linkFor(first) : { tab: 'todos' })}>
        <div className="wh"><span>Up Next</span></div>
        {items.length === 0 ? <div style={{ marginTop: 10 }}><b>All clear</b><div className="muted" style={{ fontSize: 12 }}>Nothing coming up.</div></div>
          : items.slice(0, rows).map((i) => <Row key={keyOf(i)} item={i} compact={size === 'small'} />)}
        <div className="foot"><span>{items.length > rows ? `+${items.length - rows} more` : ''}</span>
          {size !== 'small' && <button className="ask" aria-label="Open Talk" onClick={(e) => { e.stopPropagation(); open({ tab: 'talk' }) }}>✦</button>}
        </div>
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
      <Caption>Next Alarm (small) and Up Next (small, medium, large). Tapping an alarm or timer opens its tab, a to-do opens that to-do, tap a to-do's circle to check it off, ✦ opens Talk. Small widgets have one tap target, so they have no ✦.</Caption>
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
  const timer = data.timers.find((t) => t.state === 'running')

  const tapAlarm = () => {
    if (s.alarmTapToDismiss && alarm) dismiss(alarm.id, ring)
    open({ tab: 'alarms' })
  }

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
          {expanded === 'alarm' ? (
            <div className="notif-actions">
              <button className="red" onClick={() => { if (alarm) dismiss(alarm.id, ring); setExpanded(null) }}>🔕 Dismiss Alarm</button>
            </div>
          ) : (
            <button className="notif-hint" onClick={() => setExpanded('alarm')}>Touch and hold to see actions ›</button>
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
            {expanded === 'todo' ? (
              <div className="notif-actions">
                <button onClick={() => { complete(todo.id); setExpanded(null) }}>✓ Mark as Done</button>
                <button onClick={() => { snooze(todo.id, 3600_000); setExpanded(null) }}>↻ Remind Me in 1 Hour</button>
                <button onClick={() => { snooze(todo.id, 24 * 3600_000); setExpanded(null) }}>☀︎ Remind Me Tomorrow</button>
              </div>
            ) : (
              <button className="notif-hint" onClick={() => setExpanded('todo')}>Touch and hold to see actions ›</button>
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

        {/* Timer warning */}
        {timer && s.timerWarningMinutes > 0 && (
          <div className="notif">
            <button className="notif-body" onClick={() => open({ tab: 'timers' })}>
              <img src="/icon.png" alt="" />
              <div className="notif-text">
                <div className="notif-top"><b>{timer.label || durationName(timer.duration)}</b><span>now</span></div>
                <div>{leadTimeName(s.timerWarningMinutes)} left</div>
              </div>
            </button>
          </div>
        )}
      </div>
      <Caption>
        Tap a notification to open it{s.alarmTapToDismiss ? ' (the alarm one also dismisses that ring, because Tap Notification to Dismiss is on)' : ''}.
        Right-click, or tap "Touch and hold…", to see the actions you'd get by pressing and holding on iPhone.
        Which notifications appear follows each tab's settings{[!s.timerWarningMinutes && 'timer warnings', !s.todoEarlyReminderMinutes && 'to-do early reminders'].filter(Boolean).length
          ? ` (${[!s.timerWarningMinutes && 'timer warnings', !s.todoEarlyReminderMinutes && 'to-do early reminders'].filter(Boolean).join(' and ')} are off)` : ''}.
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
  const { open, setTab } = useSystem()
  return (
    <>
      <div className="cc">
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
          <button className="cc-tile small cc-app" onClick={() => { setTab('talk'); open({ tab: 'talk' }) }} aria-label="Live Talk">〰︎</button>
          <div className="cc-tile small">📷</div>
          <div className="cc-tile small">🌙</div>
          <div className="cc-tile small">🧮</div>
        </div>
        <div className="cc-label">Live Talk · Alarmie</div>
      </div>
      <Caption>Alarmie adds one control: Live Talk (orange, bottom row). Tapping it opens Alarmie and starts listening. The other tiles are stand-ins for system controls.</Caption>
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
