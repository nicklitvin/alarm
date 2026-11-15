import { createContext, useContext } from 'react'

/** True inside the Mac window (like iPad and the Mac's regular width): tabs switch to their wide layouts. */
export const WideContext = createContext(false)
export const useWide = () => useContext(WideContext)
