#!/usr/bin/env bash
# Raw App Store screenshots from the installed app on the dedicated sim, one screen per launch
# (demo routes, paused, 9:41 status bar). Output: marketing/raw/<name>.png
# Install the current build first (run_tests.sh ui or ship.sh leaves it installed).
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=$(./scripts/sim.sh)
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --cellularMode active
BID=com.divinedavis.velomaps
mkdir -p marketing/raw
shot() {   # name, wait seconds, launch args…
  local name="$1" wait="$2"; shift 2
  xcrun simctl terminate "$SIM" $BID 2>/dev/null || true
  xcrun simctl launch "$SIM" $BID -resetSettings YES "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$SIM" screenshot --type=png "marketing/raw/$name.png" >/dev/null 2>&1
  echo "captured $name"
}
shot drive          9 -demo drive -paused YES -progress 0.45
shot turn-lanes     9 -demo drive -paused YES -turnAhead 140
shot highway-sign   9 -demo drive -paused YES -signAhead 160 -signIndex 0
shot exit-sign      9 -demo drive -paused YES -signAhead 160 -signIndex 1
shot night          9 -demo drive -paused YES -progress 0.45 -night YES
shot report-menu   10 -demo drive -paused YES -progress 0.45 -reportMenu YES
shot walk           9 -demo bus -paused YES -mode walk
xcrun simctl terminate "$SIM" $BID 2>/dev/null || true
xcrun simctl status_bar "$SIM" clear
