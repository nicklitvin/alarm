#!/usr/bin/env bash
# Runs the scheduling/model logic tests with plain swiftc (works on macOS or Linux).
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
cp Tests/LogicTests.swift "$out/main.swift"
swiftc -swift-version 5 -o "$out/tests" \
  Shared/AlarmItem.swift Shared/AlarmStorage.swift Shared/TimeFormat.swift \
  App/Services/AlarmPlan.swift App/Talk/WakeWord.swift "$out/main.swift"
TZ=America/New_York LANG=en_US.UTF-8 "$out/tests"
