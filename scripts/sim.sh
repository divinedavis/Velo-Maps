#!/usr/bin/env bash
# Prints the UDID of this app's own simulator, creating it if needed.
# Uniquely named on purpose: other projects' test runs target "name=iPhone 17 Pro" and
# grab any booted sim with that name (they launched their app on ours mid-run, 11/7).
set -euo pipefail
NAME="Velo Maps Phone"
# iOS 26.4, not 26.5: since 11/7 ~18:09 the 26.5 simulator runtime crashes every third-party
# app in dyld_sim (DyldSharedCache::getUUID) before main; Apple's own apps still launch.
RUNTIME="${VELO_SIM_IOS:-26.4}"
UDID=$(xcrun simctl list devices -j | /usr/bin/python3 -I -c "
import json,sys
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name']=='$NAME' and d.get('isAvailable'): print(d['udid']); sys.exit()")
if [ -z "$UDID" ]; then
  RT=$(xcrun simctl list runtimes -j | /usr/bin/python3 -I -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='iOS' and r['isAvailable'] and r['version']=='$RUNTIME']
print(rs[0]['identifier'])")
  UDID=$(xcrun simctl create "$NAME" "iPhone 17 Pro" "$RT")
fi
echo "$UDID"
