#!/usr/bin/env python3
"""Velo Maps routing: live-traffic driving routes with up to 2 alternatives, from Mapbox's
driving-traffic profile (owner, 11/9: route with traffic, ask for 2 alternatives per route,
keep checking for a faster route while driving). The Mapbox token never leaves this server.

GET /route?from=<lat>,<lon>&to=<lat>,<lon>   header X-Velo-App: <APP_TOKEN>
    → Mapbox Directions JSON (OSRM-style: routes[], legs[].steps[] with lanes, exits and
      sign destinations), unchanged.

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


def directions(a, b):
    coords = f"{a[1]:.6f},{a[0]:.6f};{b[1]:.6f},{b[0]:.6f}"
    q = urlencode({"alternatives": "true", "geometries": "geojson", "overview": "full",
                   "steps": "true", "access_token": MAPBOX})
    req = urllib.request.Request(f"https://api.mapbox.com/directions/v5/mapbox/driving-traffic/{coords}?{q}",
                                 headers={"User-Agent": "velomaps-route/1.0"})
    with urllib.request.urlopen(req, timeout=12) as r:
        return r.read()


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
        if not spend():
            return self.send(429, b"daily routing budget reached")
        try:
            body = directions(a, b)
        except urllib.error.HTTPError as e:
            print(f"mapbox error: HTTP {e.code}", flush=True)       # never the URL (token)
            return self.send(502)
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"mapbox unreachable: {type(e).__name__}", flush=True)
            return self.send(502)
        try:
            ok = json.loads(body).get("code") == "Ok"
        except ValueError:
            ok = False
        return self.send(200, body, "application/json") if ok else self.send(502)


if __name__ == "__main__":
    os.makedirs(STATE, exist_ok=True)
    ThreadingHTTPServer(("127.0.0.1", 3131), Handler).serve_forever()
