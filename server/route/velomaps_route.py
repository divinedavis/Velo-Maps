#!/usr/bin/env python3
"""Velo Maps routing: live-traffic driving routes with up to 2 alternatives, from Mapbox's
driving-traffic profile (owner, 11/9: route with traffic, ask for 2 alternatives per route,
keep checking for a faster route while driving). The Mapbox token never leaves this server.

GET /route?from=<lat>,<lon>&to=<lat>,<lon>[&bearing=<0-359>&clear=<1-200>]
    header X-Velo-App: <APP_TOKEN>
    → Mapbox Directions JSON (OSRM-style: routes[], legs[].steps[] with lanes, exits and
      sign destinations), unchanged.
    bearing/clear (a car already moving: reroutes, faster-route checks): start the route in
    the direction of travel (±45°) with no significant maneuver in the first `clear` metres,
    so it can't begin with a U-turn. If Mapbox finds no road that way, asked again without.
    Every request excludes ferries and unpaved roads. Only these named, validated values are
    passed on — the phone can't send arbitrary Mapbox parameters.

Guards (owner rule: never blow the budget):
  * a hard daily cap on requests sent to Mapbox (DAILY_ROUTES, default 3000 ≈ 90k a month,
    under Mapbox's free monthly allowance) → 429 once reached; the app falls back to the
    public OSRM server, then Apple;
  * no Mapbox token configured → 503 (same fallback);
  * coordinates validated; nginx rate-limits per IP.
Env (from /etc/velomaps-route.env, root:velomaps 0640): MAPBOX_TOKEN, APP_TOKEN, DAILY_ROUTES.
"""
import json, os, re, threading, urllib.error, urllib.request
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlparse

STATE = os.environ.get("STATE_DIRECTORY", "/var/lib/velomaps-route")
MAPBOX = os.environ.get("MAPBOX_TOKEN", "").strip()
TOKEN = os.environ["APP_TOKEN"]
DAILY = int(os.environ.get("DAILY_ROUTES", "3000"))
COORD = re.compile(r"^(-?\d{1,2}(?:\.\d{1,7})?),(-?\d{1,3}(?:\.\d{1,7})?)$")
lock = threading.Lock()


def parse(value):
    """'lat,lon' → (lat, lon) or None."""
    m = COORD.match(value or "")
    if not m:
        return None
    lat, lon = float(m.group(1)), float(m.group(2))
    return (lat, lon) if -90 <= lat <= 90 and -180 <= lon <= 180 else None


def spend():
    """Reserve one Mapbox request from today's budget; False once the cap is reached."""
    path = os.path.join(STATE, f"budget-{date.today().isoformat()}.json")
    with lock:
        used = json.load(open(path))["requests"] if os.path.exists(path) else 0
        if used + 1 > DAILY:
            return False
        with open(path, "w") as f:
            json.dump({"requests": used + 1}, f)
        return True


def whole(value, low, high):
    """A whole number in [low, high] from a query value, else None."""
    return int(value) if re.fullmatch(r"\d{1,3}", value or "") and low <= int(value) <= high else None


def directions(a, b, bearing=None, clear=None):
    coords = f"{a[1]:.6f},{a[0]:.6f};{b[1]:.6f},{b[0]:.6f}"
    q = {"alternatives": "true", "geometries": "geojson", "overview": "full", "steps": "true",
         "exclude": "ferry,unpaved", "access_token": MAPBOX}
    if bearing is not None:
        q["bearings"] = f"{bearing},45;"                # the start only; the destination is free
        q["avoid_maneuver_radius"] = str(clear or 50)
    req = urllib.request.Request(f"https://api.mapbox.com/directions/v5/mapbox/driving-traffic/{coords}?{urlencode(q)}",
                                 headers={"User-Agent": "velomaps-route/1.0"})
    with urllib.request.urlopen(req, timeout=12) as r:
        return r.read()


def ok(body):
    try:
        return json.loads(body).get("code") == "Ok"
    except ValueError:
        return False


class Handler(BaseHTTPRequestHandler):
    server_version = "velomaps-route"

    def log_message(self, *args):          # no request lines (they'd hold where people drive)
        pass

    def send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/route/health":
            return self.send(200, b"ok" if MAPBOX else b"ok (no mapbox token)")
        if url.path != "/route":
            return self.send(404)
        if self.headers.get("X-Velo-App") != TOKEN:
            return self.send(403)
        q = parse_qs(url.query)
        a, b = parse((q.get("from") or [""])[0]), parse((q.get("to") or [""])[0])
        if not a or not b:
            return self.send(400)
        if not MAPBOX:
            return self.send(503, b"traffic routing not configured")
        bearing = whole((q.get("bearing") or [""])[0], 0, 359)
        clear = whole((q.get("clear") or [""])[0], 1, 200)
        # With a heading first; if Mapbox has no road that way (GPS course off, parking lot),
        # once more without. Each try is one request from the budget.
        for heading in ([bearing, None] if bearing is not None else [None]):
            if not spend():
                return self.send(429, b"daily routing budget reached")
            try:
                body = directions(a, b, heading, clear)
            except urllib.error.HTTPError as e:
                print(f"mapbox error: HTTP {e.code}", flush=True)       # never the URL (token)
                if e.code == 422 and heading is not None:
                    continue
                return self.send(502)
            except (urllib.error.URLError, TimeoutError) as e:
                print(f"mapbox unreachable: {type(e).__name__}", flush=True)
                return self.send(502)
            if ok(body):
                return self.send(200, body, "application/json")
        return self.send(502)


if __name__ == "__main__":
    os.makedirs(STATE, exist_ok=True)
    ThreadingHTTPServer(("127.0.0.1", 3131), Handler).serve_forever()
