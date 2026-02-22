# Wownero Moon Launch — TODO

> Crypto-themed space landing game. Land your rocket on celestial bodies, dodge hazards, collect crypto, upgrade your ship.

---

## 🔧 Immediate Fixes & Technical Debt

- [ ] **Debug level picker** — add a secret/debug menu to jump to any level (press D on main menu, or hold 3 fingers on mobile)
- [ ] **Fix Level 4 completion** — Victory.gd has no `case 4` for Next Level button; pressing it does nothing. Should show "Game Complete" or loop to Level 1 with NG+ flag
- [ ] **Fix save after Level 4** — saves `level: 5` which silently resets to Level 1 on Menu. Need proper "all levels complete" state
- [ ] **Remove debug print in eartharea.gd** — `print(gravity_point)` runs every frame, spamming console
- [ ] **Asteroid despawn** — asteroids never despawn and accelerate exponentially (`1.01^n`). Add max speed cap + despawn when off-screen by 1000px
- [ ] **Gamma ray null check** — `get_collider().name` can crash if collider is freed. Add null guard
- [ ] **Add Venus + Io orbits** — they're static unlike Moon/Mars. Give them slow orbital motion
- [ ] **Git: delete old APK/AAB binaries** — `MoonLaunch.aab` and `.idsig` are in the repo, bloating it
- [ ] **Remove `randomize()` calls** — unnecessary in Godot 4 (auto-seeded)

---

## 🎮 Gameplay — Core Loop

### Debug / Dev Tools
- [ ] **Level select screen** — unlocked levels shown with star ratings, locked levels greyed out. Dev mode: hold Shift+Click to unlock all
- [ ] **FPS/physics overlay** — toggle with F3 for debugging
- [ ] **Free camera mode** — detach camera from rocket to inspect level layout

### Ship Upgrades (between levels)
- [ ] **Upgrade shop screen** — spend collected crypto between levels
- [ ] **Thrust power** — upgrade rocket engine force (350 → 400 → 500...)
- [ ] **Fuel tank** — larger fuel capacity
- [ ] **Shield** — absorb one hit from asteroid/martian/gamma ray before death
- [ ] **Better rotation** — faster torque for tighter control
- [ ] **Reverse thrust power** — separate upgrade from forward thrust
- [ ] **Magnet** — auto-attract nearby crypto pickups
- [ ] **Armor plating** — increase crash speed threshold (100 → 150 → 200)
- [ ] **Landing gear** — increase landing speed threshold (40 → 60 → 80) for easier landings

### Fuel System
- [ ] **Fuel bar HUD** — display remaining fuel on screen
- [ ] **Fuel consumption** — thrust drains fuel; no fuel = drift only
- [ ] **Fuel pickups** — floating fuel canisters in levels
- [ ] **Fuel efficiency upgrade** — reduce drain rate

### Crypto Collectibles
- [ ] **WOW (Wownero)** — primary currency, common drop, used for upgrades
- [ ] **XMR (Monero)** — rare, worth 10x WOW, purple ring glow
- [ ] **BTC (Bitcoin)** — very rare, worth 50x WOW, golden glow
- [ ] **DOGE** — uncommon, worth 5x WOW, such wow
- [ ] **Floating crypto sprites** — spin slowly, bob up/down, sparkle effect
- [ ] **Collection animation** — fly toward ship on pickup, +amount popup text
- [ ] **Wallet HUD** — show current WOW balance during gameplay
- [ ] **Crypto spawner** — place crypto along flight paths and near hazards (risk/reward)

### Scoring & Progression
- [ ] **Star rating** — 1-3 stars per level based on time + fuel remaining + crypto collected
- [ ] **Best time per level** — save and display on level select
- [ ] **Total crypto wallet** — persisted across sessions, shown in shop
- [ ] **Achievements** — "First Landing", "Speed Demon" (under 10s), "Pacifist" (no deaths), "Crypto Whale" (1000 WOW), etc.
- [ ] **Leaderboard** — local initially, online later (Wownero testnet integration?)

---

## 🗺️ Levels & Content

### Existing Levels (polish)
- [ ] **Level 1 (Moon)** — tutorial prompts overlay ("Press UP to thrust!")
- [ ] **Level 2 (Mars)** — add a few crypto pickups as introduction to the mechanic
- [ ] **Level 3 (Venus)** — gamma rays + crypto scattered in the danger zone
- [ ] **Level 4 (Io)** — gamma rays + asteroids + crypto, the current "final" level

### New Levels (5-20+)
- [ ] **Level 5 — Jupiter** — massive gravity well, need upgraded thrust to escape
- [ ] **Level 6 — Saturn** — navigate through ring debris (asteroid belt)
- [ ] **Level 7 — Neptune** — dark level, limited visibility radius around ship
- [ ] **Level 8 — Pluto** — tiny target, extreme precision landing
- [ ] **Level 9 — Asteroid mining** — land on a moving asteroid (no gravity area)
- [ ] **Level 10 — Space station** — dock with a rotating station (match rotation)
- [ ] **Level 11+ — Procedural** — random planet placement, random hazards, infinite replayability
- [ ] **Boss Level — Martian Mothership** — large ship that spawns smaller martians, must dodge and land on it

### Level Features
- [ ] **Wormholes/portals** — teleport between two points on the map
- [ ] **Gravity slingshot** — use a planet's gravity to accelerate toward distant targets
- [ ] **Moving asteroids as obstacles** — not spawned, but pre-placed orbiting bodies
- [ ] **Solar wind** — constant directional force pushing the ship
- [ ] **Nebula zones** — areas that slow the ship or drain fuel
- [ ] **Black hole** — instant death if you get too close, extreme gravity pull

