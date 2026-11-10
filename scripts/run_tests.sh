#!/usr/bin/env bash
# Unit (Swift Testing) + UI tests (incl. accessibility audit), then performance tests into
# build.nosync/perf.xcresult for perf_gate.py.
#
#   ./scripts/run_tests.sh            # unit + ui + perf
#   ./scripts/run_tests.sh unit|ui|perf
#
# VELO_REUSE_PASSED=1 (ship.sh sets it): skip the unit or UI suite when it already passed on
# exactly these sources (build.nosync/passed-*), so a ship right after a green run does not
# spend ~5 minutes repeating it. Performance tests always run (they are a measurement).
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
# try: run and report, return xcodebuild's status. run: the same, but a failure ends the script.
try() {
  local label="$1"; shift
  local log="build.nosync/$label.log"
  set +e; xcodebuild test "${COMMON[@]}" "$@" >"$log" 2>&1; local rc=$?; set -e
  # details to stderr so callers capturing the log path still show them
  grep -E "error:|Test Case .*failed|✘|\*\* TEST" "$log" | cut -c1-400 | tail -60 >&2 || true
  return $rc
}
run() {
  try "$@" || { echo "$1: FAILED (log build.nosync/$1.log)" >&2; exit 1; }
  echo "build.nosync/$1.log"
}

# Everything a test result depends on: app + test sources, the project (minus the build
# number, which a ship bumps after the gates) and these scripts.
sources_hash() {
  { find VeloMaps VeloMapsTests VeloMapsUITests -type f ! -name .DS_Store -print0 | sort -z | xargs -0 shasum
    grep -v CURRENT_PROJECT_VERSION project.yml; cat scripts/run_tests.sh scripts/sim.sh; xcodebuild -version
  } | shasum | cut -d" " -f1
}
already_passed() {   # $1 = unit|ui
  [ "${VELO_REUSE_PASSED:-}" = 1 ] && [ "$(cat "build.nosync/passed-$1" 2>/dev/null)" = "$(sources_hash)" ]
}

unit() {
  echo "== unit (Swift Testing) =="
  if already_passed unit; then echo "unit: already passed on these exact sources — not repeated"; return; fi
  # Separate scheme + derived data: the unit-test host app never reaches the simulator
  # install the UI tests and smoke test use.
  log=$(run unit -scheme VeloMapsUnit -derivedDataPath build.nosync/dd-unit -only-testing:VeloMapsTests | tail -1)
  grep -qE "Test run with [1-9][0-9]* tests? in [0-9]+ suites? passed" "$log" \
    || { echo "unit: no Swift Testing run found in $log"; exit 1; }
  grep -E "Test run with" "$log" | tail -1
  sources_hash > build.nosync/passed-unit
}

ui() {
  echo "== ui + accessibility audit =="
  if already_passed ui; then echo "ui: already passed on these exact sources — not repeated"; return; fi
  rm -f build.nosync/passed-ui
  # Feature tests first, the accessibility audit last: right after a simulator boot the audit
  # tool cannot attach for several minutes ("Invalid target app", -902), which failed a whole
  # ship on 11/9. Running it last gives the simulator time to settle.
  log=$(run ui "${APP_DD[@]}" -only-testing:VeloMapsUITests -skip-testing:VeloMapsUITests/PerformanceTests \
        -skip-testing:VeloMapsUITests/AccessibilityAuditTests | tail -1)
  n=$(grep -cE "Test Case .*passed" "$log" || true)
  [ "$n" -gt 0 ] || { echo "ui: zero UI tests ran"; exit 1; }
  # Only an attach failure is retried (once, after a pause). A real finding fails at once.
  local alog=build.nosync/audit.log
  if ! try audit "${APP_DD[@]}" -only-testing:VeloMapsUITests/AccessibilityAuditTests; then
    if grep -q "Code=-902" "$alog" && ! grep -q "accessibility issue(s)" "$alog"; then
      echo "audit: the tool could not attach — one more try in 60 s" >&2
      sleep 60
      try audit "${APP_DD[@]}" -only-testing:VeloMapsUITests/AccessibilityAuditTests \
        || { echo "audit: FAILED (log $alog)" >&2; exit 1; }
    else
      echo "audit: FAILED (log $alog)" >&2; exit 1
    fi
  fi
  a=$(grep -cE "Test Case .*AccessibilityAuditTests.*passed" "$alog" || true)
  [ "$a" -gt 0 ] || { echo "ui: accessibility audit did not run"; exit 1; }
  echo "ui: $((n + a)) test(s) passed ($a audit screens)"
  sources_hash > build.nosync/passed-ui
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
