# Such Moon Launch: marketing vision (private / dream big)

Internal doc. Not shipped. This is where we let the ideas run; the README next
to it is the actual buildable system.

## North star

Sell Such Moon Launch with a **reusable video system**, not one-off clips. Every
piece we make should make the next one cheaper. Output funnels to the App Store
and Google Play (the in-game splash and nags already link out).

## Voice and tone

Doge-meme comedy with a thread of authentic dev story. Corny but funny. "To the
moon", much/very/wow, the Martian as the comic villain. Underneath the jokes,
the honest indie-founder angle (the maker, the build, the AI playtester) gives it
a spine that travels beyond the meme crowd.

## Visual direction

Hybrid: the **game stays 2D** (it is the product), and **3D animated mascots**
carry the interludes, title stings, and reactions. The contrast pops and it reads
as produced without re-arting the game. Source the 3D from Meshy.ai (GLBs, ideally
rigged + animated), import into Godot, film with the same Movie Maker harness as
the gameplay.

## Cast

- **Cosmonaut Doge** : the hero pilot. Earnest, in over his head, lovable. (We
  already have `art/characters/cosmonaut.png` and `art/branding/logo_cosmonaut.png`
  as the 2D reference for a Meshy generation.)
- **The Martian** : the villain. Shows up on every level from 2 onward and bonks
  the player. Smug. (`game/martian/Martian.tscn` is the 2D reference.)
- Supporting: the Rocket, the planets, moonrocks ($WOW / wownero coin art).

## Content pillars

1. **Satisfying** : the clean slingshot landing. Dopamine, near-ASMR.
2. **Comedy fails** : glorious explosions and Martian bonks. Cheapest, most
   shareable content we have, and the AI generates it for free every time it dies.
3. **Meme + founder** : the "to the moon" angle plus "I built an AI to playtest
   my game." The dev story is itself a marketing asset.

## The AI-pilot narrative (our secret weapon)

We literally built an AI that learned to slingshot to the moon. That is a story:
- v1: "I taught an AI to land on the moon. It was... not good." (flailing footage)
- arc: "then it learned to slingshot off Earth's gravity." (the win)
- punchline: "then the Martian showed up." (death footage)
As the bot improves, the narrative grows: "we used AI to playtest every level so
they'd all be such wow." First marketing short is built on exactly this (see
`videos/ai_pilot_short/`).

## Dream-big roadmap (NOT committed; just where this could go)

- **Smarter AI pilot** : reactive hazard dodging so it can clear the hazard levels
  (the current ceiling). Unlocks footage of the bot beating the whole campaign.
- **"AI-playtested every level"** : turn the tuning process into a content series
  and a credibility flex ("every level is provably beatable").
- **Player vs AI ghost races** : race the bot's recorded run on a level. Easy
  hook, single-player, huge content potential ("can you beat the AI?").
- **Online PVP / multiplayer races** : the big dream. Real-time or async ghost
  leaderboards already exist (`moonlaunch_scores`), so async ghost races are the
  natural first step toward live PVP.
- **Character universe** : lean into Cosmonaut Doge + Martian lore, recurring
  skits, maybe merch / sticker packs / a mascot people recognize.

## Distribution

Vertical-first (9:16 for TikTok / Reels / Shorts: where mobile games actually
grow). 16:9 cut becomes the store-listing trailer and YouTube/Twitter/Bluesky.
1:1 for feed posts. The system emits all three from one master.
