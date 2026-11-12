// Types and logic mirrored from the Swift app (Shared/AlarmItem.swift, TimeFormat.swift, UpNext.swift,
// App/Todos/DueSuggestions.swift). Keep them in sync when the app's behaviour changes.

export type Weekday = 1 | 2 | 3 | 4 | 5 | 6 | 7 // 1 = Sunday, like Calendar

export interface Alarm {
  id: string
  hour: number
  minute: number
  label: string
  weekdays: Weekday[]
  isEnabled: boolean
  skippedOccurrence?: number // epoch ms of a dismissed ring
}

export interface TimerItem {
  id: string
  label: string
  duration: number // seconds
  state: 'running' | 'paused' | 'ringing'
  fireDate: number // epoch ms
  remaining: number // seconds, while paused
}

export interface Todo {
  id: string
  title: string
  details: string
  due?: number
  isDone: boolean
  completedAt?: number
  createdAt: number
}

export interface Note {
  id: string
  title: string
  body: string
  createdAt: number
  updatedAt: number
  isPinned: boolean
  sortIndex: number
}

export type NotesSort = 'manual' | 'edited' | 'created' | 'title'

export interface Settings {
  alarmHeadsUpEnabled: boolean
  alarmHeadsUpMinutes: number
  timerWarningMinutes: number
  todoDueAlertEnabled: boolean
  todoEarlyReminderMinutes: number
  notesSort: NotesSort
  wakeWordEnabled: boolean
  wakeWord: string
  speakReplies: boolean
}

export const defaultSettings: Settings = {
  alarmHeadsUpEnabled: true,
  alarmHeadsUpMinutes: 60,
  timerWarningMinutes: 0,
  todoDueAlertEnabled: true,
  todoEarlyReminderMinutes: 0,
  notesSort: 'edited',
  wakeWordEnabled: false,
  wakeWord: 'Hey Alarm',
  speakReplies: true,
}

export const uid = () => Math.random().toString(36).slice(2, 10)

const DAY = 24 * 3600 * 1000
export const WORKDAYS: Weekday[] = [2, 3, 4, 5, 6]
export const WEEKEND: Weekday[] = [1, 7]
export const ALL_DAYS: Weekday[] = [1, 2, 3, 4, 5, 6, 7]
const SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const LONG = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const INITIAL = ['S', 'M', 'T', 'W', 'T', 'F', 'S']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

export const weekdayInitial = (d: Weekday) => INITIAL[d - 1]
export const weekdayShort = (d: Weekday) => SHORT[d - 1]
export const weekdayLong = (d: Weekday) => LONG[d - 1]
export const weekdayOf = (ms: number) => (new Date(ms).getDay() + 1) as Weekday

const sameSet = (a: Weekday[], b: Weekday[]) => a.length === b.length && b.every((d) => a.includes(d))

// MARK: - Time formatting (12-hour, like a US iPhone)

export function timeParts(hour: number, minute: number): { time: string; period: string } {
  const h = hour % 12 === 0 ? 12 : hour % 12
  return { time: `${h}:${String(minute).padStart(2, '0')}`, period: hour < 12 ? 'AM' : 'PM' }
}

export function timeString(hour: number, minute: number) {
  const p = timeParts(hour, minute)
  return `${p.time} ${p.period}`
}

export function timeOf(ms: number) {
  const d = new Date(ms)
  return timeString(d.getHours(), d.getMinutes())
}

export function clock(seconds: number) {
  const total = Math.max(0, Math.ceil(seconds))
  const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${m}:${String(s).padStart(2, '0')}`
}

export function durationName(seconds: number) {
  const total = Math.max(0, Math.round(seconds))
  const h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60
  const unit = (n: number, name: string) => (n > 0 ? `${n} ${name}${n === 1 ? '' : 's'}` : null)
  const parts = [unit(h, 'hour'), unit(m, 'minute'), unit(s, 'second')].filter(Boolean)
  return parts.length ? parts.join(' ') : '0 seconds'
}

export function compactDuration(seconds: number) {
  if (seconds >= 3600 && seconds % 3600 === 0) return `${seconds / 3600} hr`
  if (seconds >= 60 && seconds % 60 === 0) return `${seconds / 60} min`
  if (seconds < 60) return `${seconds} sec`
  return clock(seconds)
}

export function countdown(from: number, to: number) {
  const total = Math.max(1, Math.ceil((to - from) / 60000))
  const d = Math.floor(total / 1440), h = Math.floor((total % 1440) / 60), m = total % 60
  if (d > 0) return h > 0 ? `${d}d ${h}h` : `${d}d`
  if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`
  return `${m}m`
}

