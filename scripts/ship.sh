#!/usr/bin/env bash
# Velo Maps — quality gates, smoke test, bump build, archive, export, upload to TestFlight.
# TestFlight only: nothing here submits to App Review.
#
#   ./scripts/ship.sh notes.txt      # notes.txt = TestFlight "What to Test" (paragraphs)
#
# Gates, in order (Apple quality gates, owner rule for every TestFlight push):
#   1. test coverage from source   2. Swift Testing unit suites
#   3. UI tests + accessibility audit   4. XCTMetric launch perf vs. baseline
#   5. MetricKit wired + Organizer report (report-only)   6. cold-launch smoke test
set -euo pipefail
cd "$(dirname "$0")/.."
# A ship started by hand had nothing keeping this Mac awake (it idle-sleeps on
# battery after a minute); the nightly jobs already run under caffeinate.
# Ends with this script; a closed lid still sleeps the Mac (2026-11-09).
[[ -n "${DAILY_SHIP_AWAKE:-}" ]] || /usr/bin/caffeinate -i -w $$ &
# Stage times, memory peaks and one SHIP SUMMARY line per run, pass or fail
# (scripts/ship_log.sh, scripts/ship_summary.py; history in build/ship-history.jsonl).
SHIP_LOG_DIR=build
# shellcheck disable=SC1091
source scripts/ship_log.sh
ship_log_start
NOTES="${1:?usage: ship.sh notes.txt}"
[ -f "$NOTES" ] || { echo "no notes file $NOTES"; exit 1; }
PY=~/.venvs/spendcap/bin/python

# shellcheck disable=SC1091
source scripts/asc-config.env
[ -n "${ASC_APP_ID:-}" ] || { echo "ASC_APP_ID empty in scripts/asc-config.env"; exit 1; }

# One build at a time on this Mac (owner rule) — wait for anyone else's xcodebuild.
# pgrep -x matches the process name only; -f would match this script's own text.
while pgrep -x xcodebuild >/dev/null; do echo "waiting for another xcodebuild…"; sleep 15; done

stage "1. test coverage"
python3 -I scripts/check_test_coverage.py

stage "5a. MetricKit wired"
grep -q "MXMetricManager.shared.add" VeloMaps/Metrics.swift && grep -q "Metrics.shared.start()" VeloMaps/VeloMapsApp.swift \
  || { echo "MetricKit subscriber not wired"; exit 1; }

./scripts/generate.sh >/dev/null
stage "2-4. unit, UI + accessibility audit, performance"
./scripts/run_tests.sh all
stage "4b. perf gate"
python3 -I scripts/perf_gate.py build.nosync/perf.xcresult

stage "6. smoke test"
./scripts/smoke_test.sh
xcrun simctl shutdown "$(./scripts/sim.sh)" 2>/dev/null || true   # one sim at a time; free RAM for the archive

stage "5b. Organizer report (report-only)"
$PY scripts/organizer_report.py || true

current=$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | sed -E 's/.*"([0-9]+)".*/\1/')
next=$((current + 1))
stage "bumping build $current -> $next"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$current\"/CURRENT_PROJECT_VERSION: \"$next\"/" project.yml
./scripts/generate.sh >/dev/null

AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
ARCHIVE=build.nosync/VeloMaps.xcarchive
EXPORT=build.nosync/export
rm -rf "$ARCHIVE" "$EXPORT"

stage "archiving"
xcodebuild -project VeloMaps.xcodeproj -scheme VeloMaps -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" -jobs 4 \
  -allowProvisioningUpdates "${AUTH[@]}" archive 2>&1 | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" | sort -u
[ -d "$ARCHIVE" ] || { echo "archive failed"; exit 1; }

stage "exporting IPA"
# System PATH: Homebrew's rsync breaks Xcode's IPA export ("Copy failed").
env PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates "${AUTH[@]}" 2>&1 | grep -E "error:|EXPORT (SUCCEEDED|FAILED)" | sort -u
IPA=$(ls "$EXPORT"/*.ipa 2>/dev/null | head -1)
[ -n "$IPA" ] || { echo "export failed"; exit 1; }

stage "uploading build $next to TestFlight"
xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

stage "recording perf baseline (passing ship)"
python3 -I scripts/perf_gate.py build.nosync/perf.xcresult --record

stage "internal testers (automatic distribution)"
$PY scripts/configure_internal_testers.py

stage "What to Test (waits for processing)"
$PY scripts/set_whats_new.py "$next" "$NOTES"

stage "shipped Velo Maps 1.0 ($next) to TestFlight"

# Reached the end: the summary line reports this ship as ok.
ship_done
