#!/usr/bin/env python3
"""App Store creative assets (Asset Library) for Velo Maps, in the icon's look.

    header    3840x1646  product page header (still + animated video, 21:9, 30 fps)
    search    3840x2560  search results slot
    universal 5244x2950  16:9 master Apple can crop into either

Velo red field (the icon's gradient) with a faint tilted street grid. The lockup is the raised
Arrow mark + "Velo Maps" in white, a white route line running edge to edge under it, and one
short line under that.

The header video is animated like Marracat's (owner, 11/9: "make sure the header is animated
similar to how you animated marracats"). A small arrow drives in from the left and draws the
route line behind it. The lockup rises into place. Then the line under it changes every 3 seconds.

All type sits inside Apple's "ART SAFE AREA" (creative_assets-templates.sketch; header is only the
centre 1646x661), and on the header it sits below the band the App Store's back and mute/share
buttons cover (canvas y ~490-725). Only the route line and the background reach the edges.
check_inside() exits if any ink leaves its box. Apple's content rules: no prices, URLs, (c),
awards or other stores; claims must be true of the shipping app.

    ~/.venvs/marracat/bin/python -I scripts/make_creative_assets.py OUT_DIR [--no-video]
"""
from __future__ import annotations

import pathlib
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARK = ROOT / "marketing/brand/arrow-mark.png"
SF = "/System/Library/Fonts/SFNS.ttf"
CANVASES = {"header": (3840, 1646), "search": (3840, 2560), "universal": (5244, 2950)}
SAFE = {"header": (1097, 493, 1646, 661), "search": (836, 765, 2168, 1030), "universal": (1921, 660, 1402, 962)}
BUTTONS_BOTTOM = 725            # header: type must start below the back / mute / share buttons
TOP, BOTTOM = (0xEE, 0x3B, 0x44), (0x9A, 0x0B, 0x16)
WHITE = (255, 255, 255)
FPS = 30
LINES = [                       # every one is true of the app today
    "3D turn-by-turn navigation",
    "Lane guidance before every turn",
    "Exit signs, word for word",
    "Speed limits always in view",
    "Report potholes in one tap",
]
STILL_LINE = LINES[0]


def font(size: float, weight: str) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(SF, int(size))
    f.set_variation_by_name(weight)
    return f


def layout(kind: str) -> dict:
    sx, sy, sw, sh = SAFE[kind]
    hdr = kind == "header"
    return {
        "lock_cy": sy + (0.555 if hdr else 0.36) * sh,
        "mark_h": (0.33 if hdr else 0.30) * sh,
        "rule_y": sy + (0.785 if hdr else 0.62) * sh,
        "line_cy": sy + (0.915 if hdr else 0.80) * sh,
        "line_size": (0.092 if hdr else 0.07) * sh,
        "max_w": 0.86 * sw,
    }


def background(w: int, h: int) -> Image.Image:
    t = np.linspace(0, 1, h)[:, None, None]
    img = (np.array(TOP) * (1 - t) + np.array(BOTTOM) * t) * np.ones((1, w, 1))
    bg = Image.fromarray(img.astype(np.uint8), "RGB").convert("RGBA")
    grid = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(grid)
    step, lw = int(h * 0.11), max(4, int(h * 0.007))
    for i in range(0, w * 2, step):
        d.line([(i, 0), (i, h * 2)], fill=(255, 255, 255, 16), width=lw)
    for j in range(0, h * 2, step):
        d.line([(0, j), (w * 2, j)], fill=(255, 255, 255, 16), width=lw)
    grid = grid.rotate(20, resample=Image.BICUBIC).crop((w // 2, h // 2, w // 2 + w, h // 2 + h))
    return Image.alpha_composite(bg, grid)


def mark(height: float, angle: float = 0) -> Image.Image:
    m = Image.open(MARK).convert("RGBA")
    m = m.crop(m.getbbox())
    if angle:
        m = m.rotate(angle, resample=Image.BICUBIC, expand=True)
        m = m.crop(m.getbbox())
    return m.resize((max(1, int(m.width * height / m.height)), int(height)), Image.LANCZOS)


def lockup(kind: str) -> tuple[Image.Image, int, int]:
    """The mark + wordmark on a transparent layer; returns it and its top-left."""
    L = layout(kind)
    mh = L["mark_h"]
    for _ in range(20):
        m = mark(mh)
        f = font(mh * 0.74, "Bold")
        tw = f.getlength("Velo Maps")
        gap = mh * 0.22
        total = m.width + gap + tw
        if total <= L["max_w"]:
            break
        mh *= 0.95
    asc, desc = f.getmetrics()
    layer = Image.new("RGBA", (int(total) + 40, int(mh) + 80), (0, 0, 0, 0))
    layer.alpha_composite(m, (0, 40))
    d = ImageDraw.Draw(layer)
    cap = f.getbbox("V")
    ty = 40 + mh / 2 - (cap[1] + cap[3]) / 2
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((m.width + gap, ty + mh * 0.03), "Velo Maps", font=f, fill=(60, 0, 8, 110))
    layer = Image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(mh * 0.04)), layer)
    ImageDraw.Draw(layer).text((m.width + gap, ty), "Velo Maps", font=f, fill=WHITE)
    w, _ = CANVASES[kind]
    return layer, int(w / 2 - total / 2), int(L["lock_cy"] - mh / 2 - 40)


