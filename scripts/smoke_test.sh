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
# Wait up to 20 s for it to appear (a cold launch right after the perf tests can take longer
# than a fixed 6 s — that false failure blocked a ship on 11/8), then require it to still be
# running 3 s later, which is what catches a crash on launch.
running() {
  # Capture, then match (grep -q under pipefail SIGPIPEs the producer = false failure).
  local list; list=$(xcrun simctl spawn "$SIM" launchctl list 2>/dev/null || true)
  printf '%s' "$list" | grep -q "com.divinedavis.velomaps"
}
for _ in $(seq 1 20); do running && break; sleep 1; done
sleep 3
if running; then
  echo "SMOKE OK — Velo Maps is running after a cold launch"
else
  echo "SMOKE FAILED — Velo Maps is not running"; exit 1
fi
