# Alarm — web UI preview

A browser copy of the iOS app's screens, for reviewing design without building in Xcode.

- **Not part of the app.** The iOS project only builds `App/`, `Shared/` and `CHANGELOG.json`; this folder is never included.
- **Nothing real happens.** Alarms and timers never ring, nothing sends notifications, and the assistant is a canned stand-in that understands a few example requests.
- Everything you change is saved in your browser (use **Reset demo data** to start over).
- The About & Updates screen shows the real patch notes from `../CHANGELOG.json`.

## Run locally

```sh
cd web
npm install
npm run dev        # http://localhost:5173
```

## Deploy on Vercel

1. In Vercel, **Add New → Project** and import this GitHub repo.
2. Set **Root Directory** to `web`. Vercel detects Vite; `vercel.json` sets the build to `npm run build` with output `dist`.
3. Leave **Include files outside the root directory in the Build Step** on (the default). The About screen reads `../CHANGELOG.json`.
4. Deploy. Every push to `main` redeploys.

## Keeping it in sync

The logic in `src/logic/model.ts` mirrors the Swift code (next ring, repeat summaries, deadline suggestions, Up Next ranking).
When the app's UI or behaviour changes, update the matching screen in `src/tabs/` or `src/components/`.
