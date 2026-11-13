import { timeParts } from '../logic/model'
import { LandscapeContext } from '../logic/orientation'
import { useStore, type Tab } from '../logic/store'
import { AlarmsTab } from '../tabs/AlarmsTab'
import { NotesTab } from '../tabs/NotesTab'
import { TalkTab } from '../tabs/TalkTab'
import { TimersTab } from '../tabs/TimersTab'
import { TodoTab } from '../tabs/TodoTab'

const SCREENS: { tab: Tab; label: string }[] = [
  { tab: 'alarms', label: 'Alarms' },
  { tab: 'timers', label: 'Timers' },
  { tab: 'todos', label: 'To-Do' },
  { tab: 'notes', label: 'Notes' },
  { tab: 'talk', label: 'Talk' },
]

/** Every tab in a sideways iPhone, live and interactive like the main preview. */
export function LandscapeGallery() {
  return (
    <section className="landscape-gallery">
      <h2>Landscape</h2>
      <p>Each tab with the iPhone turned sideways. Alarms switches to a grid of cards; the other tabs keep their lists, centered.</p>
      <div className="landscape-list">
        {SCREENS.map((s) => <LandscapePhone key={s.tab} tab={s.tab} label={s.label} />)}
        <LandscapeRinging />
      </div>
    </section>
  )
}

function LandscapePhone({ tab, label }: { tab: Tab; label: string }) {
  return (
    <figure className="landscape-figure">
      <div className="phone landscape">
        <div className="screen">
          <div className="island" />
          <LandscapeContext.Provider value>
            <div className="app">
              <div className="app-body">
                {tab === 'alarms' && <AlarmsTab />}
                {tab === 'timers' && <TimersTab />}
                {tab === 'todos' && <TodoTab />}
                {tab === 'notes' && <NotesTab />}
                {tab === 'talk' && <TalkTab />}
              </div>
              <nav className="tabbar">
                {SCREENS.map((s) => <button key={s.tab} className={s.tab === tab ? 'active' : ''}>{s.label}</button>)}
              </nav>
            </div>
          </LandscapeContext.Provider>
          <div className="home-indicator" />
        </div>
      </div>
      <figcaption>{label}</figcaption>
    </figure>
  )
}

/** The ringing alarm sideways: time on the left, Stop on the right. */
function LandscapeRinging() {
  const { data, now } = useStore()
  const alarm = data.alarms.find((a) => a.isEnabled) ?? data.alarms[0]
  const d = new Date(now)
  const t = alarm ? timeParts(alarm.hour, alarm.minute) : timeParts(d.getHours(), d.getMinutes())
  return (
    <figure className="landscape-figure">
      <div className="phone landscape">
        <div className="screen">
          <div className="island" />
          <div className="ringing landscape">
            <div className="ring-left">
              <div className="ring-top">⏰ Alarmie</div>
              <div className="ring-time">{t.time}<small> {t.period}</small></div>
              <div className="ring-label">{alarm?.label || 'Alarm'}</div>
            </div>
            <button className="ring-stop">Stop</button>
          </div>
        </div>
      </div>
      <figcaption>Alarm ringing</figcaption>
    </figure>
  )
}
