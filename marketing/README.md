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
  out/                 legacy rendered outputs (git-ignored; migrate to Build)
```

## Make a video

New renders default to
`${SUCH_BUILD_ROOT:-$HOME/Build}/scratch/such-moon-launch/marketing/<run-id>`.
Keep work-in-progress outside Seafile. After human review, promote an accepted,
immutable delivery to
`~/Seafile/Marketing Media/such-moon-launch/deliveries/YYYY-MM-DD-slug/` with a
README, manifest, SHA256SUMS, byte counts, review evidence, and verifier.
`source/`, `work/`, `deliveries/`, and `archive/` are the only project-level
lifecycle directories.

The Python character generators use the same boundary. Set
`SML_MARKETING_RUN_ID` for a named run, `SUCH_GRAPHICS_SRC` only to another
real checkout below `~/src`, and `SML_BLENDER_BIN` when Blender is not on
`PATH`. `SML_MARKETING_RUN_ROOT`, when needed, must remain below
`SUCH_BUILD_ROOT`, which itself must remain below `~/Build`.

1. Write `videos/<name>/storyboard.md` (shots, captions, timing, VO lines).
2. Set a Build workspace and capture each segment there:
   - `MEDIA_RUN="${SUCH_BUILD_ROOT:-$HOME/Build}/scratch/such-moon-launch/marketing/draft-001"`
   - `mkdir -p "$MEDIA_RUN"`
   - gameplay: `lib/capture.sh res://game/levels/1/Level1.tscn "$MEDIA_RUN/seg_01.avi" 900 --autopilot`
   - mascot:   `MK_GLB=res://marketing/assets/characters/doge.glb MK_CAPTION="much altitude" \`
               `  lib/capture.sh res://marketing/stage/Stage3D.tscn "$MEDIA_RUN/seg_02.avi" 300`
3. Assemble: `lib/assemble.sh --out "$MEDIA_RUN/final" --music assets/music/bed.mp3 \`
   `  --vo assets/vo/<name>.wav "$MEDIA_RUN/seg_01.avi" "$MEDIA_RUN/seg_02.avi" ...`
4. Posts come out as `final_16x9.mp4`, `final_1x1.mp4`, `final_9x16.mp4`.

## 3D mascots (Meshy.ai workflow)

1. In Meshy, generate the character (use `art/characters/cosmonaut.png` /
   `art/branding/logo_cosmonaut.png` as the image reference for Cosmonaut Doge;
   `game/martian/Martian.tscn` art for the Martian). Prefer a **rigged + animated**
   export so we get an idle/wave/laugh loop.
2. Export **GLB**. Drop it in `assets/characters/` (Godot imports `.glb` natively
   and brings its AnimationPlayer).
3. Film it: `MK_GLB=res://marketing/assets/characters/doge.glb MK_ANIM=idle \`
   `  MK_CAPTION="wow" lib/capture.sh res://marketing/stage/Stage3D.tscn "$MEDIA_RUN/mascot.avi" 300`.
   `Stage3D` auto-frames the model, lights it, plays `MK_ANIM` (or the first
   animation), and shows the caption. Tune with `MK_CAM_DIST`, `MK_BG`, `MK_SPIN`.

## Resolution, frame rate & determinism

The pipeline renders **1080p / 60fps end-to-end** by default — no upscaling step.

- **Capture** (`capture.sh`, `render_remote.sh`) grabs frames at `MK_RES` (default
  `1920x1080`).
- **Assemble** (`assemble.sh`) normalizes every segment to `MK_OUT_RES` (default
  `1920x1080`) at `MK_FPS` (default `60`), then emits the three socials. The 1:1 and
  9:16 crops pull a native `1080x1080` square straight out of the 1080p master
  (`crop=1080:1080:420:0`) — no upscaling — with 9:16 letterboxing that square top and
  bottom to `1080x1920`.
- Codec is unchanged: `libx264 -crf 20 -movflags +faststart`, AAC audio.

Env knobs:

