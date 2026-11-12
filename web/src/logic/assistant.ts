// A canned stand-in for the app's on-device assistant, just enough to exercise the chat UI
// (attachment cards, links into tabs). It is NOT the real model.
import {
  addRecent, alarmTitle, durationName, dueDescription, noteTitle, repeatSummary, timeString, uid, WEEKEND, WORKDAYS, type Alarm, type Weekday,
} from './model'
import type { AppData, ChatMessage } from './store'

const DAY_NAMES = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']

function parseDays(text: string): Weekday[] | null {
  const t = text.toLowerCase()
  if (/\b(every ?day|daily)\b/.test(t)) return [1, 2, 3, 4, 5, 6, 7]
  if (/\bweekdays?\b|mon-fri|monday to friday/.test(t)) return WORKDAYS
  if (/\bweekends?\b/.test(t)) return WEEKEND
  const days = DAY_NAMES.flatMap((name, i) => (new RegExp(`\\b${name.slice(0, 3)}`).test(t) ? [(i + 1) as Weekday] : []))
  return days.length ? days : null
}

function parseTime(text: string): { hour: number; minute: number } | null {
  const m = text.toLowerCase().match(/\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/)
  if (!m) return null
  let hour = Number(m[1])
  const minute = Number(m[2] ?? 0)
  if (m[3] === 'pm' && hour < 12) hour += 12
  if (m[3] === 'am' && hour === 12) hour = 0
  if (hour > 23 || minute > 59) return null
  return { hour, minute }
}

const event = (text: string, icon: string, link?: ChatMessage['link']): ChatMessage => ({ id: uid(), role: 'event', text, icon, link })

