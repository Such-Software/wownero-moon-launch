#!/usr/bin/env python3
"""First-draft lip-synced character intro for MoonLaunch.

A smug little green Martian razzes SpaceDoge; the doge claps back. Portrait
1080x1920, word-synced captions, over a deep-space background. This is a PIPELINE
PROOF built on such-graphics' talking-scene renderer — the app here owns only the
two puppets, the space background, the staging and the dialogue; the lip-sync
compositing, captions and audio live in `such_graphics.scene`.

Run (lipsync.py reads the ElevenLabs key from env or the key files directly, and
finds rhubarb on PATH / ~/.local/bin; the exports below just make it explicit):

  PYTHONPATH=/Users/johnmurphy/src/such-graphics \
  RHUBARB=/Users/johnmurphy/.local/bin/rhubarb \
  python3 marketing/lib/make_char_intro.py

Output:
  marketing/out/char_intro_1.mp4            (video + muxed audio)
  marketing/out/char_intro_1.scene.m4a      (audio side-file the renderer emits)
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

sys.path.insert(0, "/Users/johnmurphy/src/such-graphics")

from PIL import Image, ImageDraw

from such_graphics.dialogue import perform
from such_graphics.puppet import Puppet
from such_graphics.scene import Actor, render_talking_scene
from such_graphics.subtitles import CaptionStyle

HERE = Path(__file__).resolve().parent          # marketing/lib
MKT = HERE.parent                               # marketing
CHARS = MKT / "characters"
OUT = MKT / "out"
WORK = OUT / "_char_intro_work"

W, H = 1080, 1920
FPS = 30
BASE = 560                                      # puppet native px (square)

# Two contrasting stock ElevenLabs voices (the default set every account ships):
#   doge  -> Brian  : deep, warm, confident narrator  (goofy-confident bravado)
#   alien -> Callum : gravelly, intense, snide         (smug little villain)
VOICE_DOGE = "nPczCjzI2devNBz1zQrb"     # Brian
VOICE_ALIEN = "N2lVS1w4EtoT3dr4eOWO"    # Callum
VOICES = {"doge": VOICE_DOGE, "alien": VOICE_ALIEN}

# Per-character delivery (ElevenLabs voice_settings; folded into the VO cache key so
# changing it re-synthesises). Both intros previously fell back to the neutral
# DEFAULT (stability 0.42 / style 0.40) — i.e. the doge spoke in a CALM narrator
# voice. Now:
#   doge  -> GROWLY-HYPED: very low stability lets the leading "Grrrr" render as an
#            actual snarl (not a politely-read "grr"), high style = excitable bravado.
#   alien -> SNIDE: expressive but composed, a hair slow = smug villain landing a jab.
VOICE_SETTINGS = {
    "doge":  {"stability": 0.18, "similarity_boost": 0.82, "style": 0.72,
              "use_speaker_boost": True, "speed": 1.0},
    "alien": {"stability": 0.42, "similarity_boost": 0.90, "style": 0.55,
              "use_speaker_boost": True, "speed": 0.95},
}

# Alien on the LEFT throws the jab; SpaceDoge on the RIGHT growls, then claps back.
# The growl lives IN the doge's line ("Grrrr...") so the voice performs it — no
# separate SFX layer (that read as a canned sound bolted on).
SCRIPT = [
    ("alien", "Pffft, you could never land the rusty rocket on Mars, you dirty doge."),
    ("doge",  "Grrrr, watch me do such landings, many moon!"),
]


def _make_background() -> Image.Image:
    """Deep indigo -> navy vertical gradient + a static starfield and a dim moon.
    Built once; a fresh copy is handed to each frame so compositing never bakes
    the actors into the shared base."""
    top, bot = (20, 17, 50), (6, 7, 22)
    col = Image.new("RGB", (1, H))
    cp = col.load()
    for y in range(H):
        k = y / (H - 1)
        cp[0, y] = (int(top[0] + (bot[0] - top[0]) * k),
                    int(top[1] + (bot[1] - top[1]) * k),
                    int(top[2] + (bot[2] - top[2]) * k))
    bg = col.resize((W, H))
    d = ImageDraw.Draw(bg, "RGBA")

    # dim moon, upper-left, well clear of the actors
    d.ellipse((70, 150, 250, 330), fill=(206, 210, 232))
    d.ellipse((70, 150, 250, 330), outline=(150, 156, 186), width=3)
    for cx, cy, r in ((120, 210, 16), (185, 250, 22), (150, 290, 12)):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(184, 188, 212))

    rnd = random.Random(7)
    for _ in range(150):
        x, y = rnd.randint(0, W - 1), rnd.randint(0, H - 1)
        r = rnd.choice([1, 1, 1, 2, 2, 3])
        b = rnd.randint(150, 255)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(b, b, min(255, b + 12)))
    return bg


_BG = _make_background()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)

    # Synthesise (cached) the two-turn exchange onto one timeline.
    perf = perform(SCRIPT, VOICES, out_dir=WORK / "_vo", lead_in=0.35, gap=0.45,
                   settings=VOICE_SETTINGS)
    placements = [(perf, 0.0)]

    doge = Puppet(CHARS / "spacedoge.svg", (BASE, BASE),
                  palette={"line": (140, 84, 34), "mouth": (74, 40, 30),
                           "lip": (214, 150, 118)})
    alien = Puppet(CHARS / "alien.svg", (BASE, BASE),
                   palette={"line": (30, 82, 26), "mouth": (26, 52, 22),
                            "teeth": (226, 232, 214), "tongue": (150, 176, 118)})

    actors = [
        Actor("alien", alien, x_frac=0.29, idle_phase=1.4),
        Actor("doge", doge, x_frac=0.71, idle_phase=0.0),
    ]

    style = CaptionStyle(mode="color+grow+lift",
                         base=(238, 242, 255), active=(255, 205, 79),
                         stroke_fill=(8, 9, 30))

    def background(t):
        return _BG.copy()

    def stage(t):
        return (0.82, 0.40)             # (scale x native, vertical anchor frac)

    def caption_at(t, ev):
        return int(H * 0.80)            # lower third

    out = OUT / "char_intro_1.mp4"
    info = render_talking_scene(
        out, placements, actors, background=background, stage=stage,
        caption_at=caption_at, style=style, fps=FPS, size=(W, H),
        work_dir=WORK / "_frames")
    print(f"  OK {out}  ({info['duration']}s, {info['frames']} frames, "
          f"{info['events']} lines)")


if __name__ == "__main__":
    main()
