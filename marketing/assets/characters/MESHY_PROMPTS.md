# Meshy 3D mascot prompts + animations (BRAINSTORM, not final)

Draft list for generating the marketing mascots in Meshy.ai. Iterate freely. The
`Stage3D` scene already auto-frames/lights/animates any GLB you drop in
`marketing/assets/characters/` (see `marketing/README.md`).

## Style guide (keep all mascots consistent)

- **Vibe:** chunky, stylized, slightly-cartoon, retro-space + doge-meme. Readable
  at small sizes (it's mostly vertical phone video). Bold shapes, not realistic.
- **Palette:** match the game — deep space navy/indigo background, doge-yellow/gold
  highlights, the $WOW orange, clean whites for the suit.
- **For brand consistency, prefer Image-to-3D** seeded from the game's own art:
  - Cosmonaut Doge ref: `art/characters/cosmonaut.png`, `art/branding/logo_cosmonaut.png`
  - Martian ref: art in `game/martian/Martian.tscn`
  - Coin/rock ref: `art/coins/wownero-wow-logo.png`
- Always request a **rigged** model + **GLB** export. Grab a couple of **animations**
  per character (Meshy's animation library or text-to-animation).

## Cast

### 1. Cosmonaut Doge — the hero (most important)
- **Prompt (text-to-3D fallback):** "a cute chunky Shiba Inu astronaut mascot in a
  rounded retro white spacesuit with a gold-tinted bubble helmet, big friendly
  eyes, stylized low-poly cartoon, doge-meme charm, space game mascot"
- **Animations:** `idle` (gentle float/breathe), `wave`, `thumbs_up`, `cheer`
  (celebrate a landing), `facepalm` (for the fails), `point` (at store badges).

### 2. The Martian — the villain
- **Prompt:** "a small smug green alien martian in a little flying-saucer scout
  ship, big eyes, antenna, stylized low-poly cartoon, mischievous grin, retro UFO"
- **Animations:** `hover_idle`, `laugh`/`taunt` (after it bonks the player),
  `zap`/`point` (menacing), `sneak` (creeping in).

### 3. The Rocket — optional prop / sting
- **Prompt:** "a stubby retro cartoon rocket ship, rounded fins, single porthole,
  glossy red-and-white, stylized low-poly, friendly"
- **Animations:** `idle_wobble`, `blast_off` (for title stings / transitions).

### 4. $WOW coin / Moonrock — spinner props
- **Prompt:** "a glossy gold crypto coin embossed with a stylized Shiba face, thick
  rim, doge-meme" / "a chunky grey moon rock with subtle gold flecks"
- **Animations:** none needed — `Stage3D` spins them (MK_SPIN).

## How they get used (ties to the AI-pilot short storyboard)

- Beat 1 hook: Cosmonaut Doge `idle` + title caption.
- Beat 4 punchline: Martian `laugh` over the crash footage.
- Beat 5 CTA: Cosmonaut Doge `thumbs_up` + store badges.
- Recurring series: Doge vs Martian skits between gameplay clips.

## TODO
- [ ] Generate Cosmonaut Doge first (it's in every video); test it in `Stage3D`.
- [ ] Then the Martian.
- [ ] Decide: one consistent art-style seed image so all mascots match.