export function respond(input: string, data: AppData, now: number): { data: AppData; reply: string; events: ChatMessage[] } {
  const text = input.trim()
  const lower = text.toLowerCase()

  // Timers: "set a pasta timer for 9 minutes"
  const dur = lower.match(/(\d+)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b/)
  if (lower.includes('timer') && dur) {
    const n = Number(dur[1])
    const seconds = dur[2].startsWith('h') ? n * 3600 : dur[2].startsWith('m') ? n * 60 : n
    const label = lower.match(/(?:a|an|the)?\s*(\w+)\s+timer/)?.[1]
    const name = label && !['a', 'set', 'start', 'new'].includes(label) ? label[0].toUpperCase() + label.slice(1) : ''
    const timer = { id: uid(), label: name, duration: seconds, state: 'running' as const, fireDate: now + seconds * 1000, remaining: seconds }
    return {
      data: { ...data, timers: [...data.timers, timer], recents: addRecent(data.recents, { duration: seconds, label: name }) },
      reply: `Started a timer for ${durationName(seconds)}${name ? ` called ${name}` : ''}.`,
      events: [event(`Timer · ${name || durationName(seconds)} · ${durationName(seconds)}`, '⏱', { tab: 'timers' })],
    }
  }

  // Change an alarm's days or time: "change my gym alarm to weekdays"
  if (/(change|move|set|make)\b.*\balarm\b/.test(lower) && data.alarms.length) {
    const target = data.alarms.find((a) => a.label && lower.includes(a.label.toLowerCase())) ?? data.alarms[0]
    const days = parseDays(lower.split(' to ').slice(1).join(' ') || lower)
    const time = parseTime(lower.split(' to ').slice(1).join(' '))
    if (days || time) {
      const updated: Alarm = { ...target, ...(days ? { weekdays: days } : {}), ...(time ?? {}), isEnabled: true, skippedOccurrence: undefined }
      return {
        data: { ...data, alarms: data.alarms.map((a) => (a.id === target.id ? updated : a)) },
        reply: `Done. ${alarmTitle(updated)} now rings at ${timeString(updated.hour, updated.minute)}, ${repeatSummary(updated).toLowerCase()}.`,
        events: [event(`Alarm updated · ${timeString(updated.hour, updated.minute)} · ${repeatSummary(updated)}`, '⏰', { tab: 'alarms', id: updated.id })],
      }
    }
  }

  // New alarm: "wake me up at 6:45 on weekdays"
  if (/wake me|\balarm\b/.test(lower)) {
    const time = parseTime(lower)
    if (time) {
      const alarm: Alarm = { id: uid(), ...time, label: '', weekdays: parseDays(lower) ?? [], isEnabled: true }
      return {
        data: { ...data, alarms: [...data.alarms, alarm] },
        reply: `Alarm set for ${timeString(alarm.hour, alarm.minute)}, ${repeatSummary(alarm).toLowerCase()}.`,
        events: [event(`Alarm set · ${timeString(alarm.hour, alarm.minute)} · ${repeatSummary(alarm)}`, '⏰', { tab: 'alarms', id: alarm.id })],
      }
    }
  }

  // Notes: "add eggs to my grocery note", "what's on my packing note?"
  const append = text.match(/add (.+) to (?:my |the )?(.+?) note/i)
  const read = text.match(/what(?:'s| is) (?:on|in) (?:my |the )?(.+?) note/i)
  const findNote = (q: string) => data.notes.find((n) => noteTitle(n).toLowerCase().includes(q.toLowerCase()))
  if (append) {
    const note = findNote(append[2])
    if (!note) return { data, reply: `I couldn't find a note called “${append[2]}”.`, events: [] }
    const body = note.body.trim() ? `${note.body.trim()}\n${append[1]}` : append[1]
    return {
      data: { ...data, notes: data.notes.map((n) => (n.id === note.id ? { ...n, body, updatedAt: now } : n)) },
      reply: `Added “${append[1]}” to ${noteTitle(note)}.`,
      events: [event(`Note updated · ${noteTitle(note)}`, '🗒', { tab: 'notes', id: note.id })],
    }
  }
  if (read) {
    const note = findNote(read[1])
    if (!note) return { data, reply: `I couldn't find a note called “${read[1]}”.`, events: [] }
    const items = note.body.split('\n').map((l) => l.trim()).filter(Boolean)
    return { data, reply: `${noteTitle(note)}: ${items.join(', ')}.`, events: [event(`Read note · ${noteTitle(note)}`, '🗒', { tab: 'notes', id: note.id })] }
  }

  // To-dos: "remind me to call mom tomorrow at 6"
  const todoMatch = text.match(/remind me to (.+)/i) ?? text.match(/add (?:a )?to-?do:? (.+)/i)
  if (todoMatch) {
    let title = todoMatch[1]
    let due: number | undefined
    const time = parseTime(title.replace(/\b(\d{1,2})(?::\d{2})?\s*(am|pm)?\b(?!.*\d)/, (m) => m))
    const dayOffset = /tomorrow/i.test(title) ? 1 : /tonight|today/i.test(title) ? 0 : null
    if (dayOffset !== null || time) {
      const d = new Date(now)
      d.setDate(d.getDate() + (dayOffset ?? 0))
      let hour = time?.hour ?? (/tonight/i.test(title) ? 21 : 9)
      if (time && hour < 12 && !/am/i.test(title) && (/tonight|evening/i.test(title) || hour < 7)) hour += 12
      d.setHours(hour, time?.minute ?? 0, 0, 0)
      if (dayOffset === null && d.getTime() <= now) d.setDate(d.getDate() + 1)
      due = d.getTime()
      title = title.replace(/\s*(tomorrow|tonight|today)\b/i, '').replace(/\s*(at\s*)?\d{1,2}(:\d{2})?\s*(am|pm)?\s*$/i, '').trim()
    }
    const todo = { id: uid(), title: title[0].toUpperCase() + title.slice(1), details: '', due, isDone: false, createdAt: now }
    return {
      data: { ...data, todos: [...data.todos, todo] },
      reply: `Added “${todo.title}”${due ? `, due ${dueDescription(due, now)}` : ''}.`,
      events: [event(`To-do added · ${todo.title}${due ? ` · ${dueDescription(due, now)}` : ''}`, '☑︎', { tab: 'todos', id: todo.id })],
    }
  }

  // Settings: "turn off spoken replies"
  if (/spoken replies|speak replies|read.*aloud/.test(lower)) {
    const on = !/\boff\b|stop|don't/.test(lower)
    return {
      data: { ...data, settings: { ...data.settings, speakReplies: on } },
      reply: `Spoken replies are now ${on ? 'on' : 'off'}.`,
      events: [event(`Settings · spoken replies ${on ? 'on' : 'off'}`, '⚙︎')],
    }
  }

  return {
    data,
    reply: 'This web preview only fakes a few requests. Try “set a pasta timer for 9 minutes”, “wake me up at 6:45 on weekdays”, “change my gym alarm to weekends”, “remind me to call mom tomorrow at 6” or “what’s on my packing note?”',
    events: [],
  }
}
