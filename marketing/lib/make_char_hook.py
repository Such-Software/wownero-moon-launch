#!/usr/bin/env python3
"""Solo HOOK clips for social video: ONE character (full body, not a jammed-in face)
delivering a short punchy line over an ALIVE space background — comets streak by and
a little UFO drifts through. Reuses the duo pipeline's voices, weird/grungy FX,
captions and background (make_char_intro + make_char_intro_3d); just a single actor.
These are the openers for the three videos (doge hook, alien hook, duo).

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

from PIL import Image, ImageDraw

from such_graphics.dialogue import perform
from such_graphics.scene import flatten_placements, mux_clips
from such_graphics.subtitles import CaptionStyle, draw_caption

import make_char_intro as base          # voices, VOICE_SETTINGS, background
import make_char_intro_3d as duo        # BLENDER, VOICE_FX, grunge_clips

BLENDER = duo.BLENDER
MKT = HERE.parent
OUT = MKT / "out"
WORK = OUT / "_hook_work"
W, H, FPS, TAIL = 1080, 1920, 30, 0.7

# Short, punchy hook lines (no "grr"). Same voices + FX as the duo.
HOOKS = {
    "doge":  "Think you can fly this rocket?",
    "alien": "Give up, human. You can't fly this thing.",
}
BUILD = {"doge": HERE / "build_3d_spacedoge.py", "alien": HERE / "build_3d_alien.py"}
# Full-character tile (default camera shows head + body), composited large but not
# face-cropped, sitting a little low so there's room for the sky action above.
RES = {"doge": (640, 900), "alien": (640, 900)}
ACTOR_W = {"doge": 860, "alien": 820}
CY = {"doge": 0.50, "alien": 0.50}

# Sky action: comets streak through, one small UFO drifts across the top.
# (t0, x0_frac, y0_frac, vx_px/s, vy_px/s, head_r, rgb)
COMETS = [
    (0.10, 1.18, 0.06, -1050, 560, 7, (185, 212, 255)),
    (0.95, -0.18, 0.24, 1180, 360, 6, (255, 232, 190)),
    (1.70, 1.15, 0.42, -980, 300, 8, (206, 190, 255)),
    (0.55, 0.28, -0.12, 300, 900, 5, (255, 255, 240)),
    (2.35, -0.15, 0.14, 1240, 250, 6, (190, 235, 255)),
]


def _bg_action(bg, t):
    """Draw moving comets + a drifting UFO onto a copy of the space bg (behind the
    actor) so the hook reads as a scene, not a static portrait."""
    im = bg.copy()
    d = ImageDraw.Draw(im, "RGBA")
    for (t0, xf, yf, vx, vy, r, col) in COMETS:
        s = t - t0
        if s < 0.0 or s > 2.2:
            continue
        x = xf * W + vx * s
        y = yf * H + vy * s
        for k in range(9):                          # fading trail behind the head
            tx, ty = x - vx * 0.013 * k, y - vy * 0.013 * k
            a = int(150 * (1.0 - k / 9.0))
            rr = r * (1.0 - k / 11.0)
            d.ellipse((tx - rr, ty - rr, tx + rr, ty + rr), fill=(*col, a))
        d.ellipse((x - r, y - r, x + r, y + r), fill=(*col, 235))
    ux = int((-0.25 + t / 3.4) * W)                 # slow UFO across the upper third
    uy = int(0.15 * H)
    d.ellipse((ux - 40, uy - 12, ux + 40, uy + 12), fill=(96, 205, 150, 225))
    d.ellipse((ux - 18, uy - 24, ux + 18, uy - 2), fill=(160, 235, 255, 205))
    for bx in (-24, 0, 24):                         # under-glow lights
        d.ellipse((ux + bx - 3, uy + 9, ux + bx + 3, uy + 15), fill=(255, 240, 160, 220))
    return im


def render_solo(speaker, cues, total, cache_root):
    """Render this character's FULL-BODY alpha frames (default camera). Cached by
    (cues, total, res, script)."""
    res = RES[speaker]
    script = BUILD[speaker]
    key = hashlib.sha1((json.dumps(cues) + f"{total:.2f}{res}solo" +
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
    env = dict(os.environ, SG3D_CUES=str(cp), SG3D_OUT=str(out),
               SG3D_DUR=f"{total:.3f}", SG3D_RES=f"{res[0]}x{res[1]}")
    env.pop("SG3D_CLOSEUP", None)                   # full body, not a face close-up
    print(f"  [{speaker}] rendering {int(total * FPS)} frames…")
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
    frames = render_solo(speaker, cues, total, WORK / "_actors")

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
        frame = _bg_action(bg, t).convert("RGBA")
        a = Image.open(frames[min(len(frames) - 1, i)]).convert("RGBA")
        w = ACTOR_W[speaker]
        a = a.resize((w, int(w * a.height / a.width)), Image.LANCZOS)
        cx = W // 2
        cy = int(H * CY[speaker]) + int(math.sin(t * 2.2) * 5)
        frame.alpha_composite(a, (cx - a.width // 2, cy - a.height // 2))
        ev = events[0]
        if ev.start <= t <= ev.end:
            draw_caption(frame, ev.words, t, cy=int(H * 0.86), style=style)
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
