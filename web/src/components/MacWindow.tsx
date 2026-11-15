import { useEffect, useRef, useState } from 'react'
import { WideContext } from '../logic/layout'
import { dayDescription, nextAlarm, timeOf, timeParts } from '../logic/model'
import { useStore, type Tab } from '../logic/store'
import { TABS, TabScreen } from './Screens'

/** The Mac app (the iPad build on the Mac): a sidebar instead of the tab bar, and each tab in its
 *  wide layout, under the Mac's menu bar with Alarmie's ⏰ item. Shares your preview data with
 *  the iPhone. */
export function MacWindow() {
  const { tab, setTab } = useStore()
  return (
    <div className="mac-desktop">
      <MenuBar />
      <div className="mac-window">
        <nav className="mac-sidebar" aria-label="Tabs">
          <div className="mac-lights" aria-hidden><i /><i /><i /></div>
          {TABS.map((t) => (
            <button key={t.id} className={tab === t.id ? 'active' : ''} onClick={() => setTab(t.id)} aria-current={tab === t.id}>
              <span className="glyph">{t.glyph}</span>{t.label}
            </button>
          ))}
        </nav>
        <div className="mac-content">
          <div className="app mac-app">
            <WideContext.Provider value={true}>
              <div className="app-body" key={tab}><TabScreen tab={tab} /></div>
            </WideContext.Provider>
          </div>
        </div>
      </div>
    </div>
  )
}

/** The Mac's menu bar: Alarmie's menus on the left; on the right Alarmie's ⏰ item (its menu shows
 *  the next alarm and open to-dos and opens any tab or Live Talk), then the system's icons. */
function MenuBar() {
  const { data, now, open } = useStore()
  const [menuOpen, setMenuOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!menuOpen) return
    const close = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setMenuOpen(false) }
    document.addEventListener('mousedown', close)
    return () => document.removeEventListener('mousedown', close)
  }, [menuOpen])

  const next = nextAlarm(data.alarms, now)
  const openTodos = data.todos.filter((t) => !t.isDone).length
  const go = (tab: Tab) => { open({ tab }); setMenuOpen(false) }
  const d = new Date(now)
  const clock = `${d.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })}  ${timeParts(d.getHours(), d.getMinutes()).time}`
  return (
    <div className="mac-menubar">
      <b>Alarmie</b><span>File</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span>
      <span className="mac-menubar-spacer" />
      <div className="status-item-wrap" ref={ref}>
        <button className={`status-item ${menuOpen ? 'open' : ''}`} aria-label="Alarmie" aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>⏰</button>
        {menuOpen && (
          <div className="status-menu" role="menu">
            <div className="status-info">{next ? `Next alarm: ${dayDescription(next.date, now)} ${timeOf(next.date)}` : 'No alarms'}</div>
            <div className="status-info">{openTodos === 0 ? 'No to-dos' : `${openTodos} to-do${openTodos === 1 ? '' : 's'} open`}</div>
            <hr />
            <button role="menuitem" onClick={() => go('alarms')}><span>Open Alarmie</span><kbd>⌘O</kbd></button>
            <button role="menuitem" onClick={() => go('talk')}><span>Live Talk</span><kbd>⌘L</kbd></button>
            <hr />
            {TABS.map((t) => <button key={t.id} role="menuitem" onClick={() => go(t.id)}><span><i>{t.glyph}</i>{t.label}</span></button>)}
            <hr />
            <button role="menuitem" onClick={() => setMenuOpen(false)}><span>Quit Alarmie</span><kbd>⌘Q</kbd></button>
          </div>
        )}
      </div>
      <svg aria-hidden width="16" height="12" viewBox="0 0 16 12" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
        <path d="M1.5 4.2a9.5 9.5 0 0 1 13 0" /><path d="M4 6.8a6 6 0 0 1 8 0" /><path d="M6.5 9.3a2.4 2.4 0 0 1 3 0" />
      </svg>
      <span aria-hidden className="batt">▭</span><span aria-hidden>⌕</span>
      <span>{clock}</span>
    </div>
  )
}
