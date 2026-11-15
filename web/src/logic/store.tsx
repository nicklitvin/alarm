import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { defaultSettings, emptyStopwatch, uid, type Stopwatch, WORKDAYS, type Alarm, type Note, type RecentTimer, type Settings, type TimerItem, type Todo } from './model'

export type Tab = 'alarms' | 'timers' | 'todos' | 'notes' | 'talk'

export interface Link { tab: Tab; id?: string }

export interface ChatMessage {
  id: string
  role: 'user' | 'assistant' | 'event'
  text: string
  icon?: string
  link?: Link
}

export interface AppData {
  alarms: Alarm[]
  timers: TimerItem[]
  recents: RecentTimer[]
  stopwatch: Stopwatch
  todos: Todo[]
  notes: Note[]
  chat: ChatMessage[]
  settings: Settings
}

const STORAGE_KEY = 'alarm-web-preview-v1'

/** Demo data that shows every state: an alarm inside the dismiss window, an overdue to-do, etc. */
export function seedData(now = Date.now()): AppData {
  const inMinutes = (m: number) => {
    const d = new Date(now + m * 60_000)
    return { hour: d.getHours(), minute: Math.floor(d.getMinutes() / 5) * 5 }
  }
  const soon = inMinutes(40)
  const hour = 3600_000
  return {
    alarms: [
      { id: uid(), ...soon, label: 'Gym', weekdays: [1, 2, 3, 4, 5, 6, 7], isEnabled: true },
      { id: uid(), hour: 7, minute: 0, label: 'Wake up', weekdays: WORKDAYS, isEnabled: true },
      { id: uid(), hour: 9, minute: 30, label: 'Lazy Sunday', weekdays: [1], isEnabled: false },
    ],
    timers: [],
    recents: [{ duration: 540, label: 'Pasta' }, { duration: 300, label: '' }, { duration: 180, label: 'Tea' }],
    stopwatch: emptyStopwatch,
    todos: [
      { id: uid(), title: 'Pay electricity bill', details: '', due: now - 2 * hour, isDone: false, createdAt: now - 9 * hour },
      { id: uid(), title: 'Call mom', details: 'Ask about Sunday dinner', due: now + 2 * hour, isDone: false, createdAt: now - 3 * hour },
      { id: uid(), title: 'Dentist appointment', details: '', due: now + 50 * hour, isDone: false, createdAt: now - 5 * hour },
      { id: uid(), title: 'Read a book', details: '', isDone: false, createdAt: now - 7 * hour },
      { id: uid(), title: 'Buy groceries', details: '', isDone: true, completedAt: now - hour, createdAt: now - 20 * hour },
    ],
    notes: [
      { id: uid(), title: 'Packing list', body: '☑ Socks\n☐ Charger\n☐ Passport\n☐ Toothbrush', createdAt: now - 50 * hour, updatedAt: now - hour, isPinned: true, sortIndex: 0 },
      { id: uid(), title: '', body: 'Groceries\nMilk\nEggs\nCoffee', createdAt: now - 30 * hour, updatedAt: now - 5 * hour, isPinned: false, sortIndex: 1 },
      { id: uid(), title: 'Meeting with Sam', body: 'Budget review and hiring plan.\nFollow up next week.', createdAt: now - 80 * hour, updatedAt: now - 26 * hour, isPinned: false, sortIndex: 2 },
    ],
    chat: [],
    settings: defaultSettings,
  }
}

function load(): AppData {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) {
      const data = JSON.parse(raw) as AppData
      const settings = { ...defaultSettings, ...data.settings }
      // The old Manual note sort no longer exists.
      if (!['edited', 'created', 'title'].includes(settings.notesSort)) settings.notesSort = 'edited'
      return { ...seedData(), ...data, settings }
    }
  } catch { /* fall through to demo data */ }
  return seedData()
}

interface Store {
  data: AppData
  update: (change: (draft: AppData) => AppData) => void
  reset: () => void
  now: number
  tab: Tab
  setTab: (tab: Tab) => void
  /** An item to open once its tab shows (chat links, widget taps). */
  pending: Link | null
  open: (link: Link) => void
  /** Goes up with every opened link; open settings panels watch it and close (AppNavigation.linkOpenCount). */
  linkOpenCount: number
  clearPending: () => void
}

const StoreContext = createContext<Store | null>(null)

export function StoreProvider({ children }: { children: ReactNode }) {
  const [data, setData] = useState<AppData>(load)
  const [now, setNow] = useState(Date.now())
  const [tab, setTab] = useState<Tab>('alarms')
  const [pending, setPending] = useState<Link | null>(null)

  useEffect(() => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(data)) } catch { /* private mode */ }
  }, [data])

  // One clock for the whole preview. Timers finish visually; nothing makes a sound.
  useEffect(() => {
    const id = setInterval(() => {
      const t = Date.now()
      setNow(t)
      setData((d) => d.timers.some((x) => x.state === 'running' && x.fireDate <= t)
        ? { ...d, timers: d.timers.map((x) => (x.state === 'running' && x.fireDate <= t ? { ...x, state: 'ringing' } : x)) }
        : d)
    }, 500)
    return () => clearInterval(id)
  }, [])

  const update = useCallback((change: (draft: AppData) => AppData) => setData((d) => change(d)), [])
  const [linkOpenCount, setLinkOpenCount] = useState(0)
  const open = useCallback((link: Link) => { setLinkOpenCount((n) => n + 1); setTab(link.tab); setPending(link.id ? link : null) }, [])

  const value = useMemo<Store>(() => ({
    data, update, now, tab, setTab, pending, open, linkOpenCount,
    clearPending: () => setPending(null),
    reset: () => setData(seedData()),
  }), [data, update, now, tab, pending, open, linkOpenCount])

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>
}

export function useStore() {
  const store = useContext(StoreContext)
  if (!store) throw new Error('useStore outside StoreProvider')
  return store
}

/**
 * A self-contained store for the example views (widgets, notifications, landscape…): fixed
 * example data, kept in memory only, so the examples never show or change your own preview data.
 * Buttons still work inside the example.
 */
export function ExampleStore({ make, children }: { make: (now: number) => AppData; children: ReactNode }) {
  const [data, setData] = useState<AppData>(() => make(Date.now()))
  const [now, setNow] = useState(Date.now())
  const [tab, setTab] = useState<Tab>('alarms')
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 500)
    return () => clearInterval(id)
  }, [])
  const update = useCallback((change: (draft: AppData) => AppData) => setData((d) => change(d)), [])
  const value = useMemo<Store>(() => ({
    data, update, now, tab, setTab, pending: null,
    open: () => {}, linkOpenCount: 0, clearPending: () => {},
    reset: () => setData(make(Date.now())),
  }), [data, update, now, tab, make])
  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>
}