---

## 🎨 Visual & Audio

### Visual Polish
- [ ] **Particle trail** — rocket leaves a fading exhaust trail as it moves
- [ ] **Screen shake** — on death/explosion and heavy thrust
- [ ] **Planet atmospheres** — glow shader around planets
- [ ] **Parallax depth** — more background layers for depth perception
- [ ] **Landing animation** — ship settles, legs extend, dust particles
- [ ] **Better explosion** — replace sprite sheet with GPU particle explosion
- [ ] **Crypto pickup VFX** — sparkle + pulse when collected
- [ ] **UI animations** — buttons slide in, scores count up
- [ ] **Ship skins** — unlockable via crypto, purely cosmetic
- [ ] **Starfield shader** — replace static background with animated procedural stars

### Audio
- [ ] **Per-level BGM** — different tracks for different vibes (calm for Moon, tense for Io)
- [ ] **Crypto pickup sound** — satisfying coin/ding sound
- [ ] **Landing countdown beeps** — audio feedback during 3s landing timer
- [ ] **Low fuel warning** — alarm sound when fuel < 20%
- [ ] **Martian chase music** — intensity increases when being pursued
- [ ] **Victory fanfare** — better than current single WAV

---

## 🔫 Combat (Future)

- [ ] **Forward cannon** — shoot asteroids and martians
- [ ] **Missile launcher** — homing missiles, limited ammo (buyable with crypto)
- [ ] **Laser beam** — continuous beam weapon, drains fuel to fire
- [ ] **Mine layer** — drop mines behind you to stop pursuing martians
- [ ] **EMP pulse** — disable all martians in radius for 5 seconds
- [ ] **Weapons as upgrades** — buy in the shop between levels

---

## 🌐 3D / First Person (Future Phase)

- [ ] **3D landing mode** — switch to 3D view for final approach/landing sequence
- [ ] **First-person cockpit** — HUD overlay with instruments, see out the window
- [ ] **3D level prototype** — one level fully in 3D as proof of concept
- [ ] **VR support** — Godot 4 has OpenXR, landing a rocket in VR would be insane

---

## 📱 Platform & Distribution

- [ ] **Android export** — re-export with Godot 4.6.1, test on real devices
- [ ] **iOS export** — Xcode build, TestFlight distribution
- [ ] **Web export** — HTML5 build hosted on itch.io or wownero.org
- [ ] **Desktop builds** — Windows, macOS, Linux binaries
- [ ] **Landscape lock** — ensure all platforms run in landscape only
- [ ] **Touch controls testing** — verify joystick + thrust buttons feel good on actual phones
- [ ] **Adaptive UI** — scale controls for different screen sizes/aspect ratios
- [ ] **Controller support** — gamepad input mapping (Xbox/PS/Switch Pro)

---

## 🔗 Crypto Integration (Future)

- [ ] **Wownero wallet connection** — link a real WOW address
- [ ] **On-chain leaderboard** — submit scores as Wownero transactions (tiny amounts with memo)
- [ ] **Tip the developer** — in-game WOW donation address
- [ ] **Mining minigame** — idle mining between levels to earn WOW passively

---

## 🧪 Testing Checklist

### Already Working ✅
- [x] Level 1 — fly to Moon and land
- [x] Level 2 — fly to Mars and land
- [x] Level 3 — dodge gamma rays, land on Venus
- [x] Level 4 — dodge gamma rays + asteroids, land on Io
- [x] Side crash death detection
- [x] High-speed foot crash death
- [x] Martian contact death
- [x] Moon/Mars orbital movement
- [x] Victory screen with formatted time
- [x] Save/load level progress
- [x] Desktop keyboard controls (arrows + Escape)
- [x] Styled buttons (Menu, Victory, Help, Pause)
- [x] Help screen with correct instructions

### Needs Testing 🔍
- [ ] Mobile virtual joystick — test on actual Android device
- [ ] Mobile thrust buttons — verify position and responsiveness
- [ ] Mobile pause menu (menu TouchScreenButton)
- [ ] Level 3 gamma ray spawning and kill behavior
- [ ] Level 4 asteroid spawning, collision, death
- [ ] Victory → Next Level flow for all 4 levels
- [ ] Save persistence across app restarts
- [ ] EarthArea gravity — is it working or is it a dead scene?
- [ ] Edge case: rocket drifts infinitely far from all bodies
- [ ] Performance: confetti labels on victory screen

### Known Bugs 🐛
- [ ] Level 4 "Next Level" button does nothing (no case 4 in Victory.gd)
- [ ] Completing Level 4 saves level=5, which resets to Level 1 on next launch
- [ ] Asteroids accelerate forever with no speed cap or despawn
- [ ] `eartharea.gd` prints to console every frame
- [ ] Gamma ray `get_collider()` has no null check
- [ ] Venus and Io don't orbit (static, unlike Moon/Mars)
- [ ] `MoonLaunch.aab` and `.apk.idsig` still in repo (should be gitignored)

---

## 📋 Priority Order

1. **Debug level picker** (dev quality of life)
2. **Fix existing bugs** (Level 4 completion, asteroids, eartharea print)
3. **Fuel system + HUD** (core gameplay depth)
4. **Crypto collectibles** (WOW pickups in levels)
5. **Upgrade shop** (spend WOW between levels)
6. **Star rating + best times** (replay value)
7. **5 new levels** (content)
8. **Combat system** (guns, basic weapons)
9. **Visual/audio polish** (particles, screen shake, per-level music)
10. **Mobile deployment** (Android/iOS real device testing)
11. **Web build** (itch.io / wownero.org)
12. **3D prototype** (experimental, future phase)
