import { useEffect, useState } from 'react'
import { MacWindow } from './components/MacWindow'
import { TABS, TabScreen } from './components/Screens'
import { SystemViews } from './components/SystemViews'
import { appVersion } from './components/ui'
import { timeParts } from './logic/model'
import { useStore } from './logic/store'

type Theme = 'light' | 'dark'
/** What the page shows: the iPhone app, the Mac app, or widgets and other system views. */
type View = 'iphone' | 'mac' | 'system'
const VIEWS: { id: View; label: string; blurb: string }[] = [
  { id: 'iphone', label: 'iPhone', blurb: 'The iPhone app, yours to use: changes are saved in this browser.' },
  { id: 'mac', label: 'Mac', blurb: 'The Mac app (also iPad): a sidebar instead of the tab bar, and wide layouts that use the window. Same data as the iPhone preview.' },
  { id: 'system', label: 'Widgets & System', blurb: 'Widgets, lock screen, notifications, Live Activities, Control Center and the ringing alarm, each with its own example data.' },
]

const read = <T extends string>(key: string, fallback: T): T => {
  try { return (localStorage.getItem(key) as T | null) ?? fallback } catch { return fallback }
}
const write = (key: string, value: string) => { try { localStorage.setItem(key, value) } catch { /* ignore */ } }

export default function App() {
  const { reset } = useStore()
  const [theme, setTheme] = useState<Theme>(() => read('alarm-web-theme', matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'))
  const [view, setView] = useState<View>(() => read<View>('alarm-web-view', 'iphone'))

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    write('alarm-web-theme', theme)
  }, [theme])
  useEffect(() => write('alarm-web-view', view), [view])

  const current = VIEWS.find((v) => v.id === view) ?? VIEWS[0]
  return (
    <div className="page">
      <header className="topbar">
        <div className="title-row">
          <h1>Alarmie · UI Preview</h1>
          <span className="version-badge" title="App version this preview matches">v{appVersion}</span>
        </div>
        <nav className="view-tabs" role="tablist" aria-label="What to preview">
          {VIEWS.map((v) => (
            <button key={v.id} role="tab" aria-selected={view === v.id} className={view === v.id ? 'active' : ''} onClick={() => setView(v.id)}>{v.label}</button>
          ))}
        </nav>
        <div className="panel-actions">
          <button className={`pill ${theme === 'light' ? 'active' : ''}`} onClick={() => setTheme('light')}>Light</button>
          <button className={`pill ${theme === 'dark' ? 'active' : ''}`} onClick={() => setTheme('dark')}>Dark</button>
          <button className="pill" onClick={() => { if (confirm('Reset all preview data to the demo set?')) reset() }}>Reset demo data</button>
        </div>
      </header>
      <p className="view-blurb">
        <b>{current.label}</b> · {current.blurb} A browser copy of the app for reviewing design: nothing rings or sends
        notifications, and the assistant only fakes a few requests.
      </p>

      {view === 'iphone' && <div className="stage"><Phone /></div>}
      {view === 'mac' && <div className="stage"><MacWindow /></div>}
      {view === 'system' && <div className="system-page"><SystemViews /></div>}
    </div>
  )
}

/** The iPhone app in a phone frame. */
function Phone() {
  const { tab, setTab, now } = useStore()
  const d = new Date(now)
  return (
    <div className="phone">
      <div className="screen">
        <div className="island" />
        <div className="app">
          <div className="statusbar"><span>{timeParts(d.getHours(), d.getMinutes()).time}</span><span className="icons">▂▄▆ 5G ▭</span></div>
          <div className="app-body" key={tab}><TabScreen tab={tab} /></div>
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
  )
}
