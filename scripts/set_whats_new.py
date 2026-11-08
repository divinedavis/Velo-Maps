#!/usr/bin/env python3
"""Wait for an uploaded build to finish processing, then set its TestFlight "What to Test"
text. Notes are plain paragraphs separated by blank lines, never bullets (owner rule,
all apps); any bullet characters are turned into paragraphs.

  ~/.venvs/spendcap/bin/python scripts/set_whats_new.py <build-number> notes.txt
"""
import os, pathlib, re, sys, time
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


def headers(c):
    now = int(time.time())
    tok = jwt.encode({"iss": c["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                     pathlib.Path(c["ASC_KEY_PATH"]).expanduser().read_text(), algorithm="ES256",
                     headers={"kid": c["ASC_KEY_ID"], "typ": "JWT"})
    return {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}


BULLET = re.compile(r"^\s*([-*•·]|\d+[.)])\s+")


def paragraphs(text):
    """Blank-line paragraphs; each bullet item becomes its own paragraph."""
    out, cur = [], []
    for raw in text.strip().splitlines():
        line = BULLET.sub("", raw).strip()
        if not line or BULLET.match(raw):
            if cur:
                out.append(" ".join(cur)); cur = []
        if line:
            cur.append(line)
    if cur:
        out.append(" ".join(cur))
    return "\n\n".join(out)


def main():
    build, notes_file = sys.argv[1], sys.argv[2]
    notes = paragraphs(pathlib.Path(notes_file).read_text())
    c = cfg()
    for attempt in range(60):   # up to ~30 min
        r = requests.get(f"{API}/builds", headers=headers(c), timeout=30,
                         params={"filter[app]": c["ASC_APP_ID"], "filter[version]": build})
        r.raise_for_status()
        data = r.json()["data"]
        state = data[0]["attributes"]["processingState"] if data else "NOT_FOUND"
        print(f"build {build}: {state}", flush=True)
        if state == "VALID":
            break
        if state in ("FAILED", "INVALID"):
            print("build failed processing"); return 1
        time.sleep(30)
    else:
        print("gave up waiting for processing"); return 1
    bid = data[0]["id"]
    r = requests.get(f"{API}/builds/{bid}/betaBuildLocalizations", headers=headers(c), timeout=30)
    r.raise_for_status()
    locs = r.json()["data"]
    if locs:
        r = requests.patch(f"{API}/betaBuildLocalizations/{locs[0]['id']}", headers=headers(c), timeout=30,
                           json={"data": {"type": "betaBuildLocalizations", "id": locs[0]["id"], "attributes": {"whatsNew": notes}}})
    else:
        r = requests.post(f"{API}/betaBuildLocalizations", headers=headers(c), timeout=30,
                          json={"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": notes},
                                         "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    print(f"What to Test: HTTP {r.status_code}")
    return 0 if r.ok else 1


if __name__ == "__main__":
    sys.exit(main())
