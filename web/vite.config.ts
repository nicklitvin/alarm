import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Web preview of the iOS app's UI. It reads ../CHANGELOG.json so the About screen shows the
// real patch notes, so the dev server is allowed to read one folder up.
export default defineConfig({
  plugins: [react()],
  server: { fs: { allow: ['..'] } },
})
