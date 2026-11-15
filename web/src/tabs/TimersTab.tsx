import { useEffect, useState } from 'react'
import { SwipeRow } from '../components/SwipeRow'
import { Section, Sheet, TabHeader, Wheel } from '../components/ui'
import { addRecent, clock, compactDuration, durationName, formatStopwatch, newTimerChoices, stopwatchElapsed, stopwatchIsReset, uid, type RecentTimer, type Stopwatch, type TimerItem } from '../logic/model'
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

  const sw = data.stopwatch ?? { accumulated: 0, laps: [] }
  const setSw = (change: (s: Stopwatch) => Stopwatch) => update((d) => ({ ...d, stopwatch: change(d.stopwatch ?? { accumulated: 0, laps: [] }) }))

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
      {!stopwatchIsReset(sw) && (
        <Section header="Stopwatch">
          <SwipeRow trailing={{ label: 'Reset', color: 'var(--red)', onAction: () => setSw(() => ({ accumulated: 0, laps: [] })) }}>
            <div className="grow"><StopwatchTime sw={sw} /></div>
            {sw.startedAt !== undefined ? (
              <>
                <button className="circle-btn" aria-label="Lap" onClick={() => setSw((s) => ({ ...s, laps: [...s.laps, stopwatchElapsed(s, Date.now())] }))}>⚑</button>
                <button className="circle-btn" aria-label="Pause" onClick={() => setSw((s) => ({ accumulated: stopwatchElapsed(s, Date.now()), laps: s.laps }))}>❚❚</button>
              </>
            ) : (
              <>
                <button className="circle-btn" aria-label="Reset" onClick={() => setSw(() => ({ accumulated: 0, laps: [] }))}>↺</button>
                <button className="circle-btn" aria-label="Resume" onClick={() => setSw((s) => ({ ...s, startedAt: Date.now() }))}>▶</button>
              </>
            )}
          </SwipeRow>
          {sw.laps.map((total, i) => ({ n: i + 1, split: total - (i > 0 ? sw.laps[i - 1] : 0) })).reverse().map((lap) => (
            <div className="row" key={lap.n} style={{ fontSize: 15 }}>
              <span className="grow muted">Lap {lap.n}</span><span style={{ fontVariantNumeric: 'tabular-nums' }}>{formatStopwatch(lap.split)}</span>
            </div>
          ))}
        </Section>
      )}
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

      {timers.length === 0 && stopwatchIsReset(sw) && (
        <div className="talk-empty"><div className="big">⏱</div><h3>No Timers</h3>Tap New Timer below, or Stopwatch to start counting up.</div>
      )}

      {/* New Timer, and Stopwatch beside it while the stopwatch isn't in use. */}
      <div className="bottom-action two">
        <button className="btn prominent" onClick={() => setCreating(true)}>＋ New Timer</button>
        {stopwatchIsReset(sw) && <button className="btn gray" onClick={() => setSw(() => ({ accumulated: 0, laps: [], startedAt: Date.now() }))}>⏱ Stopwatch</button>}
      </div>
      {creating && <NewTimerSheet recent={newTimerChoices(data.recents, data.settings.timerQuickTimes, data.settings.timerUsesRecentTimes)} title={data.settings.timerUsesRecentTimes ? 'Recent' : 'Quick Times'} onClose={() => setCreating(false)} onStart={start} />}
    </>
  )
}

function NewTimerSheet({ recent, title, onClose, onStart }: { recent: RecentTimer[]; title: string; onClose: () => void; onStart: (seconds: number, label: string) => void }) {
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
    <Sheet title="New Timer" onClose={onClose} bottom={{ label: '▶ Start', onClick: () => start(total), disabled: total === 0 }}>
      <div className="wheels">
        {([['hours', 24, h, setH], ['min', 60, m, setM], ['sec', 60, s, setS]] as const).map(([unit, n, value, setter]) => (
          <div className="wheel-unit" key={unit}>
            <Wheel items={range(n)} value={value} onChange={setter} render={(v) => <span className="num">{v}</span>} />
            <span className="unit">{unit}</span>
          </div>
        ))}
      </div>
      <div style={{ height: 16 }} />
      <Section header={title}>
        {/* The last three times, same chips as the to-do quick times: tap one to set the wheels. */}
        <div className="row quick-times">
          {recent.map((r) => (
            <button key={`${r.duration}-${recent.indexOf(r)}`} className={`qt-chip ${total === r.duration ? 'selected' : ''}`} title={r.label || durationName(r.duration)}
              onClick={() => { setH(Math.floor(r.duration / 3600)); setM(Math.floor((r.duration % 3600) / 60)); setS(r.duration % 60); if (r.label) setLabel(r.label) }}>
              {compactDuration(r.duration)}
            </button>
          ))}
        </div>
        <div className="row"><span>Label</span><input className="input right" placeholder="Timer" value={label} onChange={(e) => setLabel(e.target.value)} /></div>
      </Section>
    </Sheet>
  )
}

/** The stopwatch's time, redrawn every frame while it runs. */
function StopwatchTime({ sw }: { sw: Stopwatch }) {
  const [, tick] = useState(0)
  useEffect(() => {
    if (sw.startedAt === undefined) return
    let frame = requestAnimationFrame(function loop() { tick((n) => n + 1); frame = requestAnimationFrame(loop) })
    return () => cancelAnimationFrame(frame)
  }, [sw.startedAt])
  return <div className="timer-time">{formatStopwatch(stopwatchElapsed(sw, Date.now()))}</div>
}
