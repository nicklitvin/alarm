import type { Tab } from '../logic/store'
import { AlarmsTab } from '../tabs/AlarmsTab'
import { NotesTab } from '../tabs/NotesTab'
import { TalkTab } from '../tabs/TalkTab'
import { TimersTab } from '../tabs/TimersTab'
import { TodoTab } from '../tabs/TodoTab'

/** The app's five tabs, in the iPhone tab bar and the Mac sidebar. */
export const TABS: { id: Tab; label: string; glyph: string }[] = [
  { id: 'alarms', label: 'Alarms', glyph: '⏰' },
  { id: 'timers', label: 'Timers', glyph: '⏱' },
  { id: 'todos', label: 'To-Do', glyph: '☑︎' },
  { id: 'notes', label: 'Notes', glyph: '🗒' },
  { id: 'talk', label: 'Talk', glyph: '〰︎' },
]

export function TabScreen({ tab }: { tab: Tab }) {
  switch (tab) {
    case 'alarms': return <AlarmsTab />
    case 'timers': return <TimersTab />
    case 'todos': return <TodoTab />
    case 'notes': return <NotesTab />
    case 'talk': return <TalkTab />
  }
}
