# Alarm app — notes for contributors

SwiftUI iOS 26 app (AlarmKit, WidgetKit, Foundation Models). The Xcode project is generated
from `project.yml` with XcodeGen; it is not committed.

## Releasing a change (every user-facing change)

1. Bump `MARKETING_VERSION` (semver: patch for fixes, minor for features) and increment
   `CURRENT_PROJECT_VERSION` by 1 in `project.yml`.
2. Add a new entry at the top of `CHANGELOG.json` with the same `version` and `build`, today's
   `date` (YYYY-MM-DD), a short `title`, and `notes` written for the user (plain language, what
   they can now do — not implementation details).
3. Run `./Tests/run.sh` — it fails if `project.yml` and `CHANGELOG.json` disagree.

`CHANGELOG.json` is bundled into the app for patch notes and What's New. Update checks use the App
Store (iTunes lookup by bundle ID), so a version only counts as "available" once it's on the App Store.

## Tests

`./Tests/run.sh` compiles the Foundation-only logic (scheduling, parsing, matching, versioning)
with plain `swiftc` and runs it; it works on Linux too. Keep new pure logic in files that only
import Foundation so it can be added there.

## Web preview (`web/`)

A Vite + React mock of the app's screens, deployed on Vercel for UI review. It is not part of the
Xcode build and never rings or notifies. When you change the iOS UI or behaviour, update the
matching screen in `web/src/` (logic mirrors live in `web/src/logic/model.ts`) and check that
`cd web && npm run build` passes.

