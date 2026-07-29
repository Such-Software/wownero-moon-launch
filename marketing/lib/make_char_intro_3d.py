#!/usr/bin/env python3
"""3D lip-synced SpaceDoge vs Martian alien intro for MoonLaunch.

The 3D upgrade of make_char_intro.py: SAME two-line exchange, SAME two ElevenLabs
voices (so the VO cache is reused — no new API cost), SAME deep-space background
and lower-third captions. The only change is the actors: instead of 2D SVG puppets
they are pre-rendered 3D Blender characters (build_3d_alien.py + build_3d_spacedoge.py),
rendered on transparency and composited over the starfield. This is the 2D->3D
renderer swap the such-graphics 3d-characters doc describes — the performance JSON
is the asset, 3D is a new consumer of it.

Each actor is rendered ONCE for the whole timeline (mouth driven by its combined
viseme cues, idle otherwise), cached by content hash, then composited per frame.
Model: scripts/make_duo3d_video.py in vegan-IQ.

Run:
  SML_MARKETING_RUN_ID=char-intro-3d \
  python3 marketing/lib/make_char_intro_3d.py

Output:
  ~/Build/scratch/such-moon-launch/marketing/char-intro-3d/char_intro_3d.mp4
  (+ renderer audio and disposable working files in the same run directory)
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from workspace_paths import (
    blender_executable,
    marketing_run_root,
    such_graphics_source,
)

sys.path.insert(0, str(such_graphics_source()))

from PIL import Image

from such_graphics.dialogue import perform
from such_graphics.scene import flatten_placements, mux_clips
from such_graphics.subtitles import CaptionStyle, draw_caption

# reuse the 2D intro's script, voices, and space background verbatim
import make_char_intro as base

BLENDER = blender_executable()
MKT = HERE.parent
OUT = marketing_run_root()
WORK = OUT / "_char_intro_3d_work"

W, H = 1080, 1920
FPS = 30
TAIL = 0.6

# the two 3D character builders (invoked headless in `alpha` mode)
BUILD = {
    "alien": HERE / "build_3d_alien.py",
    "doge": HERE / "build_3d_spacedoge.py",
}
# per-actor alpha tile resolution (portrait-ish; character centred with margins)
RES = {"alien": (640, 860), "doge": (640, 860)}
# where each actor stands + how wide it composites. alien LEFT, doge RIGHT.
X_FRAC = {"alien": 0.28, "doge": 0.72}
ACTOR_W = {"alien": 560, "doge": 600}     # doge (the hero) reads a touch larger
CY_FRAC = 0.44                            # vertical centre of both actors
IDLE_BREATH = {"alien": 1.7, "doge": 0.0}


def render_actor(speaker, events, total, cache_root):
    """Render this character's alpha frames for the WHOLE timeline (mouth from its
    combined cues, idle between turns). Cached by (cues, total, res, script)."""
    cues = [{"start": c["start"], "end": c["end"], "value": c["value"]}
            for e in events if e.speaker == speaker for c in e.cues]
    cues.sort(key=lambda c: c["start"])
    res = RES[speaker]
    script = BUILD[speaker]
    key = hashlib.sha1(
        (json.dumps(cues) + f"{total:.2f}{res}" + script.read_text()).encode()
    ).hexdigest()[:16]
    out = cache_root / f"{speaker}_{key}"
    if out.exists() and (out / "done.txt").exists():
        frames = sorted(out.glob("f_*.png"))
        print(f"  [{speaker}] cache hit ({len(frames)} frames)")
        return frames
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.png"):
        f.unlink()
    cues_path = out / "cues.json"
    cues_path.write_text(json.dumps({"cues": cues}))
    env = dict(os.environ, SG3D_CUES=str(cues_path), SG3D_OUT=str(out),
               SG3D_DUR=f"{total:.3f}", SG3D_RES=f"{res[0]}x{res[1]}")
    print(f"  [{speaker}] rendering {int(total * FPS)} frames…")
    subprocess.run([BLENDER, "--background", "--python", str(script), "--", "alpha"],
                   env=env, check=True, stdout=subprocess.DEVNULL)
    (out / "done.txt").write_text("ok")
    return sorted(out.glob("f_*.png"))


def place(frame, tile_path, speaker, breath):
    """Composite one actor tile: scale to its target width, paste centred at its
    screen anchor. `breath` gently scales for an idle bob while speaking."""
    a = Image.open(tile_path).convert("RGBA")
    w = int(ACTOR_W[speaker] * (1 + breath))
    h = int(w * a.height / a.width)
    a = a.resize((max(1, w), max(1, h)), Image.LANCZOS)
    cx = int(W * X_FRAC[speaker])
    cy = int(H * CY_FRAC)
    frame.alpha_composite(a, (cx - a.width // 2, cy - a.height // 2))


def talk_breath(t, speaker, events, ramp=0.45):
    """Small 0..~1 emphasis around this speaker's turns (drives a subtle idle bob)."""
    w = 0.0
    for e in events:
        if e.speaker == speaker:
            up = min(1.0, max(0.0, (t - (e.start - 0.1)) / ramp))
            down = min(1.0, max(0.0, ((e.end + 0.1) - t) / ramp))
            w = max(w, up * down)
    return w


