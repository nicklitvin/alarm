import { useEffect, useState } from 'react'
import { LandscapeGallery } from './components/Landscape'
import { SystemViews } from './components/SystemViews'
import { appVersion } from './components/ui'
import { timeParts } from './logic/model'
import { useStore, type Tab } from './logic/store'
import { AlarmsTab } from './tabs/AlarmsTab'
import { NotesTab } from './tabs/NotesTab'
import { TalkTab } from './tabs/TalkTab'
import { TimersTab } from './tabs/TimersTab'
import { TodoTab } from './tabs/TodoTab'

const TABS: { id: Tab; label: string; glyph: string }[] = [
  { id: 'alarms', label: 'Alarms', glyph: '⏰' },
  { id: 'timers', label: 'Timers', glyph: '⏱' },
  { id: 'todos', label: 'To-Do', glyph: '☑︎' },
  { id: 'notes', label: 'Notes', glyph: '🗒' },
  { id: 'talk', label: 'Talk', glyph: '〰︎' },
]

type Theme = 'light' | 'dark'

export default function App() {
  const { tab, setTab, now, reset } = useStore()
  const [theme, setTheme] = useState<Theme>(() =>
    (localStorage.getItem('alarm-web-theme') as Theme | null) ?? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'))

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    try { localStorage.setItem('alarm-web-theme', theme) } catch { /* ignore */ }
  }, [theme])

  const d = new Date(now)
  return (
    <>
    <div className="stage">
      <div className="phone">
        <div className="screen">
          <div className="island" />
          <div className="app">
            <div className="statusbar"><span>{timeParts(d.getHours(), d.getMinutes()).time}</span><span className="icons">▂▄▆ 5G ▭</span></div>
            <div className="app-body" key={tab}>
              {tab === 'alarms' && <AlarmsTab />}
              {tab === 'timers' && <TimersTab />}
              {tab === 'todos' && <TodoTab />}
              {tab === 'notes' && <NotesTab />}
              {tab === 'talk' && <TalkTab />}
            </div>
            <nav className="tabbar">
              {TABS.map((t) => (
                <button key={t.id} className={tab === t.id ? 'active' : ''} onClick={() => setTab(t.id)} aria-current={tab === t.id}>
                  <span className="glyph">{t.glyph}</span>{t.label}
                </button>
              ))}
            </nav>
          </div>
          <div className="home-indicator" />
        </div>
      </div>

      <aside className="panel">
        <div>
          <h1>Alarmie · UI Preview</h1>
          <p>
            A browser copy of the iOS app (version {appVersion}) for reviewing design without building in Xcode.
            Nothing here rings or sends notifications, and the assistant only fakes a few requests.
            Your changes are saved in this browser.
          </p>
          <div className="panel-actions">
            <button className={`pill ${theme === 'light' ? 'active' : ''}`} onClick={() => setTheme('light')}>Light</button>
            <button className={`pill ${theme === 'dark' ? 'active' : ''}`} onClick={() => setTheme('dark')}>Dark</button>
            <button className="pill" onClick={() => { if (confirm('Reset all preview data to the demo set?')) reset() }}>Reset demo data</button>
          </div>
        </div>
        <SystemViews />
      </aside>
    </div>
    <LandscapeGallery />
    </>
  )
}
