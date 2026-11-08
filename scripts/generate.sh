#!/usr/bin/env bash
# Regenerate VeloMaps.xcodeproj from project.yml. Never hand-edit project.pbxproj.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
echo "regenerated VeloMaps.xcodeproj"
