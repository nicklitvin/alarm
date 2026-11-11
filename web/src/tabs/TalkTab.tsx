import { useEffect, useRef, useState } from 'react'
import { TabHeader } from '../components/ui'
import { respond } from '../logic/assistant'
import { uid } from '../logic/model'
import { useStore, type ChatMessage } from '../logic/store'

/** Sends a message to the canned assistant and records the reply + attachment events. */
export function useAsk() {
  const { data, update } = useStore()
  const latest = useRef(data)
  latest.current = data
  return (text: string): Promise<string> => new Promise((resolve) => {
    update((d) => ({ ...d, chat: [...d.chat, { id: uid(), role: 'user', text }] }))
    // A short "thinking" pause so the typing indicator can be reviewed.
    setTimeout(() => {
      const result = respond(text, latest.current, Date.now())
      update(() => ({ ...result.data, chat: [...result.data.chat, ...result.events, { id: uid(), role: 'assistant', text: result.reply }] }))
      resolve(result.reply)
    }, 650)
  })
}

export function TalkTab() {
  const { data, open } = useStore()
  const ask = useAsk()
  const [draft, setDraft] = useState('')
  const [live, setLive] = useState(false)
  const [thinking, setThinking] = useState(false)
  const bottom = useRef<HTMLDivElement>(null)

  useEffect(() => {
    // Scroll the phone's content only (not the browser page).
    const body = bottom.current?.closest('.app-body')
    body?.scrollTo({ top: body.scrollHeight, behavior: 'smooth' })
  }, [data.chat.length, thinking])

  const send = async () => {
    const text = draft.trim()
    if (!text) return
    setDraft('')
    setThinking(true)
    await ask(text)
    setThinking(false)
  }

  const wake = data.settings.wakeWordEnabled ? data.settings.wakeWord : null
  return (
    <>
      <TabHeader tab="talk" plain />
      <div className="chat">
        {data.chat.length === 0 && !live && (
          <div className="talk-empty" style={{ paddingTop: 90 }}>
            <div className="big">〰︎</div>
            <h3>Ask Me Anything</h3>
            Tap the waveform{wake ? ` and say “${wake}, …”` : ' to talk'}, or type below. Try “wake me up at 7 on weekdays” or “remind me to call mom tomorrow at 6”.
          </div>
        )}
        {data.chat.map((m) => <Message key={m.id} message={m} onOpen={open} />)}
        {thinking && <div className="bubble assistant" style={{ letterSpacing: 2 }}>•••</div>}
        <div ref={bottom} style={{ height: 120 }} />
      </div>
      <div className="input-bar">
        {live && (
          <div className="live">
            <div className="orb" />
            <div className="grow">
              <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--secondary)' }}>{wake ? `Listening for “${wake}”…` : 'Listening…'}</div>
              <div style={{ fontSize: 14 }}>Preview: speech isn't simulated, type instead.</div>
            </div>
          </div>
        )}
        <div className="line">
          <input placeholder="Message" value={draft} onChange={(e) => setDraft(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && send()} />
          {draft.trim() && <button className="round" aria-label="Send" onClick={send}>↑</button>}
          <button className={`round ${live ? 'stop' : ''}`} aria-label={live ? 'Stop Live Talk' : 'Start Live Talk'} onClick={() => setLive(!live)}>{live ? '■' : '〰︎'}</button>
        </div>
      </div>
    </>
  )
}

function Message({ message, onOpen }: { message: ChatMessage; onOpen: (link: NonNullable<ChatMessage['link']>) => void }) {
  if (message.role === 'event') {
    // Like an attachment the assistant sent: left-aligned card, opens the item.
    const [title, ...rest] = message.text.split(' · ')
    const body = (
      <>
        <div className="tile">{message.icon}</div>
        <div><b>{title}</b>{rest.length > 0 && <span>{rest.join(' · ')}</span>}</div>
        {message.link && <span className="chev">›</span>}
      </>
    )
    return message.link
      ? <button className="attachment" onClick={() => onOpen(message.link!)}>{body}</button>
      : <div className="attachment">{body}</div>
  }
  return <div className={`bubble ${message.role}`}>{message.text}</div>
}
