import { emptyStopwatch, uid, WORKDAYS, type Alarm, type Todo } from './model'
import { seedData, type AppData } from './store'

// Fixed example data for the gallery of widgets, notifications and other system views. Each
// shows one situation, independent of the data in your own preview.

const hour = 3600_000
const at = (now: number, minutesFromNow: number) => {
  const d = new Date(now + minutesFromNow * 60_000)
  return { hour: d.getHours(), minute: Math.floor(d.getMinutes() / 5) * 5 }
}
const todos = (now: number): Todo[] => [
  { id: uid(), title: 'Pay electricity bill', details: '', due: now - 2 * hour, isDone: false, createdAt: now - 9 * hour },
  { id: uid(), title: 'Call mom', details: 'Ask about Sunday dinner', due: now + 2 * hour, isDone: false, createdAt: now - 3 * hour },
  { id: uid(), title: 'Dentist appointment', details: '', due: now + 50 * hour, isDone: false, createdAt: now - 5 * hour },
  { id: uid(), title: 'Read a book', details: '', isDone: false, createdAt: now - 7 * hour },
  { id: uid(), title: 'Water the plants', details: '', isDone: false, createdAt: now - 8 * hour },
  { id: uid(), title: 'Book flights', details: '', isDone: false, createdAt: now - 10 * hour },
]
const base = (now: number): AppData => ({ ...seedData(now), timers: [], stopwatch: emptyStopwatch, chat: [] })

/** An alarm within 12 hours (Dismiss shows), more to-dos than fit. */
export function alarmSoon(now: number): AppData {
  const alarms: Alarm[] = [
    { id: uid(), ...at(now, 40), label: 'Gym', weekdays: [1, 2, 3, 4, 5, 6, 7], isEnabled: true },
    { id: uid(), hour: 7, minute: 0, label: 'Wake up', weekdays: WORKDAYS, isEnabled: true },
  ]
  return { ...base(now), alarms, todos: todos(now) }
}

/** The next alarm is days away (no Dismiss yet, lock screen shows zzz). */
export function alarmFar(now: number): AppData {
  const d = new Date(now + 3 * 24 * hour)
  const weekday = (d.getDay() + 1) as Alarm['weekdays'][number]
  const alarms: Alarm[] = [{ id: uid(), hour: 9, minute: 0, label: '', weekdays: [weekday], isEnabled: true }]
  const s = base(now)
  return { ...s, alarms, todos: todos(now).slice(0, 3) }
}

/** No alarms set; just to-dos. */
export function noAlarms(now: number): AppData {
  return { ...base(now), alarms: [], todos: todos(now) }
}

/** Nothing at all: no alarms, no to-dos. */
export function empty(now: number): AppData {
  return { ...base(now), alarms: [], todos: [] }
}

/** A running timer, for Live Activities and the lock screen. */
export function timerRunning(now: number): AppData {
  return { ...alarmSoon(now), timers: [{ id: uid(), label: 'Pasta', duration: 540, state: 'running', fireDate: now + 312_000, remaining: 540 }] }
}

/** A paused timer. */
export function timerPaused(now: number): AppData {
  return { ...alarmSoon(now), timers: [{ id: uid(), label: 'Tea', duration: 300, state: 'paused', fireDate: now, remaining: 120 }] }
}

/** Notifications: the alarm heads-up, a due to-do and its early reminder. */
export function notifications(now: number): AppData {
  const s = alarmSoon(now)
  return { ...s, settings: { ...s.settings, todoEarlyReminderMinutes: 60 } }
}