def line_layer(kind: str, text: str) -> tuple[Image.Image, int, int]:
    L = layout(kind)
    f = font(L["line_size"], "Semibold")
    box = f.getbbox(text)
    layer = Image.new("RGBA", (box[2] - box[0] + 20, box[3] - box[1] + 20), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((10 - box[0], 10 - box[1]), text, font=f, fill=(255, 255, 255, 235))
    w, _ = CANVASES[kind]
    return layer, int(w / 2 - layer.width / 2), int(L["line_cy"] - layer.height / 2)


def rule_layer(kind: str) -> Image.Image:
    w, h = CANVASES[kind]
    L = layout(kind)
    lw = max(10, int(SAFE[kind][3] * 0.022))
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = L["rule_y"]
    ImageDraw.Draw(sh).line([(0, y + lw * 0.6), (w, y + lw * 0.6)], fill=(60, 0, 8, 120), width=lw)
    layer = Image.alpha_composite(sh.filter(ImageFilter.GaussianBlur(lw)), layer)
    ImageDraw.Draw(layer).line([(0, y), (w, y)], fill=WHITE, width=lw)
    return layer


def check_inside(kind: str, parts: list[tuple[Image.Image, int, int]]) -> None:
    sx, sy, sw, sh = SAFE[kind]
    top = max(sy, BUTTONS_BOTTOM) if kind == "header" else sy
    for img, x, y in parts:
        b = img.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
        x0, y0, x1, y1 = x + b[0], y + b[1], x + b[2], y + b[3]
        if x0 < sx or x1 > sx + sw or y0 < top or y1 > sy + sh:
            raise SystemExit(f"{kind}: ink {x0, y0, x1, y1} outside safe box {sx, top, sx + sw, sy + sh}")


def still(kind: str, out: pathlib.Path) -> None:
    w, h = CANVASES[kind]
    img = background(w, h)
    img = Image.alpha_composite(img, rule_layer(kind))
    parts = [lockup(kind), line_layer(kind, STILL_LINE)]
    check_inside(kind, parts)
    for layer, x, y in parts:
        img.alpha_composite(layer, (x, y))
    img.convert("RGB").save(out, optimize=True)


def header_video(out: pathlib.Path) -> None:
    kind = "header"
    w, h = CANVASES[kind]
    L = layout(kind)
    bg = np.asarray(background(w, h).convert("RGB"), dtype=np.float32)
    rule = np.asarray(rule_layer(kind), dtype=np.float32)
    rule_rgb, rule_a = rule[..., :3], rule[..., 3:] / 255
    lock, lx, ly = lockup(kind)
    lines = [line_layer(kind, t) for t in LINES]
    check_inside(kind, [(lock, lx, ly)] + lines)
    puck = mark(L["mark_h"] * 0.42, angle=-90)            # the arrow, pointing right
    pk = np.asarray(puck, dtype=np.float32)
    ease = lambda t: 0.0 if t <= 0 else 1.0 if t >= 1 else t * t * (3 - 2 * t)  # noqa: E731

    def paste(frame, layer, x, y, alpha):
        a = np.asarray(layer, dtype=np.float32)
        x0, y0 = max(x, 0), max(y, 0)
        x1, y1 = min(x + a.shape[1], w), min(y + a.shape[0], h)
        if x1 <= x0 or y1 <= y0 or alpha <= 0:
            return
        a = a[y0 - y:y1 - y, x0 - x:x1 - x]
        k = a[..., 3:] / 255 * alpha
        frame[y0:y1, x0:x1] = frame[y0:y1, x0:x1] * (1 - k) + a[..., :3] * k

    drive, intro, per, fade = (0.15, 1.45), 2.4, 3.0, 0.45
    total = intro + per * len(LINES)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
           "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
           "-profile:v", "high", "-movflags", "+faststart", str(out)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    lock_arr = lock
    for n in range(round(total * FPS)):
        t = n / FPS
        frame = bg.copy()
        # the arrow drives in from the left and draws the route behind it
        p = ease((t - drive[0]) / (drive[1] - drive[0]))
        head = int(-puck.width + (w + 2 * puck.width) * p)
        if head > 0:
            k = rule_a[:, :head]
            frame[:, :head] = frame[:, :head] * (1 - k) + rule_rgb[:, :head] * k
        if 0 < p < 1:
            paste(frame, puck, head - puck.width // 2, int(L["rule_y"] - puck.height / 2), 1)
        # the lockup rises into place
        a = ease((t - 1.0) / 0.8)
        paste(frame, lock_arr, lx, ly + int((1 - a) * 40), a)
        # the line under it changes every few seconds
        for i, (layer, x, y) in enumerate(lines):
            start = intro + i * per
            a = ease((t - start) / fade)
            if i < len(lines) - 1:
                a = min(a, 1 - ease((t - start - per + fade) / fade))
            if a > 0:
                paste(frame, layer, x, y + int((1 - a) * 14), a)
        proc.stdin.write(np.clip(frame, 0, 255).astype(np.uint8).tobytes())
    proc.stdin.close()
    if proc.wait():
        raise SystemExit("ffmpeg failed")


def main() -> None:
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "marketing/asc-creative")
    out.mkdir(parents=True, exist_ok=True)
    for kind in CANVASES:
        still(kind, out / f"{kind}.png")
        print(f"  ✓ {kind}.png")
    if "--no-video" not in sys.argv:
        header_video(out / "header-video.mp4")
        print("  ✓ header-video.mp4")


if __name__ == "__main__":
    main()
