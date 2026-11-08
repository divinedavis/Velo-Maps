#!/usr/bin/env python3
"""Velo Maps voice: speaks a whole guidance sentence in Rene's ElevenLabs voice, so every
prompt sounds the same on any street (owner, 11/8: "make the elevenlabs voice consistent
throughout the sentences"). The ElevenLabs key never leaves this server.

GET /tts?text=<sentence>   header X-Velo-App: <APP_TOKEN>   → audio/mpeg

Guards (owner rule: never blow the budget):
  * every sentence is cached on disk forever (same text = no new spend);
  * a hard daily cap on NEW characters sent to ElevenLabs (DAILY_CHARS, default 5000 ≈ 2,500
    credits on eleven_flash_v2_5) → 429 once reached, the app falls back to the iPhone voice;
  * text ≤ 200 chars, letters/digits/basic punctuation only; nginx rate-limits per IP.
Env (from /etc/velomaps-tts.env, root:velomaps 0640): ELEVENLABS_API_KEY, APP_TOKEN, DAILY_CHARS.
"""
import hashlib, json, os, re, threading, time, urllib.error, urllib.request
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

VOICE_ID = "YYsXMvvITqnbq9AYpUDk"          # Rene (owner pick 11/8)
MODEL_ID = "eleven_flash_v2_5"
SETTINGS = {"stability": 0.75, "similarity_boost": 0.8, "style": 0.0, "speed": 1.0, "use_speaker_boost": True}
SEED = 7                                    # same seed → the most repeatable delivery
FORMAT = "mp3_44100_64"
STATE = os.environ.get("STATE_DIRECTORY", "/var/lib/velomaps-tts")
KEY = os.environ["ELEVENLABS_API_KEY"]
TOKEN = os.environ["APP_TOKEN"]
DAILY = int(os.environ.get("DAILY_CHARS", "5000"))
ALLOWED = re.compile(r"^[A-Za-z0-9 .,:;'!?/&()\-]{1,200}$")
lock = threading.Lock()


def cache_path(text):
    h = hashlib.sha256(f"{VOICE_ID}|{MODEL_ID}|{json.dumps(SETTINGS, sort_keys=True)}|{SEED}|{text}".encode()).hexdigest()
    return os.path.join(STATE, "cache", h[:2], h + ".mp3")


def spend(n):
    """Reserve n characters of today's budget; False if it would go over."""
    path = os.path.join(STATE, f"budget-{date.today().isoformat()}.json")
    with lock:
        used = json.load(open(path))["chars"] if os.path.exists(path) else 0
        if used + n > DAILY:
            return False
        with open(path, "w") as f:
            json.dump({"chars": used + n}, f)
        return True


def render(text):
    body = json.dumps({"text": text, "model_id": MODEL_ID, "voice_settings": SETTINGS, "seed": SEED}).encode()
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}?output_format={FORMAT}", data=body, method="POST",
        headers={"xi-api-key": KEY, "Content-Type": "application/json", "Accept": "audio/mpeg"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read()


class Handler(BaseHTTPRequestHandler):
    server_version = "velomaps-tts"

    def log_message(self, *args):          # no request lines (they'd hold the sentence text)
        pass

    def send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if code == 200:
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/tts/health":
            return self.send(200, b"ok")
        if url.path != "/tts":
            return self.send(404)
        if self.headers.get("X-Velo-App") != TOKEN:
            return self.send(403)
        text = (parse_qs(url.query).get("text") or [""])[0].strip()
        if not ALLOWED.match(text):
            return self.send(400)
        path = cache_path(text)
        if os.path.exists(path):
            return self.send(200, open(path, "rb").read(), "audio/mpeg")
        if not spend(len(text)):
            return self.send(429, b"daily voice budget reached")
        try:
            audio = render(text)
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"elevenlabs error: {getattr(e, 'code', '')} {e}", flush=True)
            return self.send(502)
        if not audio or (audio[:3] != b"ID3" and audio[:2] not in (b"\xff\xfb", b"\xff\xf3")):
            return self.send(502)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(audio)
        os.replace(tmp, path)
        return self.send(200, audio, "audio/mpeg")


if __name__ == "__main__":
    os.makedirs(os.path.join(STATE, "cache"), exist_ok=True)
    ThreadingHTTPServer(("127.0.0.1", 3130), Handler).serve_forever()
