#!/usr/bin/env python3
"""Xcode Organizer numbers before a ship (quality gate 4): what real phones reported for
recent builds — diagnostic signatures per build, perfPowerMetrics for the app — via the
ASC API. Report only: a new app has no data for days, so this never blocks a ship.
Exit 2 only when the API itself cannot be reached, so a broken key is still noticed.

  ~/.venvs/spendcap/bin/python scripts/organizer_report.py
"""
import os, pathlib, sys, time
import jwt, requests

HERE = pathlib.Path(__file__).resolve().parent
API = "https://api.appstoreconnect.apple.com/v1"


def cfg():
    out = {}
    for l in (HERE / "asc-config.env").read_text().splitlines():
        l = l.strip()
        if l and not l.startswith("#"):
            k, _, v = l.partition("="); out[k] = os.path.expandvars(v.strip().strip('"'))
    return out


def main():
    c = cfg()
    now = int(time.time())
    tok = jwt.encode({"iss": c["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                     pathlib.Path(c["ASC_KEY_PATH"]).expanduser().read_text(), algorithm="ES256",
                     headers={"kid": c["ASC_KEY_ID"], "typ": "JWT"})
    h = {"Authorization": f"Bearer {tok}"}
    try:
        r = requests.get(f"{API}/builds", headers=h, timeout=30,
                         params={"filter[app]": c["ASC_APP_ID"], "sort": "-uploadedDate", "limit": 3})
        r.raise_for_status()
    except Exception as e:
        print(f"organizer: ASC API unreachable: {e}"); return 2
    builds = r.json()["data"]
    if not builds:
        print("organizer: no builds yet — nothing reported")
    for b in builds:
        v = b["attributes"]["version"]
        d = requests.get(f"{API}/builds/{b['id']}/diagnosticSignatures", headers=h, timeout=30)
        sigs = d.json().get("data", []) if d.ok else []
        print(f"organizer: build {v}: {len(sigs)} diagnostic signature(s)" + ("" if d.ok else f" (HTTP {d.status_code}, no data yet)"))
        for s in sigs[:5]:
            a = s["attributes"]; print(f"    {a.get('diagnosticType')} {a.get('weight')}: {a.get('signature', '')[:100]}")
    m = requests.get(f"{API}/apps/{c['ASC_APP_ID']}/perfPowerMetrics", timeout=30,
                     headers={**h, "Accept": "application/vnd.apple.xcode-metrics+json"})
    print(f"organizer: perfPowerMetrics HTTP {m.status_code}" + (" (no data yet)" if not m.ok else f", {len(m.text)} bytes"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
