import { useEffect, useRef, useState, type ReactNode } from 'react'
import changelog from '../../../CHANGELOG.json'
import {
  applyQuickTime, cleanQuickTimes, compactDuration, dueDescription, newTimerChoices, dueSuggestions, leadTimeName, quickTimeLabel, timeOf, type NotesSort, type Settings,
} from '../logic/model'
import { useStore, type Tab } from '../logic/store'

export const appVersion = changelog.releases[0]?.version ?? '?'

export function Switch({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label: string }) {
  return <button role="switch" aria-checked={on} aria-label={label} className={`switch ${on ? 'on' : ''}`} onClick={() => onChange(!on)} />
}

export function Section({ header, footer, children, headerClass }: { header?: ReactNode; footer?: ReactNode; children: ReactNode; headerClass?: string }) {
  return (
    <div className="section">
      {header && <div className={`section-header ${headerClass ?? ''}`}>{header}</div>}
      <div className="card">{children}</div>
      {footer && <div className="section-footer">{footer}</div>}
    </div>
  )
}

export function Sheet({ title, onClose, left, right, medium, small, bottom, children }: {
  title: string; onClose: () => void; left?: ReactNode; right?: ReactNode; medium?: boolean
  /** A short sheet (about 300 pt), e.g. just a to-do's deadline. */
  small?: boolean
  /** A big button pinned to the bottom of the sheet, like the tabs' New … buttons. */
  bottom?: { label: string; onClick: () => void; disabled?: boolean }
  children: ReactNode
}) {
  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className={`sheet ${medium ? 'medium' : ''} ${small ? 'small' : ''}`} onClick={(e) => e.stopPropagation()} role="dialog" aria-label={title}>
        <div className="grabber" />
        <div className="sheet-nav">
          <div className="left">{left ?? <span />}</div>
          <div className="title">{title}</div>
          <div className="right">{right ?? <span />}</div>
        </div>
        <div className="sheet-body">{children}</div>
        {bottom && (
          <div className="sheet-bottom">
            <button className="btn prominent" disabled={bottom.disabled} onClick={bottom.onClick}>{bottom.label}</button>
          </div>
        )}
      </div>
    </div>
  )
}

/** Title on the left, status on the right, then the tab's settings gear. */
/** An extra button sharing the settings button's pill (TabHeaderAction). */
export interface HeaderAction { icon: string; label: string; disabled?: boolean; onClick: () => void }

export function TabHeader({ title, tab, detail, accessory, plain, actions = [] }: {
  title?: string; tab: Tab; detail?: string | null; accessory?: ReactNode; plain?: boolean; actions?: HeaderAction[]
}) {
  const [open, setOpen] = useState(false)
  return (
    <>
      <div className={`header ${plain ? 'plain' : ''}`}>
        <div className="titles">
          {title && <h1>{title}</h1>}
          {detail && <span className="detail">{detail}</span>}
        </div>
        {accessory}
        {actions.length === 0 ? <button className="gear" aria-label="Settings" onClick={() => setOpen(true)}>⚙︎</button> : (
          // One pill with the extra buttons and the gear, like the buttons above a note.
          <div className="header-pill">
            {actions.map((a) => <button key={a.label} aria-label={a.label} title={a.label} disabled={a.disabled} onClick={a.onClick}>{a.icon}</button>)}
            <button aria-label="Settings" onClick={() => setOpen(true)}>⚙︎</button>
          </div>
        )}
      </div>
      {open && <SettingsSheet tab={tab} onClose={() => setOpen(false)} />}
    </>
  )
}

export function BottomAction({ label, onClick }: { label: string; onClick: () => void }) {
  return <div className="bottom-action"><button className="btn prominent" onClick={onClick}>＋ {label}</button></div>
}

// MARK: - Wheels

const ROW = 36

export function Wheel<T extends string | number>({ items, value, onChange, render }: {
  items: T[]; value: T; onChange: (v: T) => void; render?: (v: T) => ReactNode
}) {
  const ref = useRef<HTMLDivElement>(null)
  const settle = useRef<number | undefined>(undefined)
  const index = Math.max(0, items.indexOf(value))

  useEffect(() => {
    const el = ref.current
    if (el && Math.round(el.scrollTop / ROW) !== index) el.scrollTop = index * ROW
  }, [index])

  const onScroll = () => {
    window.clearTimeout(settle.current)
    settle.current = window.setTimeout(() => {
      const el = ref.current
      if (!el) return
      const i = Math.min(items.length - 1, Math.max(0, Math.round(el.scrollTop / ROW)))
      if (items[i] !== value) onChange(items[i])
    }, 90)
  }

  return (
    <div className="wheel" ref={ref} onScroll={onScroll}>
      <div className="pad" />
      {items.map((item, i) => (
        <div className="item" key={String(item)} onClick={() => ref.current?.scrollTo({ top: i * ROW, behavior: 'smooth' })}>
          {render ? render(item) : item}
        </div>
      ))}
      <div className="pad" />
    </div>
  )
}

