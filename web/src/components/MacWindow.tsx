import { WideContext } from '../logic/layout'
import { useStore } from '../logic/store'
import { TABS, TabScreen } from './Screens'

/** The Mac app (the iPad build on the Mac): a sidebar instead of the tab bar, and each tab in its
 *  wide layout. Shares your preview data with the iPhone. */
export function MacWindow() {
  const { tab, setTab } = useStore()
  return (
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
  )
}
