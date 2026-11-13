import { createContext, useContext } from 'react'

/** True inside a landscape phone frame, so tabs can switch to their sideways layouts. */
export const LandscapeContext = createContext(false)
export const useLandscape = () => useContext(LandscapeContext)
