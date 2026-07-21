#!/usr/bin/env python3
"""Solo close-up HOOK clips for social video: ONE character framed tight on the face,
delivering a short punchy line over the space background. Reuses the duo pipeline's
voices, per-character weird/grungy FX, captions and background (make_char_intro +
make_char_intro_3d); the only difference is a SINGLE actor rendered with the
SG3D_CLOSEUP camera and composited big. These are the openers for the three videos
(doge hook, alien hook, duo).

Run:
  PYTHONPATH=/Users/johnmurphy/src/such-graphics RHUBARB=/Users/johnmurphy/.local/bin/rhubarb \
    python3 marketing/lib/make_char_hook.py [doge|alien|all]

Output: marketing/out/hook_<char>.mp4 (+ .scene.m4a)
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, "/Users/johnmurphy/src/such-graphics")
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from PIL import Image

from such_graphics.dialogue import perform
from such_graphics.scene import flatten_placements, mux_clips
from such_graphics.subtitles import CaptionStyle, draw_caption

import make_char_intro as base          # voices, VOICE_SETTINGS, background
import make_char_intro_3d as duo        # BLENDER, VOICE_FX, grunge_clips

BLENDER = duo.BLENDER
MKT = HERE.parent
OUT = MKT / "out"
WORK = OUT / "_hook_work"
W, H, FPS, TAIL = 1080, 1920, 30, 0.6

# Short, punchy hook lines (spoken + captioned). Same voices + FX as the duo.
HOOKS = {
    "doge":  "Grrr! Think you can fly this rocket?",
    "alien": "Give up, human. You can't fly this thing.",
}
BUILD = {"doge": HERE / "build_3d_spacedoge.py", "alien": HERE / "build_3d_alien.py"}
RES = {"doge": (760, 920), "alien": (760, 920)}   # close-up alpha tile
ACTOR_W = {"doge": 990, "alien": 960}             # composite width (big face)
CY = {"doge": 0.40, "alien": 0.40}                # face vertical anchor (frac of H)


def render_closeup(speaker, cues, total, cache_root):
    """Render this character's close-up alpha frames (SG3D_CLOSEUP camera). Cached by
    (cues, total, res, closeup, script)."""
    res = RES[speaker]
    script = BUILD[speaker]
    key = hashlib.sha1((json.dumps(cues) + f"{total:.2f}{res}closeup" +
                        script.read_text()).encode()).hexdigest()[:16]
    out = cache_root / f"{speaker}_{key}"
    if out.exists() and (out / "done.txt").exists():
        print(f"  [{speaker}] cache hit")
        return sorted(out.glob("f_*.png"))
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.png"):
        f.unlink()
    cp = out / "cues.json"
    cp.write_text(json.dumps({"cues": cues}))
    env = dict(os.environ, SG3D_CLOSEUP="1", SG3D_CUES=str(cp), SG3D_OUT=str(out),
               SG3D_DUR=f"{total:.3f}", SG3D_RES=f"{res[0]}x{res[1]}")
    print(f"  [{speaker}] rendering {int(total * FPS)} close-up frames…")
    subprocess.run([BLENDER, "--background", "--python", str(script), "--", "alpha"],
                   env=env, check=True, stdout=subprocess.DEVNULL)
    (out / "done.txt").write_text("ok")
    return sorted(out.glob("f_*.png"))


def make_hook(speaker):
    line = HOOKS[speaker]
    perf = perform([(speaker, line)], {speaker: base.VOICES[speaker]},
                   out_dir=WORK / f"_vo_{speaker}", lead_in=0.3,
                   settings={speaker: base.VOICE_SETTINGS[speaker]})
    events, clips = flatten_placements([(perf, 0.0)])
    clips = duo.grunge_clips(events, clips, WORK)        # weird/grungy VO
    total = max(e.end for e in events) + TAIL
    cues = sorted(({"start": c["start"], "end": c["end"], "value": c["value"]}
                   for e in events for c in e.cues), key=lambda c: c["start"])
    frames = render_closeup(speaker, cues, total, WORK / "_actors")

    bg = base._make_background()
    style = CaptionStyle(mode="color+grow+lift", base=(238, 242, 255),
                         active=(255, 205, 79), stroke_fill=(8, 9, 30))
    work = WORK / f"_frames_{speaker}"
    work.mkdir(parents=True, exist_ok=True)
    for f in work.glob("*.png"):
        f.unlink()
    n = int(total * FPS)
    for i in range(n):
        t = i / FPS
        frame = bg.copy().convert("RGBA")
        a = Image.open(frames[min(len(frames) - 1, i)]).convert("RGBA")
        w = ACTOR_W[speaker]
        a = a.resize((w, int(w * a.height / a.width)), Image.LANCZOS)
        cx, cy = W // 2, int(H * CY[speaker]) + int(math.sin(t * 2.2) * 5)
        frame.alpha_composite(a, (cx - a.width // 2, cy - a.height // 2))
        ev = events[0]
        if ev.start <= t <= ev.end:
            draw_caption(frame, ev.words, t, cy=int(H * 0.82), style=style)
        frame.convert("RGB").save(work / f"f_{i:05d}.png")

    audio = OUT / f"hook_{speaker}.scene.m4a"
    mux_clips(clips, audio, total)
    out = OUT / f"hook_{speaker}.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS),
                    "-i", str(work / "f_%05d.png"), "-i", str(audio),
                    "-map", "0:v", "-map", "1:a", "-c:v", "libx264",
                    "-pix_fmt", "yuv420p", "-crf", "19", "-c:a", "aac",
                    "-ar", "48000", "-shortest", "-movflags", "+faststart",
                    str(out)], check=True)
    print(f"  OK {out} ({total:.1f}s, {n} frames)")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    chars = ["doge", "alien"] if which == "all" else [which]
    for sp in chars:
        print(f"hook: {sp}")
        make_hook(sp)


if __name__ == "__main__":
    main()