| var | default | where | effect |
|-----|---------|-------|--------|
| `MK_RES` | `1920x1080` | capture | capture resolution |
| `MK_OUT_RES` | `1920x1080` | assemble | master + 16:9 resolution |
| `MK_FPS` | `60` | assemble | master frame rate |
| `SML_SEED` | `1337` (under `--capture`) | render_remote | RNG seed — **plumbed only; engine consumption pending (see below)** |
| `SML_RL_DETERMINISTIC` | `1` (under capture) | render_remote | greedy RL policy; set `""` for variance |

**Deterministic takes (PARTIAL today):** `render_remote.sh` always renders under
`--capture` and runs the RL pilot greedily by default (`SML_RL_DETERMINISTIC=1`), which
removes the biggest source of take-to-take variance. It also forwards `SML_SEED` (default
`1337`) to the remote engine, **but the engine does not yet consume it** — the global /
`globalvar` / `WarpTunnel` RNGs still randomize per run (`globalvar.gd:268,621`,
`WarpTunnel.gd:246`), so takes are **not yet bit-reproducible**. Physics timing is already
fixed by Movie Maker's fixed timestep. Full reproducibility lands when the engine-side seed
consumption ships (WP-E3 wave 2); until then `SML_SEED=42` has no effect on output.

**Render time:** 1080p60 under lavapipe is roughly **2–3× slower** than the old 720p30.
If a remote render crawls or the Vulkan/lavapipe path misbehaves, fall back to
`GODOT_DRIVER=opengl3` (llvmpipe).

## Native portrait 9:16 capture (WP-E2)

Cropping a landscape take down to 9:16 throws away most of the frame. A **native**
1080x1920 gameplay clip looks far better on Reels/Shorts/TikTok — but there is a catch:

> **The game is landscape-LOCKED.** `globalvar.gd:639` forces
> `DisplayServer.SCREEN_SENSOR_LANDSCAPE` on mobile and `project.godot` sets
> `window/handheld/orientation=4`. The in-game `Camera2D` lives on the rocket and is
> authored for a landscape viewport. If you simply render into a 1080x1920 window you get
> the *same landscape framing* squeezed into a tall frame — the playfield is a narrow band
> with dead space above/below (effectively self-letterboxed), not a real portrait shot.

So a true portrait take needs a **temporary marketing camera** that re-zooms and
re-centers the rocket's `Camera2D` for the portrait aspect. There are two paths.

### Recommended path — such-graphics marketing camera (works today)

`~/src/such-graphics` already solved this for this game. It stages two **capture-only**
autoload scripts into the render host at render time (they never touch this repo's
tree) via a temporary `override.cfg`, then renders at native 1080x1920:

- `scripts/godot/marketing_camera_overlay.gd` — a tiny autoload that, every frame, finds
  the node in the `rocket` group, grabs its `Camera2D`, and sets `camera.zoom` (from
  `SG_MKT_ZOOM`, default `2.6`) and disables drag/position-smoothing so the rocket stays
  centered. This is the whole trick: **it just retunes the existing camera for portrait**,
  it does not add a new camera or fight the landscape lock.
- `scripts/godot/marketing_slingshot_pilot.gd` — an optional capture-only opening
  maneuver (`SG_MKT_SLINGSHOT=1`): it takes over from AutoPilot, orbits Earth, wraps past
  half the planet, burns outward, then hands control **back** to AutoPilot (setting
  `tangent_bias`/`angle_tol`) so the transit + landing continue normally. Purely for a
  cinematic slingshot beat; leave it off for a plain landing take.
