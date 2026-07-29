#!/usr/bin/env python3
"""Generate the CTA end-card for the promo videos: the app icon + title + a big
"PLAY FREE" over the same deep-space background the intros use. Emits a still PNG
and a short MP4 (gentle push-in) to tack onto the end of each video.

Run: python3 marketing/lib/make_cta.py
Out: marketing/out/_promo/cta.png, marketing/out/_promo/cta.mp4
"""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, "/Users/johnmurphy/src/such-graphics")
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from PIL import Image, ImageDraw, ImageFont
import make_char_intro as base

W, H = 1080, 1920
MKT = HERE.parent
ROOT = MKT.parent
FONT = str(ROOT / "fonts" / "Computer Speak v0.3.ttf")
ICON = str(ROOT / "art" / "branding" / "icon.png")
OUT = MKT / "out" / "_promo"
DUR, FPS = 2.6, 30

YELLOW = (255, 205, 79)
WHITE = (238, 242, 255)
MUTED = (150, 160, 200)


def _centered(d, y, text, font, fill):
    w = d.textbbox((0, 0), text, font=font)[2]
    d.text(((W - w) // 2, y), text, font=font, fill=fill)


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    bg = base._make_background().convert("RGBA")
    d = ImageDraw.Draw(bg)

    icon = Image.open(ICON).convert("RGBA").resize((452, 452), Image.LANCZOS)
    bg.alpha_composite(icon, ((W - 452) // 2, 300))

    _centered(d, 820, "SUCH MOON", ImageFont.truetype(FONT, 96), WHITE)
    _centered(d, 930, "LAUNCH", ImageFont.truetype(FONT, 96), WHITE)
    _centered(d, 1200, "PLAY FREE", ImageFont.truetype(FONT, 132), YELLOW)
    _centered(d, 1380, "iOS   ·   Android", ImageFont.truetype(FONT, 54), MUTED)

    png = OUT / "cta.png"
    bg.convert("RGB").save(png)

    # gentle push-in (zoompan) so the card isn't a dead freeze
    mp4 = OUT / "cta.mp4"
    n = int(DUR * FPS)
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-i", str(png),
        "-vf", f"zoompan=z='min(zoom+0.0008,1.06)':d={n}:s={W}x{H}:fps={FPS},"
               f"format=yuv420p",
        "-t", f"{DUR}", "-r", str(FPS), str(mp4)], check=True)
    print(f"  OK {png}\n  OK {mp4} ({DUR}s)")


if __name__ == "__main__":
    build()
