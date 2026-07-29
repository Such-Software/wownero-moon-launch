# AI-pilot short (first marketing video)

~25s vertical (9:16) hero piece. Doge-meme comedy with a dev-story spine. The
hook is true: we really did teach an AI to land on the moon. Optional founder VO;
captions carry it if there's no VO.

## Beats

| # | ~secs | Visual | Caption (doge) | VO (corny, optional) |
|---|-------|--------|----------------|----------------------|
| 1 | 0-3 | Cosmonaut Doge 3D mascot, idle, title vibe | "i taught an AI to land on the moon" | "So I taught an AI to land a rocket on the moon." |
| 2 | 3-9 | EARLY bot footage: spinning / falling back to Earth | "it was... not good. much tumble" | "It was... not good." |
| 3 | 9-16 | The WIN: clean climb-out + slingshot + landing (L1/L3) | "then it learned to slingshot. wow" | "Then it learned to swing around Earth. Look at this little guy go." |
| 4 | 16-21 | DEATH footage: Martian bonk + explosion; Martian mascot smug | "the Martian had other plans" | "And then the Martian showed up." |
| 5 | 21-25 | Cosmonaut Doge thumbs up + logo + store badges | "can you do better? Such Moon Launch" | "Think you can do better? It's free. Such Moon Launch." |

Tone: corny, warm, self-deprecating. Let the explosion land the joke.

## Segments to capture

```sh
cd marketing
MEDIA_RUN="${SUCH_BUILD_ROOT:-$HOME/Build}/scratch/such-moon-launch/marketing/ai-pilot-short"
mkdir -p "$MEDIA_RUN"
# beat 1 + 5 mascot (swap MK_GLB once the Meshy Cosmonaut Doge GLB is in assets/characters/)
MK_CAPTION="i taught an AI to land on the moon" \
  lib/capture.sh res://marketing/stage/Stage3D.tscn "$MEDIA_RUN/seg_01.avi" 180
MK_GLB=res://marketing/assets/characters/cosmonaut_doge.glb MK_ANIM=idle MK_CAPTION="can you do better?" \
  lib/capture.sh res://marketing/stage/Stage3D.tscn "$MEDIA_RUN/seg_05.avi" 240

# beat 2 early-flail gameplay: temporarily set bad params so it fails on purpose
AP_TURN_GAIN=1 AP_ESCAPE_RADIUS=120 \
  lib/capture.sh res://game/levels/1/Level1.tscn "$MEDIA_RUN/seg_02.avi" 360 --autopilot

# beat 3 the win (clean defaults)
lib/capture.sh res://game/levels/1/Level1.tscn "$MEDIA_RUN/seg_03.avi" 900 --autopilot

# beat 4 death by Martian (level 2+)
lib/capture.sh res://game/levels/2/Level2.tscn "$MEDIA_RUN/seg_04.avi" 700 --autopilot
```

## Assemble

```sh
MEDIA_RUN="${SUCH_BUILD_ROOT:-$HOME/Build}/scratch/such-moon-launch/marketing/ai-pilot-short"
lib/assemble.sh --out "$MEDIA_RUN/final" \
  --music assets/music/bed.mp3 \
  "$MEDIA_RUN/seg_01.avi" "$MEDIA_RUN/seg_02.avi" \
  "$MEDIA_RUN/seg_03.avi" "$MEDIA_RUN/seg_04.avi" \
  "$MEDIA_RUN/seg_05.avi"
# add  --vo assets/vo/ai_pilot_short.wav  once the voiceover is recorded
```

## TODO before this is post-ready
- Meshy: generate Cosmonaut Doge + Martian GLBs, drop in `assets/characters/`.
- Pick a music bed (royalty-free) into `assets/music/`.
- Trim each captured segment to its beat length (the table is the target timing).
- Optional: founder VO take into `assets/vo/`.
