import { useEffect, useState } from 'react'
import { BottomAction, Section, Sheet, Switch, TabHeader, TimeWheel } from '../components/ui'
import {
  alarmTitle, countdown, dayDescription, nextAlarm, nextFire, repeatSummary, roundTo5, timeOf, timeParts, uid,
  weekdayInitial, type Alarm, type Weekday,
} from '../logic/model'
import { useStore } from '../logic/store'

const ORDER: Weekday[] = [1, 2, 3, 4, 5, 6, 7]

export function AlarmsTab() {
  const { data, update, now, pending, clearPending } = useStore()
  const [editing, setEditing] = useState<Alarm | 'new' | null>(null)
  const headsUp = data.settings.alarmHeadsUpMinutes * 60_000
  const next = nextAlarm(data.alarms, now)
  const sorted = [...data.alarms].sort((a, b) => a.hour * 60 + a.minute - (b.hour * 60 + b.minute))

  // Opened from a chat link or widget tap.
  useEffect(() => {
    if (pending?.tab !== 'alarms' || !pending.id) return
    const alarm = data.alarms.find((a) => a.id === pending.id)
    if (alarm) setEditing(alarm)
    clearPending()
  }, [pending, data.alarms, clearPending])

  const setAlarm = (id: string, change: (a: Alarm) => Alarm) =>
    update((d) => ({ ...d, alarms: d.alarms.map((a) => (a.id === id ? change(a) : a)) }))

  // Rings within the heads-up window. Once dismissed, a ring is skipped, so its card disappears.
  const soon = data.alarms.flatMap((a) => {
    const t = a.isEnabled ? nextFire(a, now) : undefined
    return t !== undefined && t - now <= headsUp ? [{ alarm: a, date: t }] : []
  })

  return (
    <>
      <TabHeader title="Alarms" tab="alarms" detail={next ? `Next in ${countdown(now, next.date)}` : null} />
      {data.alarms.length === 0 ? (
        <div className="talk-empty"><div className="big">⏰</div><h3>No Alarms</h3>Tap New Alarm below to set your first one.</div>
      ) : (
        <>
          {soon.length > 0 && (
            <Section>
              {soon.map(({ alarm, date }) => (
                <div className="row" key={alarm.id}>
                  <div className="soon-icon">⏰</div>
                  <div className="grow">
                    <div style={{ fontWeight: 600 }}>{alarmTitle(alarm)}</div>
                    <div className="sub">{timeOf(date)} · in {Math.max(1, Math.ceil((date - now) / 60000))} min</div>
                  </div>
                  <button className="btn prominent small" onClick={() => setAlarm(alarm.id, (a) => a.weekdays.length ? { ...a, skippedOccurrence: date } : { ...a, isEnabled: false })}>Dismiss</button>
                </div>
              ))}
            </Section>
          )}
          <Section>
            {sorted.map((alarm) => {
              const p = timeParts(alarm.hour, alarm.minute)
              const fire = nextFire(alarm, now)
              const sub = [alarm.label.trim() || null,
                alarm.weekdays.length ? repeatSummary(alarm) : alarm.isEnabled && fire ? dayDescription(fire, now) : 'Once'].filter(Boolean).join(', ')
              return (
                <div key={alarm.id} className={`row tappable alarm-row ${alarm.isEnabled ? '' : 'off'}`} onClick={() => setEditing(alarm)}>
                  <div className="grow">
                    <div className="alarm-time">{p.time}<small>{p.period}</small></div>
                    <div className="sub ellipsis">{sub}</div>
                    {alarm.skippedOccurrence && alarm.skippedOccurrence > now && (
                      <div className="skip">🔕 Skipping {dayDescription(alarm.skippedOccurrence, now).toLowerCase()}</div>
                    )}
                  </div>
                  <span onClick={(e) => e.stopPropagation()}>
                    <Switch label="Enabled" on={alarm.isEnabled} onChange={(v) => setAlarm(alarm.id, (a) => ({ ...a, isEnabled: v, skippedOccurrence: undefined }))} />
                  </span>
                </div>
              )
            })}
          </Section>
        </>
      )}
      <BottomAction label="New Alarm" onClick={() => setEditing('new')} />
      {editing && <AlarmEditor alarm={editing === 'new' ? undefined : editing} onClose={() => setEditing(null)} />}
    </>
  )
}

function AlarmEditor({ alarm, onClose }: { alarm?: Alarm; onClose: () => void }) {
  const { update, now } = useStore()
  const start = new Date(roundTo5(now))
  const [draft, setDraft] = useState<Alarm>(alarm ?? {
    id: uid(), hour: start.getHours(), minute: start.getMinutes(), label: '', weekdays: [], isEnabled: true,
  })

  const save = () => {
    const changed = !alarm || alarm.hour !== draft.hour || alarm.minute !== draft.minute || alarm.weekdays.join() !== draft.weekdays.join() || !alarm.isEnabled
    // A changed alarm is a new alarm: it forgets today's dismissal and can ring again today.
    const saved = { ...draft, isEnabled: true, skippedOccurrence: changed ? undefined : draft.skippedOccurrence }
    update((d) => ({ ...d, alarms: alarm ? d.alarms.map((a) => (a.id === saved.id ? saved : a)) : [...d.alarms, saved] }))
    onClose()
  }
  const toggleDay = (day: Weekday) =>
    setDraft((d) => ({ ...d, weekdays: d.weekdays.includes(day) ? d.weekdays.filter((x) => x !== day) : [...d.weekdays, day] }))
  const footer = draft.weekdays.length === 0 ? `Rings once at the next ${timeOf(new Date(2000, 0, 1, draft.hour, draft.minute).getTime())}.`
    : draft.weekdays.length === 7 ? 'Rings every day.' : `Rings: ${repeatSummary(draft)}.`

  return (
    <Sheet title={alarm ? 'Edit Alarm' : 'Add Alarm'} onClose={onClose}
      left={<button onClick={onClose}>Cancel</button>} right={<button onClick={save}>Save</button>}>
      <TimeWheel hour={draft.hour} minute={draft.minute} onChange={(hour, minute) => setDraft((d) => ({ ...d, hour, minute }))} />
      <div style={{ height: 20 }} />
      <Section header="Repeat" footer={footer}>
        <div className="days">
          {ORDER.map((day) => (
            <button key={day} className={`day ${draft.weekdays.includes(day) ? 'on' : ''}`} onClick={() => toggleDay(day)}>{weekdayInitial(day)}</button>
          ))}
        </div>
      </Section>
      <Section>
        <div className="row"><span>Label</span><input className="input right" placeholder="Alarm" value={draft.label} onChange={(e) => setDraft((d) => ({ ...d, label: e.target.value }))} /></div>
      </Section>
      {alarm && (
        <Section>
          <button className="row tappable red" style={{ width: '100%', justifyContent: 'center' }}
            onClick={() => { update((d) => ({ ...d, alarms: d.alarms.filter((a) => a.id !== alarm.id) })); onClose() }}>Delete Alarm</button>
        </Section>
      )}
      <div className="section-footer" style={{ textAlign: 'center' }}>Preview only: alarms here never ring.</div>
    </Sheet>
  )
}

