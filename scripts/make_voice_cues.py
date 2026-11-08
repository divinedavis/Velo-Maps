#!/usr/bin/env python3
"""Render Velo Maps' spoken guidance with ElevenLabs into the app bundle (Milepost pattern).

No key ships in the app: every phrase the demo can say is rendered once here into
VeloMaps/VoiceCues/cue-<slug>.mp3, and the phone stitches clips (distance + instruction).
Anything without a clip falls back to Apple's voice on device.

Clip names are slug(display text), computed identically in Swift (VoiceCues.swift); the
unit tests fail if a phrase the demo routes produce has no clip.

Key: keychain service `nemo-elevenlabs` (TTS-scoped). Credits can't be read from the key,
so this counts characters and refuses runs over MAX_CHARS_PER_RUN.

  python3 scripts/make_voice_cues.py [--dry-run] [--force]
"""
import json, os, re, subprocess, sys, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "VeloMaps", "VoiceCues")
MANIFEST = os.path.join(OUT, "voice_cues.json")
VOICE_ID = "EXAVITQu4vr4xnSDxMaL"       # Sarah (same voice as Milepost)
VOICE_NAME = "Sarah"
MODEL_ID = "eleven_flash_v2_5"          # 0.5 credits/char
OUTPUT_FORMAT = "mp3_22050_32"
MAX_CHARS_PER_RUN = 3000


def slug(text):
    """Must match VoiceCues.slug in Swift."""
    return "cue-" + re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def spoken(text):
    """Display text -> what the voice says (abbreviations expanded)."""
    t = text
    t = re.sub(r"\bW (\d+) St\b", lambda m: f"West {ordinal(int(m.group(1)))} Street", t)
    t = t.replace("Columbus Av / ", "Columbus Avenue and ").replace("CPW", "Central Park West")
    t = re.sub(r"\bNY (\w+)", r"New York \1", t)
    return t


def ordinal(n):
    suf = "th" if 11 <= n % 100 <= 13 else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suf}"


# Everything the demo routes can say (VeloMaps: Route.maneuvers, Trip stop alerts, potholes).
INSTRUCTIONS = [
    "Turn left onto W 96 St", "Arrive at Columbus Av / W 96 St",                     # bus
    "Turn left onto West 79th Street", "Turn left onto Riverside Drive",             # drive
    "Turn right onto West 72nd Street", "Take the ramp to NY 9A North",
    "Take the exit to West 96th Street", "Arrive at West 96th Street",
]
LINES = [
    "Pothole ahead",
    "Your stop is next: Columbus Av / W 96 St",
    "2 stops to go. Your stop is Columbus Av / W 96 St",
    "Arriving at your stop, Columbus Av / W 96 St",
    "Arriving at your stop, West 96th Street",
]
# Spoken distances, rounded like a navigation voice (VoiceCues.distanceText in Swift).
DISTANCES = [f"In {f} feet" for f in range(100, 1001, 100)] + \
    [("In 1 mile" if m == 10 else f"In {m / 10:.1f} miles") for m in range(2, 14)]


def library():
    lib = {}
    for d in DISTANCES:
        lib[slug(d)] = (d + ",", None, "turn left")
    for i in INSTRUCTIONS:
        text = spoken(i)
        lib[slug(i)] = (text[0].lower() + text[1:] + ".", "In 300 feet,", None)
    for l in LINES:
        lib[slug(l)] = (spoken(l) + ".", None, None)
    return lib


def api_key():
    return subprocess.check_output(["security", "find-generic-password", "-s", "nemo-elevenlabs", "-w"], text=True).strip()


def render(key, text, previous, nxt):
    body = {"text": text, "model_id": MODEL_ID, "previous_text": previous, "next_text": nxt,
            "voice_settings": {"stability": 0.6, "similarity_boost": 0.8, "style": 0.0, "speed": 1.0}}
    body = {k: v for k, v in body.items() if v is not None}
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}?output_format={OUTPUT_FORMAT}",
        data=json.dumps(body).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"}, method="POST")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            if e.code in (429, 500, 502, 503) and attempt < 2:
                time.sleep(2 * (attempt + 1)); continue
            raise SystemExit(f"error: ElevenLabs HTTP {e.code} for {text!r}: {detail}")
    raise SystemExit("error: gave up")


def main():
    force, dry = "--force" in sys.argv, "--dry-run" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    lib = library()
    todo = {n: s for n, s in lib.items() if force or not os.path.exists(os.path.join(OUT, f"{n}.mp3"))}
    chars = sum(len(s[0]) for s in todo.values())
    print(f"{len(lib)} clips in library, {len(todo)} to render, {chars} characters (~{chars // 2} credits on {MODEL_ID})")
    if chars > MAX_CHARS_PER_RUN:
        raise SystemExit(f"error: {chars} characters exceeds the per-run cap of {MAX_CHARS_PER_RUN}")
    if dry:
        for n, s in sorted(lib.items()): print(f"  {n}: {s[0]!r}")
        return
    if todo:
        key, sent = api_key(), 0
        for i, (name, (text, previous, nxt)) in enumerate(sorted(todo.items()), 1):
            sent += len(text)
            if sent > MAX_CHARS_PER_RUN:
                raise SystemExit("error: per-run character cap hit mid-run")
            audio = render(key, text, previous, nxt)
            if not audio or (audio[:3] != b"ID3" and audio[:2] not in (b"\xff\xfb", b"\xff\xf3")):
                raise SystemExit(f"error: {name}: response is not mp3 ({len(audio)} bytes)")
            with open(os.path.join(OUT, f"{name}.mp3"), "wb") as f:
                f.write(audio)
            print(f"  [{i}/{len(todo)}] {name}.mp3 {len(audio):>6} B  {text!r}")
        print(f"sent {sent} characters (~{sent // 2} credits)")
    with open(MANIFEST, "w") as f:
        json.dump({"voiceID": VOICE_ID, "voiceName": VOICE_NAME, "modelID": MODEL_ID,
                   "clips": {n: s[0] for n, s in lib.items()}}, f, indent=2, sort_keys=True)
        f.write("\n")
    total = sum(os.path.getsize(os.path.join(OUT, p)) for p in os.listdir(OUT) if p.endswith(".mp3"))
    print(f"wrote {MANIFEST}; {total / 1e6:.2f} MB of clips")


if __name__ == "__main__":
    main()
