import { useState } from 'react'
import { SwipeRow } from '../components/SwipeRow'
import { BottomAction, Section, Sheet, TabHeader, Wheel } from '../components/ui'
import { addRecent, clock, compactDuration, durationName, latestTimes, uid, type RecentTimer, type TimerItem } from '../logic/model'
import { useStore } from '../logic/store'

const range = (n: number) => Array.from({ length: n }, (_, i) => i)

/** Running timers. New timers are set up in a sheet with your last three times one tap away. */
export function TimersTab() {
  const { data, update, now } = useStore()
  const [creating, setCreating] = useState(false)
  const timers = data.timers
  const running = timers.filter((t) => t.state !== 'paused').length
  const paused = timers.length - running
  const detail = timers.length === 0 ? null : paused === 0 ? `${running} running` : running === 0 ? `${paused} paused` : `${running} running · ${paused} paused`

  const start = (seconds: number, label: string) => {
    if (seconds <= 0) return
    const t: TimerItem = { id: uid(), label, duration: seconds, state: 'running', fireDate: Date.now() + seconds * 1000, remaining: seconds }
    update((d) => ({ ...d, timers: [...d.timers, t], recents: addRecent(d.recents, { duration: seconds, label }) }))
  }
  const set = (id: string, change: (t: TimerItem) => TimerItem | null) =>
    update((d) => ({ ...d, timers: d.timers.flatMap((t) => (t.id === id ? (change(t) ?? []) : [t])) }))

  return (
    <>
      <TabHeader title="Timers" tab="timers" detail={detail} />
      {timers.length > 0 && (
        <Section header="Running">
          {timers.map((t) => {
            const left = t.state === 'running' ? Math.max(0, (t.fireDate - now) / 1000) : t.state === 'paused' ? t.remaining : 0
            const progress = t.duration ? left / t.duration : 0
            const title = t.label || durationName(t.duration)
            return (
              <SwipeRow key={t.id} trailing={{ label: 'Cancel', color: 'var(--red)', onAction: () => set(t.id, () => null) }}>
                <svg className="ring" viewBox="0 0 44 44" aria-hidden>
                  <circle cx="22" cy="22" r="19" fill="none" stroke="color-mix(in srgb, var(--orange) 18%, transparent)" strokeWidth="5" />
                  <circle cx="22" cy="22" r="19" fill="none" stroke="var(--orange)" strokeWidth="5" strokeLinecap="round"
                    strokeDasharray={`${progress * 119.4} 119.4`} transform="rotate(-90 22 22)" />
                  {t.state === 'ringing' && <text x="22" y="27" textAnchor="middle" fontSize="15">🔔</text>}
                </svg>
                <div className="grow">
                  <div className="timer-time">{t.state === 'ringing' ? "Time's up" : clock(left - 0.05)}</div>
                  <div className="sub ellipsis">{t.state === 'paused' ? `${title} · Paused` : title}</div>
                </div>
                {t.state === 'ringing' && <button className="btn small" style={{ background: 'var(--red)', color: '#fff' }} onClick={() => set(t.id, () => null)}>Stop</button>}
                {t.state === 'running' && <button className="circle-btn" aria-label="Pause" onClick={() => set(t.id, (x) => ({ ...x, state: 'paused', remaining: Math.max(0, (x.fireDate - Date.now()) / 1000) }))}>❚❚</button>}
                {t.state === 'paused' && <button className="circle-btn" aria-label="Resume" onClick={() => set(t.id, (x) => ({ ...x, state: 'running', fireDate: Date.now() + x.remaining * 1000 }))}>▶</button>}
              </SwipeRow>
            )
          })}
        </Section>
      )}

      {timers.length === 0 && (
        <div className="talk-empty"><div className="big">⏱</div><h3>No Timers</h3>Tap New Timer below. Your last three times are one tap away there.</div>
      )}

      <BottomAction label="New Timer" onClick={() => setCreating(true)} />
      {creating && <NewTimerSheet recent={latestTimes(data.recents)} onClose={() => setCreating(false)} onStart={start} />}
    </>
  )
}

function NewTimerSheet({ recent, onClose, onStart }: { recent: RecentTimer[]; onClose: () => void; onStart: (seconds: number, label: string) => void }) {
  const [h, setH] = useState(0)
  const [m, setM] = useState(5)
  const [s, setS] = useState(0)
  const [label, setLabel] = useState('')
  const total = h * 3600 + m * 60 + s
  const start = (seconds: number) => {
    if (seconds <= 0) return
    onStart(seconds, label.trim())
    onClose()
  }
  return (
    <Sheet title="New Timer" onClose={onClose} left={<button onClick={onClose}>Cancel</button>}
      right={<button disabled={total === 0} onClick={() => start(total)}>Start</button>}>
      <div className="wheels">
        {([['hours', 24, h, setH], ['min', 60, m, setM], ['sec', 60, s, setS]] as const).map(([unit, n, value, setter]) => (
          <div className="wheel-unit" key={unit}>
            <Wheel items={range(n)} value={value} onChange={setter} render={(v) => <span className="num">{v}</span>} />
            <span className="unit">{unit}</span>
          </div>
        ))}
      </div>
      <div style={{ height: 16 }} />
      <Section header="Recent">
        {/* The last three times, same chips as the to-do quick times: tap one to set the wheels. */}
        <div className="row quick-times">
          {recent.map((r) => (
            <button key={r.duration} className={`qt-chip ${total === r.duration ? 'selected' : ''}`} title={r.label || durationName(r.duration)}
              onClick={() => { setH(Math.floor(r.duration / 3600)); setM(Math.floor((r.duration % 3600) / 60)); setS(r.duration % 60); if (r.label) setLabel(r.label) }}>
              {compactDuration(r.duration)}
            </button>
          ))}
        </div>
        <div className="row"><span>Label</span><input className="input right" placeholder="Timer" value={label} onChange={(e) => setLabel(e.target.value)} /></div>
      </Section>
      <div style={{ padding: '0 16px' }}>
        <button className="btn prominent" style={{ width: '100%', padding: 14, fontSize: 17 }} disabled={total === 0} onClick={() => start(total)}>Start</button>
      </div>
    </Sheet>
  )
}