const HOURS = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const MINUTES_5 = Array.from({ length: 12 }, (_, i) => i * 5)

/** Hour · minute (5-minute steps) · AM/PM, like the app's time wheel. */
export function TimeWheel({ hour, minute, onChange }: { hour: number; minute: number; onChange: (h: number, m: number) => void }) {
  const h12 = hour % 12 === 0 ? 12 : hour % 12
  const pm = hour >= 12
  const set = (h: number, m: number, isPM: boolean) => onChange((h % 12) + (isPM ? 12 : 0), m)
  const roundedMinute = MINUTES_5.includes(minute) ? minute : Math.round(minute / 5) * 5 % 60
  return (
    <div className="wheels">
      <Wheel items={HOURS} value={h12} onChange={(h) => set(h, roundedMinute, pm)} />
      <Wheel items={MINUTES_5} value={roundedMinute} onChange={(m) => set(h12, m, pm)} render={(m) => String(m).padStart(2, '0')} />
      <Wheel items={['AM', 'PM']} value={pm ? 'PM' : 'AM'} onChange={(p) => set(h12, roundedMinute, p === 'PM')} />
    </div>
  )
}

// MARK: - Deadline helpers

/** The time under a suggestion, without repeating the day its title already says. */
const chipSubtitle = (title: string, date: number, now: number) =>
  /^(Tomorrow|Tonight|This (afternoon|evening))|^In /.test(title) ? timeOf(date) : dueDescription(date, now)

export function SuggestionChips({ value, onChange, onCustom }: { value?: number; onChange: (v?: number) => void; onCustom?: () => void }) {
  const { now } = useStore()
  const suggestions = dueSuggestions(now)
  const isCustom = value !== undefined && !suggestions.some((s) => s.date === value)
  return (
    <div className="chip-grid">
      {suggestions.map((s) => {
        const selected = value === s.date
        return (
          <button key={s.title} className={`chip ${selected ? 'selected' : ''}`} onClick={() => onChange(selected ? undefined : s.date)}>
            <b>{s.title}</b><span>{chipSubtitle(s.title, s.date, now)}</span>
          </button>
        )
      })}
      {onCustom && (
        <button className={`chip ${isCustom ? 'selected' : ''}`} onClick={onCustom}>
          <b>📅 Custom</b><span>{isCustom && value ? dueDescription(value, now) : 'Pick a time'}</span>
        </button>
      )}
    </div>
  )
}

