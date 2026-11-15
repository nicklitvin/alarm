import { useState, type ReactNode } from 'react'
import {
  alarmTitle, clock, countdown, dayDescription, dueDescription, durationName, isOverdue, leadTimeName, nextAlarm, nextFire,
  timeOf, timeParts, upNext, upNextLayout, alarmWindow, type Alarm, type TimerItem, type Todo, type UpNextItem,
} from '../logic/model'
import * as ex from '../logic/examples'
import { ExampleStore, useStore, type AppData, type Link } from '../logic/store'
import { useAsk } from '../tabs/TalkTab'

// Examples of everything the app shows outside itself: widgets, lock screen, notifications,
// Live Activities, Control Center and the ringing alarm. Each example has its own fixed data
// (never your preview's), shows one situation, and its buttons work. Nothing here is a real iOS
// surface.

type Example = [label: string, make: (now: number) => AppData]

const SECTIONS: { id: string; label: string; examples: Example[]; view: () => ReactNode }[] = [
  { id: 'home', label: 'Home Screen', view: () => <HomeScreen />, examples: [
    ['Alarm within 12 hours (the widget window): it shows, with Dismiss; more to-dos than fit', ex.alarmSoon],
    ['Next alarm days away: not in the widgets yet (zzz); Live Talk button off', ex.alarmFar],
    ['No alarms: Next Alarm shows zzz', ex.noAlarms],
    ['Nothing at all', ex.empty],
  ] },
  { id: 'ideas', label: 'Up Next Ideas (4 rows of content)', view: () => <UpNextIdeas />, examples: [
    ['With an alarm', ex.alarmSoon],
    ['Just to-dos', ex.noAlarms],
  ] },
  { id: 'lock', label: 'Lock Screen', view: () => <LockScreen />, examples: [
    ['Alarm within the widget window, with a running timer', ex.timerRunning],
    ['No alarm within the widget window: zzz', ex.alarmFar],
  ] },
  { id: 'notifications', label: 'Notifications', view: () => <Notifications />, examples: [['', ex.notifications]] },
  { id: 'live', label: 'Live Activity', view: () => <LiveActivity />, examples: [
    ['Running', ex.timerRunning],
    ['Paused', ex.timerPaused],
  ] },
  { id: 'control', label: 'Control Center', view: () => <ControlCenter />, examples: [['', ex.alarmSoon]] },
  { id: 'ringing', label: 'Alarm Ringing', view: () => <Ringing />, examples: [['', ex.alarmSoon]] },
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
  // The widgets only show the next alarm within the widget window (Alarm settings).
  const within24h = next && next.date - now <= alarmWindow(data.settings) ? next : undefined
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

/** Every system view, one after another in a long list, each in all its example situations. */
export function SystemViews() {
  return (
    <div className="system-list">
      {SECTIONS.map((section) => (
        <section key={section.id} id={section.id} className="system-section">
          <h2>{section.label}</h2>
          <div className="examples">
            {section.examples.map(([label, make]) => (
              <div key={label} className="example">
                {label && <div className="example-label">{label}</div>}
                <ExampleStore make={make}>{section.view()}</ExampleStore>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  )
}

// MARK: - Shared row

function Row({ item, compact = false, light = false, single = false }: { item: UpNextItem; compact?: boolean; light?: boolean; single?: boolean }) {
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
  // One-line rows (medium and large widgets): title on the left, the short detail on the right.
  const inline = item.kind === 'todo' ? (item.todo.due ? dueDescription(item.todo.due, now) : '')
    : item.kind === 'timer' ? sub : `in ${countdown(now, item.date)}`
  return (
    <div className={`widget-row ${light ? 'on-wallpaper' : ''}`} onClick={(e) => { e.stopPropagation(); open(linkFor(item)) }}>
      {item.kind === 'todo'
        ? <button className={`check ${done ? 'done' : subRed ? 'overdue' : ''}`} style={{ width: 20, height: 20, fontSize: 11 }} aria-label="Complete"
            onClick={(e) => { e.stopPropagation(); complete(item.todo.id) }}>{done ? '✓' : ''}</button>
        : <span className={item.kind === 'timer' ? '' : 'alarm-glyph'} style={{ width: 20, textAlign: 'center' }}>{icon}</span>}
      {single ? (
        <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'baseline', gap: 6 }}>
          <div className="t ellipsis" style={{ flex: 1, minWidth: 0, fontSize: 14, textDecoration: done ? 'line-through' : undefined, opacity: done ? 0.6 : 1 }}>{title}</div>
          {inline && <div className={`s ${subRed ? 'red' : ''}`} style={{ flex: 'none', fontSize: 12 }}>{inline}</div>}
        </div>
      ) : (
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="t ellipsis" style={{ fontSize: compact ? 13 : 14, textDecoration: done ? 'line-through' : undefined, opacity: done ? 0.6 : 1 }}>{title}</div>
          {sub && <div className={`s ellipsis ${subRed ? 'red' : ''}`}>{sub}</div>}
        </div>
      )}
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
  const { now, items, open, dismiss, data, next } = useSystem()
  const shownNext = next && next.date - now <= alarmWindow(data.settings) ? next : undefined
  const first = items[0]
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
          {!stacked && <span className="v-alarm-icon alarm-glyph">⏰</span>}
          <div className="v-alarm-time">{bigTime(featured.date).time}<small> {bigTime(featured.date).period}</small></div>
          <div className="v-alarm-sub ellipsis">{featured.alarm.label.trim() ? `${featured.alarm.label.trim()} · ` : ''}in {countdown(now, featured.date)}</div>
        </div>
      </div>
      {/* One skipped ring per alarm: once dismissed, the ring after it can't be dismissed too. */}
      {(featured.alarm.skippedOccurrence ?? 0) <= now && featured.date - now <= alarmWindow(data.settings) &&
        <button className="mini dismiss" onClick={(e) => { e.stopPropagation(); dismiss(featured.alarm.id, featured.date) }}>Dismiss</button>}
    </div>
  )
  const upNextWidget = (size: 'small' | 'medium' | 'large') => {
    // Equal-height lines, no title: the alarm, the rows, and the last line with "+3 to-dos"
    // (when some don't fit) and the Live Talk button. Four lines in the medium widget.
    const showsTalk = data.settings.widgetShowsTalkButton
    const lines = size === 'medium' ? 4 : 11
    const capacity = lines - (featured ? 1 : 0)
    const needsFooter = showsTalk || layout.rows.length > capacity
    const shown = layout.rows.slice(0, capacity - (needsFooter ? 1 : 0))
    const hidden = layout.rows.slice(shown.length)
    const hiddenTodos = hidden.filter((i) => i.kind === 'todo').length
    const more = hiddenTodos > 0 ? `+${hiddenTodos} to-do${hiddenTodos === 1 ? '' : 's'}` : `+${hidden.length} more`
    if (size === 'small') {
      return (
        <div className="widget upnext small" onClick={() => open(featured ? { tab: 'alarms' } : first ? linkFor(first) : { tab: 'todos' })}>
          {featured ? (
            // Fills the widget like Next Alarm: day, big time, label, then a full-width Dismiss.
            <div className="small-alarm">
              <div className="wh"><span className="alarm-glyph">⏰</span><span className="muted" style={{ fontSize: 12 }}>in {countdown(now, featured.date)}</span></div>
              <div className="big">{bigTime(featured.date).time}<small> {bigTime(featured.date).period}</small></div>
              {featured.alarm.label.trim() && <div className="muted ellipsis" style={{ fontSize: 14, fontWeight: 500 }}>{featured.alarm.label.trim()}</div>}
              {(featured.alarm.skippedOccurrence ?? 0) <= now && featured.date - now <= alarmWindow(data.settings) &&
                <button className="dismiss-full" onClick={(e) => { e.stopPropagation(); dismiss(featured.alarm.id, featured.date) }}>Dismiss</button>}
            </div>
          ) : (
            <>{first ? <Row item={first} compact /> : <div style={{ marginTop: 10 }}><b>All clear</b></div>}</>
          )}
        </div>
      )
    }
    return (
      <div className={`widget upnext ${size}`} onClick={() => open(featured ? { tab: 'alarms' } : first ? linkFor(first) : { tab: 'todos' })}>
        {/* The alarm (if any), then the rows directly: no divider, no "Up Next" title. */}
        <div className="upnext-lines" style={{ gridTemplateRows: `repeat(${lines}, 1fr)` }}>
          {featured && <div className="line">{alarmHeader(false)}</div>}
          {shown.length === 0 ? <div style={{ gridRow: featured ? undefined : 'span 2' }}>{featured ? <span className="muted" style={{ fontSize: 12 }}>Nothing to do.</span> : <><b>All clear</b><div className="muted" style={{ fontSize: 12 }}>Nothing coming up.</div></>}</div>
            : shown.map((i) => <div className="line" key={keyOf(i)}><Row item={i} single /></div>)}
          {needsFooter && (
            <div className="upnext-foot" style={{ gridRow: lines }}>
              <span>{hidden.length > 0 ? more : ''}</span>
              {showsTalk && <button className="ask line-ask" aria-label="Open Talk" onClick={(e) => { e.stopPropagation(); open({ tab: 'talk' }) }}>〰︎</button>}
            </div>
          )}
        </div>
      </div>
    )
  }
  return (
    <>
      <div className="home">
        <div className="widgets">
          {/* Next Alarm (small): the next alarm (within the widget window) with a full-width Dismiss; otherwise zzz. */}
          <div className="widget upnext small" onClick={() => open({ tab: 'alarms' })}>
            {shownNext ? (
              <div className="small-alarm">
                <div className="wh"><span className="alarm-glyph">⏰</span><span className="muted" style={{ fontSize: 12 }}>in {countdown(now, shownNext.date)}</span></div>
                <div className="big">{bigTime(shownNext.date).time}<small> {bigTime(shownNext.date).period}</small></div>
                {shownNext.alarm.label.trim() && <div className="muted ellipsis" style={{ fontSize: 14, fontWeight: 500 }}>{shownNext.alarm.label.trim()}</div>}
                {(shownNext.alarm.skippedOccurrence ?? 0) <= now &&
                  <button className="dismiss-full" onClick={(e) => { e.stopPropagation(); dismiss(shownNext.alarm.id, shownNext.date) }}>Dismiss</button>}
              </div>
            ) : <div className="small-alarm" style={{ alignItems: 'center', justifyContent: 'center' }}><Zzz size={72} muted /></div>}
          </div>
          {upNextWidget('medium')}
          {upNextWidget('large')}
        </div>
      </div>
      <Caption>Next Alarm (small, with Dismiss) and Up Next (medium, large). Your next alarm shows (with Dismiss) from 12 hours before it rings, or whatever Alarm settings → Show Alarm says; to-dos and timers follow. Tapping anything opens its tab, a to-do's circle checks it off, and the waveform button opens Talk.</Caption>
    </>
  )
}

const keyOf = (i: UpNextItem) => i.kind + ('alarm' in i ? i.alarm.id : i.kind === 'timer' ? i.timer.id : i.todo.id)

/** The "zzz" SF Symbol (as on the lock screen): a big Z top-left, a small z under it, a medium z
 *  to the right. An SVG whose viewBox hugs the strokes, so it centers exactly like the symbol does. */
function Zzz({ size, muted }: { size: number; muted?: boolean }) {
  const z = (x: number, y: number, s: number) => `M${x} ${y}h${s}l${-s} ${s}h${s}`
  return (
    <svg aria-label="zzz" role="img" className={muted ? 'muted' : undefined} width={size * 0.8} height={size * 0.8}
      viewBox="-1.6 -1.6 23.2 23.2" fill="none" stroke="currentColor" strokeWidth={3.2} strokeLinecap="round" strokeLinejoin="round"
      style={{ display: 'block' }}>
      <path d={z(0, 0, 10)} />
      <path d={z(12, 6, 8)} />
      <path d={z(1, 14, 6)} />
    </svg>
  )
}

// MARK: - Up Next ideas

type Idea = 'corner' | 'cornerCount' | 'topButton' | 'rail' | 'noButton'
const IDEAS: [Idea, string, string][] = [
  ['corner', 'A · Corner button', 'The Live Talk button floats in the bottom-right corner; the last row stops short of it. No "+N": tap the widget to see everything.'],
  ['cornerCount', 'B · Corner button + count', 'Like A, with a small "+N" (the to-dos that don’t fit) just left of the button on the last row.'],
  ['topButton', 'C · Button on the top row', 'The button sits at the end of the first line (after Dismiss, or after the first to-do); "+N" is a small badge at the end of the last row.'],
  ['rail', 'D · Side rail', 'A narrow column on the right holds "+N" and the button; every row is a little narrower.'],
  ['noButton', 'E · No button', 'Just content: "+N" as a badge at the end of the last row. Live Talk stays in Control Center and the app.'],
]

/** One medium Up Next widget in each idea, all with four equal lines of content. */
function UpNextIdeas() {
  return (
    <>
      <div className="ideas-group">Split, like the Reminders widget: a summary on the left, four named to-dos on the right</div>
      <div className="ideas">
        {SPLIT_IDEAS.map(([idea, title, caption]) => (
          <div key={idea}>
            <div className="idea-title">{title}</div>
            <SplitIdea idea={idea} />
            <p className="view-caption">{caption}</p>
          </div>
        ))}
      </div>
      <div className="ideas-group">One list with the button tucked in</div>
      <div className="ideas">
        {IDEAS.map(([idea, title, caption]) => (
          <div key={idea}>
            <div className="idea-title">{title}</div>
            <UpNextIdea idea={idea} />
            <p className="view-caption">{caption}</p>
          </div>
        ))}
      </div>
    </>
  )
}

type SplitIdeaKind = 'alarmDismiss' | 'alarmButtons' | 'reminders'
const SPLIT_IDEAS: [SplitIdeaKind, string, string][] = [
  ['alarmButtons', 'F · Alarm, buttons, count', 'Top left: the next alarm and when it rings. Under it: Dismiss and the Live Talk button. Bottom left: how many to-dos are open. Right: four to-dos. With no alarm, the Live Talk button takes the alarm\u2019s place.'],
  ['alarmDismiss', 'G · Alarm and count, no Talk', 'Like F without the Live Talk button: the alarm with Dismiss on the left, the count below, four to-dos on the right. With no alarm, a to-do icon sits top left like Reminders.'],
  ['reminders', 'H · Just like Reminders', 'The Live Talk button top left (like the Reminders icon), the count bottom left. The alarm is the first row on the right, with Dismiss, then three to-dos.'],
]

/** A medium Up Next widget split in two: summary column on the left, four equal rows on the right. */
function SplitIdea({ idea }: { idea: SplitIdeaKind }) {
  const { now, items, open, dismiss, data } = useSystem()
  const layout = upNextLayout(items, now)
  const featured = layout.alarm
  const openTodos = data.todos.filter((t) => !t.isDone).length
  const canDismiss = featured && (featured.alarm.skippedOccurrence ?? 0) <= now && featured.date - now <= alarmWindow(data.settings)
  const dismissButton = canDismiss && (
    <button className="mini dismiss" onClick={(e) => { e.stopPropagation(); dismiss(featured.alarm.id, featured.date) }}>Dismiss</button>
  )
  const ask = (
    <button className="ask split-ask" aria-label="Open Talk" onClick={(e) => { e.stopPropagation(); open({ tab: 'talk' }) }}>〰︎</button>
  )
  // Right column: to-dos and timers (the alarm lives on the left), or for H the alarm first.
  const others = layout.rows.filter((i) => i.kind !== 'alarmSoon' && i.kind !== 'nextAlarm')
  const rows: ReactNode[] = []
  if (idea === 'reminders' && featured) {
    rows.push(
      <div className="split-row split-alarm-row" key="alarm" onClick={(e) => { e.stopPropagation(); open({ tab: 'alarms' }) }}>
        <span className="alarm-glyph split-glyph">⏰</span>
        <span className="split-alarm-time">{bigTime(featured.date).time}<small> {bigTime(featured.date).period}</small></span>
        <span className="split-spacer" />
        {dismissButton}
      </div>,
    )
  }
  others.slice(0, 4 - rows.length).forEach((item) => rows.push(<div className="split-row" key={keyOf(item)}><Row item={item} single /></div>))
  if (rows.length === 0) rows.push(<div className="split-row muted" key="none" style={{ fontSize: 14 }}>Nothing to do</div>)

  const alarmBlock = featured && idea !== 'reminders' && (
    <div className="split-alarm" onClick={(e) => { e.stopPropagation(); open({ tab: 'alarms' }) }}>
      <div className="split-alarm-big"><span className="alarm-glyph split-glyph">⏰</span>{bigTime(featured.date).time}<small> {bigTime(featured.date).period}</small></div>
      <div className="split-alarm-sub ellipsis">{featured.alarm.label.trim() ? `${featured.alarm.label.trim()} · ` : ''}in {countdown(now, featured.date)}</div>
    </div>
  )
  let top: ReactNode
  if (idea === 'reminders') top = ask
  else if (featured) top = (
    <>
      {alarmBlock}
      <div className="split-buttons">{dismissButton}{idea === 'alarmButtons' && ask}</div>
    </>
  )
  else top = idea === 'alarmButtons' ? <div className="split-top-icon">{ask}</div> : <span className="split-icon" aria-hidden>☰</span>

  return (
    <div className={`widget upnext medium split ${idea}`} onClick={() => open({ tab: 'todos' })}>
      <div className="split-left">
        <div className="split-top">{top}</div>
        <div className="split-count" onClick={(e) => { e.stopPropagation(); open({ tab: 'todos' }) }}>
          <b>{openTodos}</b>
          <span>{openTodos === 1 ? 'To-Do' : 'To-Dos'}</span>
        </div>
      </div>
      <div className="split-right" style={{ gridTemplateRows: 'repeat(4, 1fr)' }}>{rows}</div>
    </div>
  )
}

function UpNextIdea({ idea }: { idea: Idea }) {
  const { now, items, open, dismiss, data } = useSystem()
  const layout = upNextLayout(items, now)
  const featured = layout.alarm
  const shown = layout.rows.slice(0, 4 - (featured ? 1 : 0))
  const hidden = layout.rows.length - shown.length
  const ask = (
    <button className="ask line-ask" aria-label="Open Talk" onClick={(e) => { e.stopPropagation(); open({ tab: 'talk' }) }}>〰︎</button>
  )
  const count = hidden > 0 ? <span className="idea-count">+{hidden}</span> : null
  const canDismiss = featured && (featured.alarm.skippedOccurrence ?? 0) <= now && featured.date - now <= alarmWindow(data.settings)
  // Each line is a quarter of the widget. `last` and `first` mark where the button or count goes.
  const lines: ReactNode[] = []
  if (featured) {
    lines.push(
      <div className="v-top idea-alarm" key="alarm">
        <div className="v-alarm" onClick={(e) => { e.stopPropagation(); open({ tab: 'alarms' }) }}>
          <div className="v-alarm-line">
            <span className="v-alarm-icon alarm-glyph">⏰</span>
            <div className="v-alarm-time">{bigTime(featured.date).time}<small> {bigTime(featured.date).period}</small></div>
            <div className="v-alarm-sub ellipsis">{featured.alarm.label.trim() ? `${featured.alarm.label.trim()} · ` : ''}in {countdown(now, featured.date)}</div>
          </div>
        </div>
        {canDismiss && <button className="mini dismiss" onClick={(e) => { e.stopPropagation(); dismiss(featured.alarm.id, featured.date) }}>Dismiss</button>}
        {idea === 'topButton' && ask}
      </div>,
    )
  }
  shown.forEach((item, index) => {
    const isFirstLine = !featured && index === 0
    const isLast = index === shown.length - 1 && lines.length + 1 === 4
    lines.push(
      <div className="line idea-line" key={keyOf(item)}>
        <Row item={item} single />
        {idea === 'topButton' && isFirstLine && ask}
        {isLast && (idea === 'topButton' || idea === 'noButton') && count}
        {isLast && idea === 'cornerCount' && count}
        {isLast && (idea === 'corner' || idea === 'cornerCount') && <span className="idea-corner-space" />}
      </div>,
    )
  })
  if (lines.length === 0) lines.push(<div key="clear"><b>All clear</b><div className="muted" style={{ fontSize: 12 }}>Nothing coming up.</div></div>)
  const grid = <div className="upnext-lines idea-lines" style={{ gridTemplateRows: 'repeat(4, 1fr)' }}>{lines}</div>
  return (
    <div className={`widget upnext medium idea ${idea}`} onClick={() => open(featured ? { tab: 'alarms' } : { tab: 'todos' })}>
      {idea === 'rail' ? (
        <div className="idea-rail-wrap">
          {grid}
          <div className="idea-rail">{count ?? <span />}{ask}</div>
        </div>
      ) : grid}
      {(idea === 'corner' || idea === 'cornerCount') && <div className="idea-corner">{ask}</div>}
    </div>
  )
}

// MARK: - Lock Screen

function LockScreen() {
  const { now, next, within24h, items, open, data } = useSystem()
  const soon = within24h
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
              : <Zzz size={30} />}
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
            ) : <span style={{ display: 'flex', gap: 8, alignItems: 'center' }}><Zzz size={26} /><span className="s">{next ? 'No alarm in the next 24 hours' : 'No alarms'}</span></span>}
          </button>
        </div>
        {timer && <div style={{ marginTop: 14 }}><TimerLockActivity timer={timer} /></div>}
      </div>
      <Caption>Inline text above the clock, Next Alarm (circular and rectangular) and Up Next (rectangular). They show zzz when no alarm is within the widget window (12 hours unless changed in Alarm settings).{timer ? ' The running timer shows as a Live Activity.' : ''}</Caption>
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
  const { data, now, setTimer } = useSystem()
  const real = data.timers.find((t) => t.state !== 'ringing')
  const timer: TimerItem = real ?? { id: 'example', label: 'Pasta', duration: 540, state: 'running', fireDate: now + 312_000, remaining: 540 }
  const left = timer.state === 'running' ? Math.max(0, (timer.fireDate - now) / 1000) : timer.remaining
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
      <Caption>A timer in the Dynamic Island (compact, minimal, expanded) and on the lock screen, with Pause/Resume and Cancel.</Caption>
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
