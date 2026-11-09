#!/usr/bin/env python3
"""Mock of the App Store product page on an iPhone 17 Pro with the header video playing at the
top, cropped the way the App Store crops it (canvas x ~1006-2833, y ~232-1410; back and
mute/share buttons over y ~490-725), and the icon, name, Get button and screenshots below.

    ~/.venvs/marracat/bin/python -I scripts/preview_product_page.py CREATIVE_DIR SCREENSHOT_DIR OUT_DIR
writes product-page.mp4 + product-page.png (for review only; not uploaded anywhere).
"""
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

creative, shots, out = (pathlib.Path(a) for a in sys.argv[1:4])
W, H = 1206, 2622
CROP = (1006, 232, 1827, 1178)
scale = W / CROP[2]
head_h = int(CROP[3] * scale)
SF = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight="Semibold"):
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f


def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width - 1, img.height - 1), r, fill=255)
    img = img.convert("RGBA")
    img.putalpha(m)
    return img


ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(ov)
d.rectangle((0, head_h, W, H), fill=(255, 255, 255, 255))
d.text((96, 54), "9:41", font=font(50), fill="white")
# back + share/mute buttons over the header (glass circles)
for cx, glyph in ((90, "‹"), (W - 230, ""), (W - 90, "⇪")):
    d.ellipse((cx - 56, (490 - 232) * scale + 30 - 56 + 50, cx + 56, (490 - 232) * scale + 30 + 56 + 50), fill=(255, 255, 255, 70))
    cy = (490 - 232) * scale + 80
    if glyph:
        d.text((cx, cy), glyph, font=font(64, "Bold"), fill="white", anchor="mm")
    else:                                   # "more" button: three dots
        for dx in (-22, 0, 22):
            d.ellipse((cx + dx - 7, cy - 7, cx + dx + 7, cy + 7), fill="white")
# icon, name, Get
icon = rounded(Image.open(pathlib.Path(__file__).resolve().parent.parent / "marketing/brand/icon-1024.png").resize((230, 230)), 52)
y = head_h + 50
ov.alpha_composite(icon, (54, y))
d.text((320, y + 30), "Velo Maps", font=font(66, "Bold"), fill=(0, 0, 0))
d.text((320, y + 112), "3D navigation with lane guidance", font=font(38, "Regular"), fill=(120, 120, 128))
d.rounded_rectangle((320, y + 170, 500, y + 236), 33, fill=(0, 122, 255))
d.text((410, y + 203), "Get", font=font(38, "Bold"), fill="white", anchor="mm")
d.line((54, y + 290, W - 54, y + 290), fill=(225, 225, 230), width=3)
# screenshot row
panels = sorted(shots.glob("*.png"))[:3]
x, py, pw = 54, y + 330, 520
for p in panels:
    im = rounded(Image.open(p).resize((pw, int(pw * 2868 / 1320))), 40)
    ov.alpha_composite(im, (x, py))
    x += pw + 30
out.mkdir(parents=True, exist_ok=True)
ov.save(out / "_overlay.png")

vf = (f"[0:v]crop={CROP[2]}:{CROP[3]}:{CROP[0]}:{CROP[1]},scale={W}:{head_h}[h];"
      f"color=c=white:s={W}x{H}:r=30[bg];[bg][h]overlay=0:0:shortest=1[v];[v][1:v]overlay=0:0")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(creative / "header-video.mp4"), "-i", str(out / "_overlay.png"),
                "-filter_complex", vf, "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                str(out / "product-page.mp4")], check=True)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "7", "-i", str(out / "product-page.mp4"), "-frames:v", "1",
                str(out / "product-page.png")], check=True)
(out / "_overlay.png").unlink()
print("wrote product-page.mp4 + .png")
