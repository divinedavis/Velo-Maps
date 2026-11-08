#!/usr/bin/env bash
# Run just the accessibility audit and list issues per screen.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/generate.sh >/dev/null
while pgrep -x xcodebuild >/dev/null; do sleep 10; done
SIM=$(./scripts/sim.sh)
xcodebuild test -project VeloMaps.xcodeproj -scheme VeloMaps -destination "id=$SIM" -derivedDataPath build.nosync/dd -jobs 4 \
  -only-testing:VeloMapsUITests/AccessibilityAuditTests > build.nosync/audit.log 2>&1 || true
grep -E "Test Case .*(passed|failed)|BUILD FAILED|error: [^-]" build.nosync/audit.log | cut -c1-160 | sort -u
awk '/accessibility issue\(s\):/{print; f=1; next} f && /^(Contrast|Text|Hit|Element|Dynamic|Traits)/{print "   " $0; next} f{f=0}' build.nosync/audit.log \
  | sed 's|.*AccessibilityAuditTests \(test[A-Za-z]*\).*failed - |## \1: |' | cut -c1-200