export function leadTimeName(minutes: number) {
  if (minutes === 0) return 'Off'
  if (minutes === 1440) return '1 day'
  if (minutes % 60 === 0) return minutes === 60 ? '1 hour' : `${minutes / 60} hours`
  return `${minutes} min`
}

const startOfDay = (ms: number) => {
  const d = new Date(ms)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}
const dayDiff = (from: number, to: number) => Math.round((startOfDay(to) - startOfDay(from)) / DAY)

export function dayDescription(ms: number, now: number) {
  const diff = dayDiff(now, ms)
  if (diff === 0) return 'Today'
  if (diff === 1) return 'Tomorrow'
  return weekdayLong(weekdayOf(ms))
}

/** "5:00 PM", "Tomorrow 9:00 AM", "Fri 9:00 AM", "Nov 14, 9:00 AM" */
export function dueDescription(ms: number, now: number) {
  const time = timeOf(ms)
  const diff = dayDiff(now, ms)
  if (diff === 0) return time
  if (diff === 1) return `Tomorrow ${time}`
  if (diff === -1) return `Yesterday ${time}`
  if (diff >= 2 && diff <= 6) return `${weekdayShort(weekdayOf(ms))} ${time}`
  const d = new Date(ms)
  return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${time}`
}

export function roundTo5(ms: number) {
  const d = new Date(ms)
  d.setSeconds(0, 0)
  d.setMinutes(Math.round(d.getMinutes() / 5) * 5)
  return d.getTime()
}

// MARK: - Alarms

export const alarmTitle = (a: Alarm) => a.label.trim() || 'Alarm'

export function repeatSummary(a: Alarm) {
  const days = a.weekdays
  if (days.length === 0) return 'Once'
  if (days.length === 7) return 'Every day'
  if (sameSet(days, WORKDAYS)) return 'Weekdays'
  if (sameSet(days, WEEKEND)) return 'Weekends'
  return [...days].sort((x, y) => ((x + 5) % 7) - ((y + 5) % 7)).map(weekdayShort).join(', ')
}

/** Next scheduled time strictly after `after`, ignoring dismissal. */
export function nextOccurrence(a: Alarm, after: number): number | undefined {
  const base = new Date(after)
  for (let i = 0; i <= 8; i++) {
    const d = new Date(base)
    d.setDate(base.getDate() + i)
    d.setHours(a.hour, a.minute, 0, 0)
    const t = d.getTime()
    if (t <= after) continue
    if (a.weekdays.length === 0 || a.weekdays.includes(weekdayOf(t))) return t
  }
  return undefined
}

/** Next time it actually rings (skips a dismissed ring). */
export function nextFire(a: Alarm, after: number): number | undefined {
  if (!a.isEnabled) return undefined
  let cursor = after
  for (let i = 0; i < 3; i++) {
    const t = nextOccurrence(a, cursor)
    if (t === undefined) return undefined
    if (a.skippedOccurrence !== undefined && Math.abs(a.skippedOccurrence - t) < 1000) {
      if (a.weekdays.length === 0) return undefined
      cursor = t
      continue
    }
    return t
  }
  return undefined
}

export function nextAlarm(alarms: Alarm[], now: number) {
  let best: { alarm: Alarm; date: number } | undefined
  for (const a of alarms) {
    const t = nextFire(a, now)
    if (t !== undefined && (!best || t < best.date)) best = { alarm: a, date: t }
  }
  return best
}

// MARK: - To-dos

export const isOverdue = (t: Todo, now: number) => !t.isDone && t.due !== undefined && t.due <= now

export function sortTodos(todos: Todo[]) {
  return [...todos].sort((a, b) => {
    if (a.isDone !== b.isDone) return a.isDone ? 1 : -1
    if (a.due !== undefined && b.due !== undefined && a.due !== b.due) return a.due - b.due
    if (a.due !== undefined && b.due === undefined) return -1
    if (a.due === undefined && b.due !== undefined) return 1
    return a.createdAt - b.createdAt
  })
}

export interface Suggestion { title: string; date: number }

export function dueSuggestions(now: number): Suggestion[] {
  const result: Suggestion[] = []
  const d = new Date(now)
  const minutesNow = d.getHours() * 60 + d.getMinutes()
  const at = (dayOffset: number, h: number) => {
    const x = new Date(now)
    x.setDate(x.getDate() + dayOffset)
    x.setHours(h, 0, 0, 0)
    return x.getTime()
  }
  const inHour = new Date(now + 3600_000)
  inHour.setSeconds(0, 0)
  inHour.setMinutes(Math.ceil(inHour.getMinutes() / 5) * 5)
  result.push({ title: 'In 1 hour', date: inHour.getTime() })
  if (minutesNow < 12 * 60) result.push({ title: 'This afternoon', date: at(0, 15) })
  if (minutesNow < 16 * 60) result.push({ title: 'This evening', date: at(0, 18) })
  if (minutesNow < 20 * 60 + 30) result.push({ title: 'Tonight', date: at(0, 21) })
  result.push({ title: 'Tomorrow morning', date: at(1, 9) })
  if (minutesNow >= 16 * 60) result.push({ title: 'Tomorrow evening', date: at(1, 18) })
  const weekday = d.getDay() + 1
  if (weekday >= 2 && weekday <= 5) result.push({ title: 'This weekend', date: at(7 - weekday, 10) })
  else result.push({ title: 'Next week', date: at(weekday === 1 ? 1 : 9 - weekday, 9) })
  return result
}

export const TIMES_OF_DAY = [
  { title: 'Morning', hour: 9 },
  { title: 'Noon', hour: 12 },
  { title: 'Afternoon', hour: 15 },
  { title: 'Evening', hour: 18 },
  { title: 'Night', hour: 21 },
]

/** Keep the day, set the time; if that's already past, the next day. */
export function applyTimeOfDay(date: number, hour: number, now: number) {
  const d = new Date(date)
  d.setHours(hour, 0, 0, 0)
  if (d.getTime() <= now) d.setDate(d.getDate() + 1)
  return d.getTime()
}

// MARK: - Notes

export const noteTitle = (n: Note) => n.title.trim() || n.body.split('\n').find((l) => l.trim())?.trim() || 'New Note'

export function notePreview(n: Note) {
  const lines = n.body.split('\n').map((l) => l.trim()).filter(Boolean)
  if (!n.title.trim() && lines.length) lines.shift()
  return lines.join(' ')
}

export const noteCopyText = (n: Note) => [n.title.trim(), n.body.trim()].filter(Boolean).join('\n\n')

export function sortNotes(notes: Note[], sort: NotesSort) {
  return [...notes].sort((a, b) => {
    if (a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1
    switch (sort) {
      case 'manual': return a.sortIndex !== b.sortIndex ? a.sortIndex - b.sortIndex : b.updatedAt - a.updatedAt
      case 'edited': return b.updatedAt - a.updatedAt
      case 'created': return b.createdAt - a.createdAt
      case 'title': return noteTitle(a).localeCompare(noteTitle(b), undefined, { sensitivity: 'base' })
    }
  })
}

// MARK: - Up Next (widget)

export type UpNextItem =
  | { kind: 'alarmSoon'; alarm: Alarm; date: number }
  | { kind: 'timer'; timer: TimerItem }
  | { kind: 'todo'; todo: Todo }
  | { kind: 'nextAlarm'; alarm: Alarm; date: number }

export function upNext(alarms: Alarm[], todos: Todo[], timers: TimerItem[], now: number, headsUpMinutes: number): UpNextItem[] {
  const headsUp = headsUpMinutes * 60_000
  const result: UpNextItem[] = []
  const soonIDs = new Set<string>()
  const urgent: { date: number; item: UpNextItem }[] = []
  for (const a of alarms.filter((x) => x.isEnabled)) {
    {
      // A dismissed ring is skipped by nextFire, so it simply disappears.
      const t = nextFire(a, now)
      if (t !== undefined && t - now <= headsUp) {
        urgent.push({ date: t, item: { kind: 'alarmSoon', alarm: a, date: t } })
        soonIDs.add(a.id)
      }
    }
  }
  result.push(...urgent.sort((x, y) => x.date - y.date).map((x) => x.item))

  const rank = (t: TimerItem): [number, number] =>
    t.state === 'ringing' || (t.state === 'running' && t.fireDate <= now) ? [0, 0]
      : t.state === 'running' ? [1, t.fireDate - now] : [2, t.remaining]
  result.push(...[...timers].sort((a, b) => {
    const [ra, va] = rank(a), [rb, vb] = rank(b)
    return ra !== rb ? ra - rb : va - vb
  }).map((timer) => ({ kind: 'timer' as const, timer })))

  const open = sortTodos(todos.filter((t) => !t.isDone))
  const overdue = open.filter((t) => isOverdue(t, now))
  const dueSoon = open.filter((t) => t.due !== undefined && t.due > now && t.due - now <= 3 * 3600_000)
  result.push(...[...overdue, ...dueSoon].map((todo) => ({ kind: 'todo' as const, todo })))

  const next = nextAlarm(alarms.filter((a) => !soonIDs.has(a.id)), now)
  if (next && next.date - now <= DAY) result.push({ kind: 'nextAlarm', alarm: next.alarm, date: next.date })

  const shown = new Set([...overdue, ...dueSoon].map((t) => t.id))
  result.push(...open.filter((t) => !shown.has(t.id)).map((todo) => ({ kind: 'todo' as const, todo })))
  return result
}