- `scripts/capture-wownero-gameplay.py` — the driver. It `rsync`s the two `.gd` files to
  the host, writes a temporary `override.cfg` that (a) sets
  `window/size/viewport_{width,height}` + `window_{width,height}_override` to
  `1080x1920`, `window/size/mode=0`, and (b) registers the two scripts under
  `[autoload]` (`MarketingCaptureCamera`, `MarketingSlingshotPilot`). It backs up any
  existing `override.cfg`, runs Godot under `xvfb-run -s "-screen 0 1080x1920x24"` with
  `--write-movie … --fixed-fps 60 --quit-after N --capture --autopilot`, then encodes
  the AVI to a color-managed H.264 MP4 (bt709, `crf 17`) and restores the override on a
  trap. Env it forwards: `SG_MKT_ZOOM`, `SG_MKT_CENTER`, `SG_MKT_SLINGSHOT`,
  `AP_TANGENT_BIAS`, `AP_ANGLE_TOL`, `SML_RL_LAND`, `SML_RL_DETERMINISTIC`.

One-liner (from the such-graphics repo):

```
python scripts/capture-wownero-gameplay.py \
  --host deb --scene res://game/levels/1/Level1.tscn \
  --size 1080x1920 --frames 1080 --slingshot \
  -o "$HOME/Build/scratch/such-moon-launch/marketing/l1-portrait/l1_portrait.mp4"
```

This yields a native 1080x1920 clip with the rocket + target actually framed for
portrait, HUD not clipped. It's the recommended portrait path **because the framing
problem is already solved there** — nothing to port, nothing to verify.

### render_remote SML_PORTRAIT plumb (starting point in THIS repo)

`render_remote.sh` now understands `SML_PORTRAIT=1`, which flips the default capture
resolution to **native 9:16 (1080x1920)** and — because it already forwards
`MK_OUT_RES="$RES"` into `assemble.sh` — keeps the assembled master native portrait with
**no crop/upscale** step added:

```
SML_MARKETING_RUN_ID=l1-portrait SML_PORTRAIT=1 marketing/lib/render_remote.sh 1 15
```

This is deliberately only the **resolution + assembly** half of the job. It is the
STARTING point the marketing camera plugs into — **framing is still landscape** until you
also stage a camera override, exactly like the such-graphics scripts above. Without that
override a `SML_PORTRAIT=1` take will render the landscape playfield into a tall frame
(self-letterboxed), which is fine for a resolution/pipeline smoke test but not a
publishable portrait shot. An explicit `MK_RES` always overrides the `SML_PORTRAIT`
default.

To make `SML_PORTRAIT=1` produce publishable framing **from this repo**, port the
such-graphics approach in: copy the two capture-only autoload `.gd` files (or a trimmed
`marketing_camera_overlay.gd`) into `marketing/`, and have `render_remote.sh` stage them
via a temporary `override.cfg` `[autoload]` block when `SML_PORTRAIT=1` (backing up /
restoring any existing override, as the such-graphics driver does). Also spot-check the
HUD at portrait aspect — `MobileUI.gd` positions by viewport size
(`MobileUI.gd:89-115`), so anchors should adapt, but this needs a real render to confirm.

> **Verification deferred:** the acceptance for WP-E2 (a real 1080x1920 L1 take with the
> rocket + target framed through the slingshot and HUD un-clipped) requires an actual GPU
> render, and the render box is busy with an RL training run. The code + this doc are the
> shippable deliverable; framing verification lands with the next render window.

| var | default | where | effect |
|-----|---------|-------|--------|
| `SML_PORTRAIT` | unset | render_remote | `1` = native 9:16 (1080x1920) capture + assembly; framing still needs the marketing-camera override (see above) |

## Notes / safety

- `capture.sh` launches Godot in a **minimized** window (a temporary `override.cfg`
  sets `window/size/mode=1`, see `capture.sh:48-52`) so the render window lives in the
  Dock — never on-screen, never steals focus. It still has to render (Movie Maker can't
  be headless), it just stays out of your way. (It deliberately does **not** pass
  `--position` — that forces the window back out of minimized mode and onto the screen.)
- Telemetry and score submission are disabled under `--autopilot`, so gameplay
  captures never touch the live backend.
- `marketing/` is a dev tool. Add it to the export-exclude filter before shipping
  a build so these scenes/GLBs don't bloat the app.
- `out/` is retained only for legacy compatibility. Use Build scratch/review
  space for new generated media and promote only approved deliveries to Seafile.