# Per-character voice FX — make the VO weirder + grungier. rubberband PITCH-shifts
# while PRESERVING duration, so the Rhubarb lip-sync cues still line up. Tunable.
#   doge  -> deep + gritty (pitch down, bitcrush, drive) = grungy growly dog.
#   alien -> higher + metallic warble (pitch up, flanger, crush) = weird/otherworldly.
VOICE_FX = {
    "doge":  "rubberband=pitch=0.84,acrusher=bits=6:samples=1:mode=log:mix=0.5,"
             "alimiter=limit=0.92",
    "alien": "rubberband=pitch=1.11,flanger=delay=6:depth=3:regen=7:speed=1.3,"
             "acrusher=bits=7:samples=1:mode=log:mix=0.4,alimiter=limit=0.92",
}


def grunge_clips(events, clips, work):
    """Apply each speaker's weird/grungy FX chain to its VO clip and return a new
    (start, file) list. rubberband keeps clip duration, so lip-sync is unaffected.
    Falls back to the clean clip on any ffmpeg failure."""
    fxdir = work / "_fx"
    fxdir.mkdir(parents=True, exist_ok=True)
    out = []
    for ev, (st, mp3) in zip(events, clips):
        chain = VOICE_FX.get(ev.speaker)
        if not chain:
            out.append((st, mp3))
            continue
        # Probe the clean duration and force the FX clip to match EXACTLY (apad fills
        # if rubberband shortened it, -t trims) so the lip-sync cues stay aligned.
        dur = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nk=1:nw=1", str(mp3)],
            capture_output=True, text=True).stdout.strip()
        dst = fxdir / f"{ev.speaker}_{Path(mp3).stem}.wav"
        try:
            args = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(mp3),
                    "-af", chain + ",apad"]
            if dur:
                args += ["-t", dur]
            args.append(str(dst))
            subprocess.run(args, check=True)
            out.append((st, dst))
            print(f"  [fx] {ev.speaker}: {chain.split(',')[0]}")
        except Exception as e:
            print(f"  [fx] {ev.speaker} failed ({e}); using clean VO")
            out.append((st, mp3))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)

    # SAME two-turn exchange + voices + per-character delivery as the 2D intro.
    perf = perform(base.SCRIPT, base.VOICES, out_dir=WORK / "_vo",
                   lead_in=0.35, gap=0.45, settings=base.VOICE_SETTINGS)
    placements = [(perf, 0.0)]
    events, clips = flatten_placements(placements)
    clips = grunge_clips(events, clips, WORK)   # weird + grungy per-character VO
    total = max(e.end for e in events) + TAIL
    print(f"timeline {total:.1f}s · {len(events)} lines")

    # render both 3D actors for the whole cut (cached by content hash)
    cache_root = WORK / "_actors"
    frames = {sp: render_actor(sp, events, total, cache_root)
              for sp in ("alien", "doge")}

    bg = base._make_background()
    style = CaptionStyle(mode="color+grow+lift", base=(238, 242, 255),
                         active=(255, 205, 79), stroke_fill=(8, 9, 30))

    def event_at(t):
        for e in events:
            if e.start <= t <= e.end:
                return e
        return None

    work = WORK / "_frames"
    work.mkdir(exist_ok=True)
    for f in work.glob("*.png"):
        f.unlink()
    n = int(total * FPS)
    for i in range(n):
        t = i / FPS
        frame = bg.copy().convert("RGBA")
        # draw the listener first, the speaker last (speaker on top if they overlap)
        ev = event_at(t)
        order = sorted(("alien", "doge"),
                       key=lambda sp: 1 if (ev and ev.speaker == sp) else 0)
        for sp in order:
            breath = math.sin((t + IDLE_BREATH[sp]) * 3.0) * 0.012 * \
                talk_breath(t, sp, events)
            fi = min(len(frames[sp]) - 1, i)
            place(frame, frames[sp][fi], sp, breath)
        if ev:
            draw_caption(frame, ev.words, t, cy=int(H * 0.82), style=style)
        frame.convert("RGB").save(work / f"f_{i:05d}.png")

    audio = OUT / "char_intro_3d.scene.m4a"
    mux_clips(clips, audio, total)
    out = OUT / "char_intro_3d.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS),
                    "-i", str(work / "f_%05d.png"), "-i", str(audio),
                    "-map", "0:v", "-map", "1:a", "-c:v", "libx264",
                    "-pix_fmt", "yuv420p", "-crf", "19", "-c:a", "aac",
                    "-ar", "48000", "-shortest", "-movflags", "+faststart",
                    str(out)], check=True)
    print(f"  OK {out}  ({total:.1f}s, {n} frames)")


if __name__ == "__main__":
    main()
