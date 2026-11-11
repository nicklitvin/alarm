#!/usr/bin/env bash
# Runs the scheduling/model logic tests with plain swiftc (works on macOS or Linux).
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
cp Tests/LogicTests.swift "$out/main.swift"
swiftc -swift-version 5 -o "$out/tests" \
  Shared/AlarmItem.swift Shared/AlarmStorage.swift Shared/AppSettings.swift Shared/TimeFormat.swift \
  Shared/TodoItem.swift Shared/TimerItem.swift Shared/UpNext.swift Shared/DeepLink.swift App/Services/AlarmPlan.swift App/Talk/WakeWord.swift \
  App/Talk/NaturalTime.swift App/Todos/DueSuggestions.swift App/Talk/AssistantMatching.swift App/About/Changelog.swift App/Notes/Note.swift "$out/main.swift"
TZ=America/New_York LANG=en_US.UTF-8 "$out/tests"
