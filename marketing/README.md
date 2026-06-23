# Marketing video system

A small, reusable pipeline for making Such Moon Launch promo videos. The whole
idea: **every video is an ordered list of "segments," and a segment is just a
short video clip.** A clip comes from one of two places, and both render through
the same Godot Movie Maker capture:

- **Gameplay** : a level played by the autopilot (see `../game/test/README.md`).
- **A marketing scene** : a Godot scene we made for promo, 2D card or 3D mascot.

Then ffmpeg stitches the segments, mixes audio (game sound / music bed / your
voiceover), burns in captions, and exports all three social formats. Make a new
video by writing a new manifest, not new code.

## Pipeline

```
  [gameplay capture]  \
                        >--  segment clips (.avi/.mp4)  --[assemble.sh]-->  9:16 + 1:1 + 16:9
  [marketing scene]   /        (captured via Movie Maker)    ^
                                                              |
                                            music bed + voiceover + captions
```

## Layout

```
marketing/
  VISION.md            private dream doc (big ideas, not shipped)
  README.md            this file
  lib/
    capture.sh         render any Godot scene -> clip (off-screen Movie Maker)
    assemble.sh        ffmpeg: concat segments + audio + captions -> 3 formats
  stage/
    Stage3D.gd/.tscn   reusable 3D mascot stage: loads a GLB, frames it, plays
                       its animation, shows a caption. Placeholder box if no GLB.
  assets/
    characters/        drop Meshy GLBs here  (e.g. cosmonaut_doge.glb)
    music/  vo/        music beds and your voiceover takes
  videos/
    <name>/
      storyboard.md    the script / shot list / timing for one video
      build.sh         captures its segments + calls assemble.sh
  out/                 rendered outputs (git-ignored)
```

## Make a video

1. Write `videos/<name>/storyboard.md` (shots, captions, timing, VO lines).
2. Capture each segment to `out/<name>/seg_NN.*`:
   - gameplay: `lib/capture.sh res://game/levels/1/Level1.tscn out/<name>/seg_01.avi 900 --autopilot`
   - mascot:   `MK_GLB=res://marketing/assets/characters/doge.glb MK_CAPTION="much altitude" \`
               `  lib/capture.sh res://marketing/stage/Stage3D.tscn out/<name>/seg_02.avi 300`
3. Assemble: `lib/assemble.sh --out out/<name>/final --music assets/music/bed.mp3 \`
   `  --vo assets/vo/<name>.wav out/<name>/seg_01.avi out/<name>/seg_02.avi ...`
4. Posts come out as `final_16x9.mp4`, `final_1x1.mp4`, `final_9x16.mp4`.

## 3D mascots (Meshy.ai workflow)

1. In Meshy, generate the character (use `art/characters/cosmonaut.png` /
   `art/branding/logo_cosmonaut.png` as the image reference for Cosmonaut Doge;
   `game/martian/Martian.tscn` art for the Martian). Prefer a **rigged + animated**
   export so we get an idle/wave/laugh loop.
2. Export **GLB**. Drop it in `assets/characters/` (Godot imports `.glb` natively
   and brings its AnimationPlayer).
3. Film it: `MK_GLB=res://marketing/assets/characters/doge.glb MK_ANIM=idle \`
   `  MK_CAPTION="wow" lib/capture.sh res://marketing/stage/Stage3D.tscn out.avi 300`.
   `Stage3D` auto-frames the model, lights it, plays `MK_ANIM` (or the first
   animation), and shows the caption. Tune with `MK_CAM_DIST`, `MK_BG`, `MK_SPIN`.

## Notes / safety

- `capture.sh` launches Godot **off-screen** (`--position 6000,6000`) so the
  render window does not steal focus. It still has to render (Movie Maker can't be
  headless), it just stays out of your way.
- Telemetry and score submission are disabled under `--autopilot`, so gameplay
  captures never touch the live backend.
- `marketing/` is a dev tool. Add it to the export-exclude filter before shipping
  a build so these scenes/GLBs don't bloat the app.
- `out/` is git-ignored; large GLBs/music probably should be too (see `.gitignore`).
