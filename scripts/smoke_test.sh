#!/usr/bin/env bash
# Cold-launch the built app in the simulator and prove it is running — a green build or
# XCUITest run (own harness) does not prove that.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=$(./scripts/sim.sh)
APP=build.nosync/dd/Build/Products/Debug-iphonesimulator/VeloMaps.app
[ -d "$APP" ] || { echo "no app at $APP — run run_tests.sh first"; exit 1; }
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl install "$SIM" "$APP"
xcrun simctl terminate "$SIM" com.divinedavis.velomaps 2>/dev/null || true
xcrun simctl launch "$SIM" com.divinedavis.velomaps >/dev/null
sleep 6
# Capture, then match (grep -q under pipefail SIGPIPEs the producer = false failure).
RUNNING=$(xcrun simctl spawn "$SIM" launchctl list 2>/dev/null || true)
if printf '%s' "$RUNNING" | grep -q "com.divinedavis.velomaps"; then
  echo "SMOKE OK — Velo Maps is running after a cold launch"
else
  echo "SMOKE FAILED — Velo Maps is not running"; exit 1
fi