/** The quick times from To-Do settings (9 AM · 3 PM · 9 PM by default), shown as just the time. */
export function TimeOfDayChips({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const { now, data } = useStore()
  const d = new Date(value)
  return (
    <div className="tod">
      {cleanQuickTimes(data.settings.todoQuickTimes).map((m) => {
        const selected = d.getHours() * 60 + d.getMinutes() === m
        return (
          <button key={m} className={`chip ${selected ? 'selected' : ''}`} onClick={() => onChange(applyQuickTime(value, m, now))}>
            <b>{quickTimeLabel(m)}</b>
          </button>
        )
      })}
    </div>
  )
}

/** A centered iOS alert (no popover arrow), for confirming destructive actions. */
export function Alert({ title, message, action, onConfirm, onCancel }: {
  title: string; message?: string; action: string; onConfirm: () => void; onCancel: () => void
}) {
  return (
    <div className="alert-backdrop" onClick={onCancel}>
      <div className="alert" role="alertdialog" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <div className="alert-text"><b>{title}</b>{message && <span>{message}</span>}</div>
        <div className="alert-buttons">
          <button onClick={onCancel}>Cancel</button>
          <button className="red" onClick={onConfirm}>{action}</button>
        </div>
      </div>
    </div>
  )
}


/** Timer settings → Quick Times: tap a time to set it with hour and minute wheels right below,
 *  or turn on Use Recent Times. */
function TimerQuickTimesSection() {
  const { data, update } = useStore()
  const s = data.settings
  const [editing, setEditing] = useState<number | null>(null)
  const times = newTimerChoices([], s.timerQuickTimes, false).map((r) => r.duration)
  const set = (patch: Partial<Settings>) => update((d) => ({ ...d, settings: { ...d.settings, ...patch } }))
  const change = (index: number, hours: number, minutes: number) =>
    set({ timerQuickTimes: times.map((t, n) => (n === index ? Math.max(60, hours * 3600 + minutes * 60) : t)) })
  const range = (n: number) => Array.from({ length: n }, (_, i) => i)
  return (
    <>
    {/* A pair: turning one on turns the other off, so New Timer always shows one of them. */}
    <Section header="New Timer" footer={s.timerUsesRecentTimes ? undefined : 'Three one-tap times in New Timer. Tap one to change it with the wheels.'}>
      <div className="row"><span className="grow">Use Quick Times</span>
        <Switch label="Use quick times" on={!s.timerUsesRecentTimes} onChange={(v) => set({ timerUsesRecentTimes: !v })} /></div>
      {!s.timerUsesRecentTimes && (
        <>
          <div className="row quick-times">
            {times.map((t, index) => (
              <button key={index} className={`qt-chip ${editing === index ? 'selected' : ''}`} onClick={() => setEditing(editing === index ? null : index)}>{compactDuration(t)}</button>
            ))}
          </div>
          {editing !== null && (
            <div className="wheels" style={{ padding: '4px 12px 8px' }}>
              {([['hours', 24, Math.floor(times[editing] / 3600)], ['min', 60, Math.floor((times[editing] % 3600) / 60)]] as const).map(([unit, n, value]) => (
                <div className="wheel-unit" key={unit}>
                  <Wheel items={range(n)} value={value} render={(v) => <span className="num">{v}</span>}
                    onChange={(v) => unit === 'hours' ? change(editing, v, Math.floor((times[editing] % 3600) / 60)) : change(editing, Math.floor(times[editing] / 3600), v)} />
                  <span className="unit">{unit}</span>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </Section>
    <Section footer="Shows the last three times you used instead of your quick times.">
      <div className="row"><span className="grow">Use Recent Times</span>
        <Switch label="Use recent times" on={s.timerUsesRecentTimes} onChange={(v) => set({ timerUsesRecentTimes: v })} /></div>
    </Section>
    </>
  )
}

/** To-Do settings → Quick Times: three buttons across the row; tap one to change it with a
 *  time wheel right below. */
function QuickTimesSection() {
  const { data, update } = useStore()
  const times = cleanQuickTimes(data.settings.todoQuickTimes)
  const [editing, setEditing] = useState<number | null>(null)
  const change = (index: number, value: number) => {
    const sorted = cleanQuickTimes(times.map((x, n) => (n === index ? value : x)))
    update((d) => ({ ...d, settings: { ...d.settings, todoQuickTimes: sorted } }))
    setEditing(sorted.indexOf(value) >= 0 ? sorted.indexOf(value) : index)
  }
  return (
    <Section header="Quick Times" footer="One-tap times under a to-do's deadline. Tap one to change it.">
      <div className="row quick-times">
        {times.map((m, index) => (
          <button key={index} className={`qt-chip ${editing === index ? 'selected' : ''}`} onClick={() => setEditing(editing === index ? null : index)}>{quickTimeLabel(m)}</button>
        ))}
      </div>
      {editing !== null && (
        <div style={{ padding: '0 12px 8px' }}>
          <TimeWheel hour={Math.floor(times[editing] / 60)} minute={times[editing] % 60} onChange={(h, mm) => change(editing, h * 60 + mm)} />
        </div>
      )}
    </Section>
  )
}

/** Date + time inputs (time in 5-minute steps). */
export function DeadlineInputs({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const d = new Date(value)
  const pad = (n: number) => String(n).padStart(2, '0')
  const dateStr = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
  const timeStr = `${pad(d.getHours())}:${pad(d.getMinutes())}`
  return (
    <>
      <div className="row"><span className="grow">Date</span>
        <input type="date" value={dateStr} className="input right date-input" style={{ width: 170 }}
          onChange={(e) => { const [y, m, day] = e.target.value.split('-').map(Number); if (!y) return; const n = new Date(value); n.setFullYear(y, m - 1, day); onChange(n.getTime()) }} />
      </div>
      <div className="row"><span className="grow">Time</span>
        <input type="time" step={300} value={timeStr} className="input right date-input" style={{ width: 140 }}
          onChange={(e) => { const [h, m] = e.target.value.split(':').map(Number); if (Number.isNaN(h)) return; const n = new Date(value); n.setHours(h, Math.round(m / 5) * 5, 0, 0); onChange(n.getTime()) }} />
      </div>
    </>
  )
}

// MARK: - Settings (per tab) + About

const TITLES: Record<Tab, string> = { alarms: 'Alarm Settings', timers: 'Timer Settings', todos: 'To-Do Settings', notes: 'Notes Settings', talk: 'Talk Settings' }

function SettingsSheet({ tab, onClose }: { tab: Tab; onClose: () => void }) {
  const { data, update } = useStore()
  const [about, setAbout] = useState(false)
  const [confirmDeleteAll, setConfirmDeleteAll] = useState(false)
  const s = data.settings
  const set = <K extends keyof Settings>(key: K, value: Settings[K]) => update((d) => ({ ...d, settings: { ...d.settings, [key]: value } }))

  if (about) {
    return (
      <Sheet title="About & Updates" onClose={onClose} left={<button onClick={() => setAbout(false)}>‹ Back</button>}>
        <div style={{ textAlign: 'center', padding: '8px 0 20px' }}>
          <img src="/icon.png" width={72} height={72} style={{ borderRadius: 17 }} alt="" />
          <div style={{ fontSize: 22, fontWeight: 600, marginTop: 8 }}>Alarmie</div>
          <div className="muted">Version {appVersion} · Web preview</div>
        </div>
        <Section header="Patch Notes">
          {changelog.releases.map((r, i) => (
            <details key={r.version} className="row" open={i === 0} style={{ display: 'block' }}>
              <summary style={{ cursor: 'pointer' }}><b>{r.version}</b> <span className="muted">· {r.title} · {r.date}</span></summary>
              <ul style={{ margin: '8px 0 4px', paddingLeft: 20, color: 'var(--label)' }}>
                {r.notes.map((n) => <li key={n} style={{ margin: '4px 0', fontSize: 15 }}>{n}</li>)}
              </ul>
            </details>
          ))}
        </Section>
      </Sheet>
    )
  }

  const choice = (value: number, choices: number[], onChange: (v: number) => void, zero = 'Off', suffix = ' before') => (
    <select className="ios" value={value} onChange={(e) => onChange(Number(e.target.value))}>
      {choices.map((c) => <option key={c} value={c}>{c === 0 ? zero : `${leadTimeName(c)}${suffix}`}</option>)}
    </select>
  )

  return (
    <Sheet title={TITLES[tab]} onClose={onClose}>
      {tab === 'alarms' && (
        <Section header="Notifications" footer={s.alarmHeadsUpEnabled
          ? `You'll get a notification ${leadTimeName(s.alarmHeadsUpMinutes)} before each alarm, with a button to dismiss that ring.`
          : 'No notification before alarms.'}>
          <div className="row"><span className="grow">Heads-Up Notification</span><Switch label="Heads-up" on={s.alarmHeadsUpEnabled} onChange={(v) => set('alarmHeadsUpEnabled', v)} /></div>
          <div className="row"><span className="grow">Notify Me</span>{choice(s.alarmHeadsUpMinutes, [15, 30, 60, 120], (v) => set('alarmHeadsUpMinutes', v))}</div>
        </Section>
      )}
      {tab === 'alarms' && (
        <Section header="Up Next Widget" footer="Whether alarms appear in the Up Next widget.">
          <div className="row"><span className="grow">Show Alarms</span><Switch label="Show alarms in widget" on={s.widgetShowsAlarms} onChange={(v) => set('widgetShowsAlarms', v)} /></div>
        </Section>
      )}
      {tab === 'todos' && (
        <Section header="Notifications" footer="You'll get a notification when a to-do is due.">
          <div className="row"><span className="grow">At the Deadline</span><Switch label="At the deadline" on={s.todoDueAlertEnabled} onChange={(v) => set('todoDueAlertEnabled', v)} /></div>
          <div className="row"><span className="grow">Early Reminder</span>{choice(s.todoEarlyReminderMinutes, [0, 5, 15, 30, 60, 1440], (v) => set('todoEarlyReminderMinutes', v), 'None')}</div>
        </Section>
      )}
      {tab === 'timers' && <TimerQuickTimesSection />}
      {tab === 'todos' && <QuickTimesSection />}
      {tab === 'todos' && (
        <Section header="Up Next Widget" footer="Choose which to-dos appear in the Up Next widget.">
          <div className="row"><span className="grow">To-Dos with a Deadline</span><Switch label="To-dos with a deadline" on={s.widgetShowsTimedTodos} onChange={(v) => set('widgetShowsTimedTodos', v)} /></div>
          <div className="row"><span className="grow">To-Dos without a Deadline</span><Switch label="To-dos without a deadline" on={s.widgetShowsUntimedTodos} onChange={(v) => set('widgetShowsUntimedTodos', v)} /></div>
        </Section>
      )}
      {tab === 'notes' && (
        <Section header="Sort By" footer="Pinned notes always stay on top.">
          {(['edited', 'created', 'title'] as NotesSort[]).map((sort) => (
            <button key={sort} className="row tappable" style={{ width: '100%', textAlign: 'left' }} onClick={() => set('notesSort', sort)}>
              <span className="grow">{{ edited: 'Date Edited', created: 'Date Created', title: 'Title' }[sort]}</span>
              {s.notesSort === sort && <span className="orange">✓</span>}
            </button>
          ))}
        </Section>
      )}
      {tab === 'talk' && (
        <>
          <Section header="Live Talk" footer={s.wakeWordEnabled ? `Only sentences that start with “${s.wakeWord}” get a reply. Typed messages always get a reply.` : 'Live Talk replies to everything it hears.'}>
            <div className="row"><span className="grow">Require Wake Word</span><Switch label="Require wake word" on={s.wakeWordEnabled} onChange={(v) => set('wakeWordEnabled', v)} /></div>
            {s.wakeWordEnabled && <div className="row"><span>Wake Word</span><input className="input right" value={s.wakeWord} onChange={(e) => set('wakeWord', e.target.value)} /></div>}
          </Section>
          <Section footer="Reads replies aloud during Live Talk.">
            <div className="row"><span className="grow">Speak Replies</span><Switch label="Speak replies" on={s.speakReplies} onChange={(v) => set('speakReplies', v)} /></div>
          </Section>
          <Section header="Up Next Widget" footer="The waveform button in the corner of the medium and large Up Next widget. Without it, the widget fits one more item.">
            <div className="row"><span className="grow">Show Live Talk Button</span>
              <Switch label="Show Live Talk button" on={s.widgetShowsTalkButton} onChange={(v) => set('widgetShowsTalkButton', v)} /></div>
          </Section>
          <Section header="Custom Instructions" footer="Applied to every conversation and reply. In the app everything runs on your iPhone with Apple's on-device model; this preview uses simple canned replies.">
            <div className="row">
              <textarea className="instructions" rows={3} placeholder="e.g. Call me Sam. Keep answers very short." value={s.customInstructions}
                onChange={(e) => set('customInstructions', e.target.value)} />
            </div>
          </Section>
        </>
      )}
      {tab !== 'talk' && (() => {
        const info = {
          alarms: { label: 'Delete All Alarms', count: data.alarms.length, ask: `Delete all ${data.alarms.length} alarms?` },
          timers: { label: 'Delete All Timers', count: data.timers.length + data.recents.length + (data.stopwatch && (data.stopwatch.startedAt !== undefined || data.stopwatch.accumulated > 0 || data.stopwatch.laps.length) ? 1 : 0), ask: 'Cancel running timers and clear recent times?' },
          todos: { label: 'Delete All To-Dos', count: data.todos.length, ask: `Delete all ${data.todos.length} to-dos, including completed ones?` },
          notes: { label: 'Delete All Notes', count: data.notes.length, ask: `Delete all ${data.notes.length} notes?` },
        }[tab]
        const clear = () => update((d) => tab === 'alarms' ? { ...d, alarms: [] } : tab === 'timers' ? { ...d, timers: [], recents: [], stopwatch: { accumulated: 0, laps: [] } }
          : tab === 'todos' ? { ...d, todos: [] } : { ...d, notes: [] })
        return (
          <Section footer={tab === 'timers' ? 'Cancels any running timers, resets the stopwatch and clears your recent times.' : 'Removes everything on this tab.'}>
            <button className="row tappable red" style={{ width: '100%' }}
              onClick={() => { if (info.count) setConfirmDeleteAll(true) }}>🗑︎ {info.label}</button>
            {confirmDeleteAll && <Alert title={info.ask} message="This can't be undone." action="Delete All"
              onCancel={() => setConfirmDeleteAll(false)} onConfirm={() => { clear(); setConfirmDeleteAll(false) }} />}
          </Section>
        )
      })()}
      <Section>
        <button className="row tappable" style={{ width: '100%', textAlign: 'left' }} onClick={() => setAbout(true)}>
          <span className="grow">ⓘ About & Updates</span><span className="muted">Version {appVersion} ›</span>
        </button>
      </Section>
    </Sheet>
  )
}
