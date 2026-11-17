// A canned stand-in for the app's on-device assistant, just enough to exercise the chat UI.
// It is NOT the real model. Like the app's assistant, it only has timer tools: it starts, pauses,
// resumes and cancels countdown timers, and can't touch alarms, to-dos, notes, the stopwatch or
// settings. Running timers show as cards at the top of Talk, so replies stay short.
import { addRecent, durationName, uid } from './model'
import type { AppData, ChatMessage } from './store'

export function respond(input: string, data: AppData, now: number): { data: AppData; reply: string; events: ChatMessage[] } {
  const lower = input.trim().toLowerCase()

  // Start: "set a pasta timer for 9 minutes", "timer for 5 min"
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
      events: [],
    }
  }

  // Pause, resume or cancel: "pause my timer", "cancel the pasta timer", "cancel all timers"
  const action = /\b(pause|stop)\b/.test(lower) && !/cancel/.test(lower) ? 'pause' : /\b(resume|continue|unpause)\b/.test(lower) ? 'resume' : /\b(cancel|delete|clear)\b/.test(lower) ? 'cancel' : null
  if (action && lower.includes('timer')) {
    const name = lower.match(/(?:the|my)\s+(\w+)\s+timer/)?.[1]
    const matches = data.timers.filter((t) => !name || ['my', 'the', 'all'].includes(name) || t.label.toLowerCase().includes(name))
      .filter((t) => action === 'pause' ? t.state === 'running' : action === 'resume' ? t.state === 'paused' : true)
    if (!matches.length) return { data, reply: 'No matching timer.', events: [] }
    const ids = new Set(matches.map((t) => t.id))
    const timers = data.timers.flatMap((t) => {
      if (!ids.has(t.id)) return [t]
      if (action === 'cancel') return []
      return action === 'pause'
        ? [{ ...t, state: 'paused' as const, remaining: Math.max(0, (t.fireDate - now) / 1000) }]
        : [{ ...t, state: 'running' as const, fireDate: now + t.remaining * 1000 }]
    })
    const verb = { pause: 'Paused', resume: 'Resumed', cancel: 'Cancelled' }[action]
    return { data: { ...data, timers }, reply: `${verb} ${matches.length === 1 ? 'the timer' : `${matches.length} timers`}.`, events: [] }
  }

  // Everything else in the app is off limits for the assistant.
  if (/\b(alarm|wake me|to-?dos?|remind|note|stop ?watch|settings?)\b/.test(lower)) {
    return { data, reply: 'I can only help with timers here. Use that tab for the rest.', events: [] }
  }

  return { data, reply: 'This web preview only fakes timers. Try “set a pasta timer for 9 minutes” or “pause my timer”.', events: [] }
}
