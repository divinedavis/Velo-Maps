#!/usr/bin/env bash
# Unit (Swift Testing) + UI tests (incl. accessibility audit), then performance tests into
# build.nosync/perf.xcresult for perf_gate.py.
#
#   ./scripts/run_tests.sh            # unit + ui + perf
#   ./scripts/run_tests.sh unit|ui|perf
set -euo pipefail
cd "$(dirname "$0")/.."
WHAT="${1:-all}"
./scripts/generate.sh >/dev/null   # new files must be in the project
SIM=$(./scripts/sim.sh)
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
DEST="id=$SIM"
mkdir -p build.nosync
# Signed (no CODE_SIGNING_ALLOWED=NO): since 11/7 unsigned simulator builds crash in dyld_sim
# before main (kernel: vm_shared_region_start_address() returned 0x1); signed ones launch.
COMMON=(-project VeloMaps.xcodeproj -destination "$DEST" -jobs 4)
APP_DD=(-scheme VeloMaps -derivedDataPath build.nosync/dd)

# Never trust "TEST SUCCEEDED" alone: xcodebuild passes with zero tests run.
run() {
  local label="$1"; shift
  local log="build.nosync/$label.log"
  set +e; xcodebuild test "${COMMON[@]}" "$@" >"$log" 2>&1; local rc=$?; set -e
  # details to stderr so callers capturing the log path still show them
  grep -E "error:|Test Case .*failed|✘|\*\* TEST" "$log" | cut -c1-400 | tail -60 >&2 || true
  [ $rc -eq 0 ] || { echo "$label: FAILED (log $log)" >&2; exit 1; }
  echo "$log"
}

unit() {
  echo "== unit (Swift Testing) =="
  # Separate scheme + derived data: the unit-test host app never reaches the simulator
  # install the UI tests and smoke test use.
  log=$(run unit -scheme VeloMapsUnit -derivedDataPath build.nosync/dd-unit -only-testing:VeloMapsTests | tail -1)
  grep -qE "Test run with [1-9][0-9]* tests? in [0-9]+ suites? passed" "$log" \
    || { echo "unit: no Swift Testing run found in $log"; exit 1; }
  grep -E "Test run with" "$log" | tail -1
}

ui() {
  echo "== ui + accessibility audit =="
  log=$(run ui "${APP_DD[@]}" -only-testing:VeloMapsUITests -skip-testing:VeloMapsUITests/PerformanceTests | tail -1)
  n=$(grep -cE "Test Case .*passed" "$log" || true)
  [ "$n" -gt 0 ] || { echo "ui: zero UI tests ran"; exit 1; }
  grep -q "AccessibilityAuditTests" "$log" || { echo "ui: accessibility audit did not run"; exit 1; }
  echo "ui: $n test(s) passed"
}

perf() {
  echo "== performance =="
  rm -rf build.nosync/perf.xcresult
  run perf "${APP_DD[@]}" -only-testing:VeloMapsUITests/PerformanceTests -resultBundlePath build.nosync/perf.xcresult >/dev/null
  echo "perf: results in build.nosync/perf.xcresult"
}

case "$WHAT" in
  unit) unit ;; ui) ui ;; perf) perf ;;
  all) unit; ui; perf ;;
  *) echo "usage: run_tests.sh [unit|ui|perf|all]"; exit 2 ;;
esac
