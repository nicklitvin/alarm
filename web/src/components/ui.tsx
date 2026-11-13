import { useEffect, useRef, useState, type ReactNode } from 'react'
import changelog from '../../../CHANGELOG.json'
import {
  applyTimeOfDay, dueDescription, dueSuggestions, leadTimeName, TIMES_OF_DAY, timeOf, type NotesSort, type Settings,
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

export function Sheet({ title, onClose, left, right, medium, children }: {
  title: string; onClose: () => void; left?: ReactNode; right?: ReactNode; medium?: boolean; children: ReactNode
}) {
  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className={`sheet ${medium ? 'medium' : ''}`} onClick={(e) => e.stopPropagation()} role="dialog" aria-label={title}>
        <div className="grabber" />
        <div className="sheet-nav">
          <div className="left">{left ?? <span />}</div>
          <div className="title">{title}</div>
          <div className="right">{right ?? <span />}</div>
        </div>
        <div className="sheet-body">{children}</div>
      </div>
    </div>
  )
}

/** Title on the left, status on the right, then the tab's settings gear. */
export function TabHeader({ title, tab, detail, accessory, plain }: {
  title?: string; tab: Tab; detail?: string | null; accessory?: ReactNode; plain?: boolean
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
        <button className="gear" aria-label="Settings" onClick={() => setOpen(true)}>⚙︎</button>
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

export function TimeOfDayChips({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const { now } = useStore()
  const d = new Date(value)
  return (
    <div className="tod">
      {TIMES_OF_DAY.map((t) => {
        const selected = d.getHours() === t.hour && d.getMinutes() === 0
        return (
          <button key={t.title} className={`chip ${selected ? 'selected' : ''}`} onClick={() => onChange(applyTimeOfDay(value, t.hour, now))}>
            <b>{t.title}</b><span>{timeOf(new Date(2000, 0, 1, t.hour).getTime()).replace(':00', '')}</span>
          </button>
        )
      })}
    </div>
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
    <Sheet title={TITLES[tab]} onClose={onClose} right={<button onClick={onClose}>Done</button>}>
      {tab === 'alarms' && (
        <Section header="Notifications" footer={s.alarmHeadsUpEnabled
          ? `You'll get a notification ${leadTimeName(s.alarmHeadsUpMinutes)} before each alarm, with a button to dismiss that ring.`
          : `No notification before alarms. You can still dismiss the next ring ${leadTimeName(s.alarmHeadsUpMinutes)} before it.`}>
          <div className="row"><span className="grow">Heads-Up Notification</span><Switch label="Heads-up" on={s.alarmHeadsUpEnabled} onChange={(v) => set('alarmHeadsUpEnabled', v)} /></div>
          <div className="row"><span className="grow">Notify Me</span>{choice(s.alarmHeadsUpMinutes, [15, 30, 60, 120], (v) => set('alarmHeadsUpMinutes', v))}</div>
        </Section>
      )}
      {tab === 'alarms' && (
        <Section footer={s.alarmTapToDismiss
          ? "Tapping the heads-up notification cancels that ring. Swiping the notification away doesn't."
          : 'Touch and hold the heads-up notification, then tap Dismiss Alarm, to cancel that ring.'}>
          <div className="row"><span className="grow">Tap Notification to Dismiss</span>
            <Switch label="Tap notification to dismiss" on={s.alarmTapToDismiss} onChange={(v) => set('alarmTapToDismiss', v)} /></div>
        </Section>
      )}
      {tab === 'alarms' && (
        <Section header="Up Next Widget" footer="Whether alarms appear in the Up Next widget. The Next Alarm widget always shows them.">
          <div className="row"><span className="grow">Show Alarms</span><Switch label="Show alarms in widget" on={s.widgetShowsAlarms} onChange={(v) => set('widgetShowsAlarms', v)} /></div>
        </Section>
      )}
      {tab === 'timers' && (
        <Section header="Notifications" footer={s.timerWarningMinutes === 0 ? 'Timers ring when they finish, even in Silent mode.' : `You'll get a notification ${leadTimeName(s.timerWarningMinutes)} before a timer finishes.`}>
          <div className="row"><span className="grow">Before a Timer Ends</span>{choice(s.timerWarningMinutes, [0, 1, 5], (v) => set('timerWarningMinutes', v))}</div>
        </Section>
      )}
      {tab === 'todos' && (
        <Section header="Notifications" footer="Deadlines also show in the app and widget.">
          <div className="row"><span className="grow">At the Deadline</span><Switch label="At the deadline" on={s.todoDueAlertEnabled} onChange={(v) => set('todoDueAlertEnabled', v)} /></div>
          <div className="row"><span className="grow">Early Reminder</span>{choice(s.todoEarlyReminderMinutes, [0, 5, 15, 30, 60, 1440], (v) => set('todoEarlyReminderMinutes', v), 'None')}</div>
        </Section>
      )}
      {tab === 'todos' && (
        <Section header="Up Next Widget" footer="Choose which to-dos appear in the Up Next widget.">
          <div className="row"><span className="grow">To-Dos with a Deadline</span><Switch label="To-dos with a deadline" on={s.widgetShowsTimedTodos} onChange={(v) => set('widgetShowsTimedTodos', v)} /></div>
          <div className="row"><span className="grow">To-Dos without a Deadline</span><Switch label="To-dos without a deadline" on={s.widgetShowsUntimedTodos} onChange={(v) => set('widgetShowsUntimedTodos', v)} /></div>
        </Section>
      )}
      {tab === 'notes' && (
        <Section header="Sort By" footer={s.notesSort === 'manual' ? 'Press and hold a note, then drag it onto another to move it. Pinned notes always stay on top.' : 'Pinned notes always stay on top. Press and hold a note and drag it to arrange notes yourself (switches to Manual).'}>
          {(['manual', 'edited', 'created', 'title'] as NotesSort[]).map((sort) => (
            <button key={sort} className="row tappable" style={{ width: '100%', textAlign: 'left' }} onClick={() => set('notesSort', sort)}>
              <span className="grow">{{ manual: 'Manual', edited: 'Date Edited', created: 'Date Created', title: 'Title' }[sort]}</span>
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
          <Section footer="In the app everything runs on your iPhone with Apple's on-device model. This preview uses simple canned replies.">
            <button className="row tappable red" style={{ width: '100%' }} onClick={() => { update((d) => ({ ...d, chat: [] })); onClose() }}>🗑︎ Clear Conversation</button>
          </Section>
        </>
      )}
      {tab !== 'talk' && (() => {
        const info = {
          alarms: { label: 'Delete All Alarms', count: data.alarms.length, ask: `Delete all ${data.alarms.length} alarms?` },
          timers: { label: 'Delete All Timers', count: data.timers.length + data.recents.length, ask: 'Cancel running timers and clear Recents?' },
          todos: { label: 'Delete All To-Dos', count: data.todos.length, ask: `Delete all ${data.todos.length} to-dos, including completed ones?` },
          notes: { label: 'Delete All Notes', count: data.notes.length, ask: `Delete all ${data.notes.length} notes?` },
        }[tab]
        const clear = () => update((d) => tab === 'alarms' ? { ...d, alarms: [] } : tab === 'timers' ? { ...d, timers: [], recents: [] }
          : tab === 'todos' ? { ...d, todos: [] } : { ...d, notes: [] })
        return (
          <Section footer={tab === 'timers' ? 'Cancels any running timers and clears the Recents list.' : 'Removes everything on this tab.'}>
            <button className="row tappable red" style={{ width: '100%' }}
              onClick={() => { if (info.count && confirm(`${info.ask}\nThis can't be undone.`)) clear() }}>🗑︎ {info.label}</button>
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
