# Wownero Moon Launch — TODO

> Crypto-themed space landing game. Land your rocket on celestial bodies, dodge hazards, collect crypto, upgrade your ship.

---

## � Phase 1: Foundation & Web Export

- [x] **Remove `[dotnet]` config** — deleted the `[dotnet]` section from project.godot. No C# code exists; this is pure GDScript. Removes Mono dependency for clean web/mobile exports.
- [x] **Delete dead scripts** — removed `QuitButton.gd` + `.uid` and `helpbuttons.gd` + `.uid` from project root. Neither was referenced by any scene or script.
- [x] **Create export presets** — added `export_presets.cfg` with Web, Android, iOS, Windows, macOS, Linux targets. Export paths set to `builds/<platform>/`. Android package: `org.wownero.moonlaunch`.
- [ ] **Verify web build** — export HTML5, test in Chrome/Firefox/Safari: confirm save/load (IndexedDB), leaderboard API (HTTPRequest), touch input emulation all work
- [ ] **Secure HMAC secret** — configure build-time secret for ScoreClient.gd before public launch (currently empty string)
- [x] **Save file migration** — audited `globalvar.load_game()` — already uses `.get(key, default)` for every field. New keys fall back to defaults safely.

---

## 🔧 Technical Debt (Completed)

- [x] **Debug level picker** — secret/debug menu to jump to any level (press D on main menu, or hold 3 fingers on mobile)
- [x] **Fix Level 4 completion** — Victory.gd shows level name, routes to UpgradeShop. "Upgrades & Menu" at max level. Extensible for new levels.
- [x] **Fix save after Level 4** — tracks `highest_level_completed`, caps save at MAX_LEVEL, `all_completed` flag
- [x] **Remove debug prints** — all `print()` calls removed from game code
- [x] **Asteroid despawn** — speed cap (300), reduced accel, despawn at 2000px from rocket
- [x] **Gamma ray null check** — added collider null guard
- [x] **Add Venus + Io orbits** — orbital scripts (Venus 0.008 rad/s, Io 0.010 rad/s)
- [x] **Git: delete old APK/AAB binaries** — removed + .gitignore covers `*.aab`, `*.apk`, `*.apk.idsig`
- [x] **Remove `randomize()` calls** — removed from all files (Godot 4 auto-seeds)
- [x] **Art folder reorganization** — moved to backgrounds/, planets/, ship/, asteroids/, coins/, characters/, effects/, ui/, audio/, branding/
- [x] **Menu.gd uses globalvar.LEVEL_SCENES** — no more hardcoded match statements
- [x] **Debug level picker reads from LEVEL_SCENES** — auto-updates when new levels are added

---

## 🎮 Gameplay — Core Loop

### Debug / Dev Tools
- [x] **Level select screen** — debug level picker (press D on menu), reads from globalvar.LEVEL_SCENES
- [x] **FPS/physics overlay** — toggle with F3 for debugging
- [ ] **Free camera mode** — detach camera from rocket to inspect level layout

### Ship Upgrades (between levels)
- [x] **Upgrade shop screen** — spend collected crypto between levels (UpgradeShop.gd/.tscn)
- [x] **Thrust power** — upgrade rocket engine force (350 → 400 → 500...)
- [x] **Fuel tank** — larger fuel capacity
- [x] **Shield** — absorb one hit from asteroid/martian/gamma ray before death
- [x] **Better rotation** — faster torque for tighter control
- [x] **Reverse thrust power** — separate upgrade from forward thrust
- [x] **Magnet** — auto-attract nearby crypto pickups
- [x] **Armor plating** — increase crash speed threshold (100 → 150 → 200)
- [x] **Landing gear** — increase landing speed threshold (40 → 60 → 80) for easier landings

### Fuel System
- [x] **Fuel bar HUD** — display remaining fuel on screen (FuelBar.gd)
- [x] **Fuel consumption** — thrust drains fuel; no fuel = drift only
- [x] **Fuel pickups** — floating fuel canisters in levels
- [x] **Fuel efficiency upgrade** — reduce drain rate (in upgrade shop)

### Crypto Collectibles
- [x] **WOW (Wownero)** — primary currency, common drop, used for upgrades
- [x] **XMR (Monero)** — rare, worth 10x WOW, purple ring glow
- [x] **BTC (Bitcoin)** — very rare, worth 50x WOW, golden glow
- [x] **DOGE** — uncommon, worth 5x WOW, such wow
- [x] **Floating crypto sprites** — spin slowly, bob up/down, self-drawing (CryptoPickup.gd)
- [x] **Collection animation** — fly toward ship on pickup, +amount popup text
- [x] **Wallet HUD** — show current WOW balance during gameplay (WalletHUD.gd)
- [x] **Crypto spawner** — drop-in CryptoSpawner.gd with weighted random types + min spacing

### Scoring & Progression
- [x] **Star rating** — 1-3 stars per level based on time + fuel remaining + crypto collected
- [x] **Best time per level** — save and display on level select
- [x] **Total crypto wallet** — persisted across sessions, shown in shop
- [ ] **Achievements** — "First Landing", "Speed Demon" (under 10s), "Pacifist" (no deaths), "Crypto Whale" (1000 WOW), etc.
- [x] **Leaderboard** — backend API at api.such.software, per-level rankings, auto-submit on victory

---

## 💰 Phase 2: Monetization

### Ads (Primary Revenue)
- [ ] **Interstitial ads** — show between levels (after Victory screen, before Upgrade Shop). Never during gameplay.
- [ ] **Rewarded video ads** — "Watch ad for 50 WOW" button on death screen and in upgrade shop. Opt-in only.
- [ ] **Banner ad** — menu screen only. Removed during gameplay.
- [ ] **Web ad integration** — Google AdSense/Ad Manager via JavaScript bridge for HTML5 builds.

### Cosmetic IAP
- [ ] **Ship skins** — unlockable rocket textures. Free skins earned via achievements (gold rocket for all 3★, skull rocket for 50 deaths). Premium skins via small IAP ($0.99–$2.99) or large WOW amounts.
- [ ] **Skin storage** — save selected skin in savegame.json, apply as texture swap in rocket.gd `_ready()`.

### Premium Content
- [ ] **Level pack unlock** — Levels 1–4 free. Levels 5–10 unlockable via one-time $2.99 IAP OR earning 2000 WOW in-game (grindable but incentivizes ad watching).

### Crypto Tipping
- [ ] **"Support the Dev" button** — menu screen, shows Wownero donation address as QR code + copy-to-clipboard. Zero friction, high goodwill.
- [ ] **Community tip jar** — fetch total community donations from API, show running total in-game.

---

## 🎯 Phase 4: Fairness & Fun

### Difficulty Rebalance
- [x] **Level 2 Martian reduction** — reduced from 5 to 2 Martians, speed=25. Smooth ramp from Level 1.
- [x] **Progressive ramp** — Level 1: 0 enemies. Level 2: 2 slow Martians. Level 3: 4 Martians + gamma rays. Level 4: 6 Martians + gamma rays + asteroids.
- [x] **Martian speed scaling** — Level 2: 25, Level 3: 32–35, Level 4: 40–45. Per-instance speed set in .tscn.

### Retry & Checkpoints
- [ ] **Celestial waypoints (Levels 5+)** — instead of arbitrary position checkpoints, use intermediate planets as natural waypoints. Entering a waypoint planet's gravity well = auto-checkpoint. On death, respawn orbiting the last waypoint with preserved velocity/fuel.
- [ ] **Waypoint as gameplay** — waypoint planets double as gravity slingshot opportunities and refueling stations. Fuel pickups clustered near waypoints.
- [ ] **Retry button (Levels 1–4)** — short levels get a simple free "Retry Level" on death. No checkpoints needed.
- [ ] **Checkpoint retry (Levels 5+)** — on death, offer "Retry from waypoint (25 WOW or watch ad)" vs "Retry Level (free)".
- [ ] **Multi-body level architecture:**
  - Levels 1–4: Earth → Target (no waypoints, quick retry)
  - Levels 5–8: Earth → 1 Waypoint → Target (one checkpoint)
  - Levels 9–10: Earth → 2 Waypoints → Target (two checkpoints)
  - Endless mode: Earth → Waypoint → Waypoint → ... (each = checkpoint)

### Visual Feedback
- [x] **Screen shake** — Camera2D offset randomized on death (intensity=12, decay over frames). Added to rocket.gd.
- [x] **Particle exhaust trail** — GPUParticles2D "ExhaustTrail" in Rocket.tscn (30 particles, 1.5s lifetime, world-space trail).
- [x] **Low fuel warning** — fuel bar flashes red at <20% (4Hz toggle), dark red background, pulsing border, "LOW FUEL" text.
- [x] **Landing proximity beeps** — `tone1.ogg` from Kenney Digital Audio, pitch scales 0.8→2.0 and volume -18→-3 dB as rocket approaches target (250px range), interval shrinks 0.6s→0.1s.
- [x] **Better explosion** — GPUParticles2D one-shot burst (40 particles, 0.8s, sphere emission, 80-200 velocity, fire gradient). Layered SFX: original explosion.wav + `explosionCrunch_000.ogg` + `lowFrequency_explosion_000.ogg` from Kenney Sci-Fi Sounds.
- [x] **Gravity field visualization** — translucent blue arc rings on all planets via `_draw()`, auto-detects gravity radius from Area2D child.

### Game Feel
- [x] **Slow-motion landing** — within 80px of target at speed < 80 → Engine.time_scale = 0.7. Reverts on death/land/menu. Added to rocket.gd.
- [ ] **Crypto pickup VFX** — sparkle + pulse when collected
- [ ] **UI animations** — buttons slide in, scores count up on victory screen

---

## 🗺️ Phase 3: Content Expansion

### Existing Levels (polish)
- [ ] **Level 1 (Moon)** — tutorial prompts overlay ("Press UP to thrust!"). First-time only, saved to prefs.
- [ ] **Level 2 (Mars)** — rebalance Martians (see Phase 4), add crypto pickups as introduction
- [ ] **Level 3 (Venus)** — gamma rays + crypto scattered in the danger zone
- [ ] **Level 4 (Io)** — gamma rays + asteroids + crypto, the current "final" level

### New Levels (5–10)
- [ ] **Level 5 — Jupiter** — 2x gravity, requires upgraded thrust. Introduce gravity slingshot mechanic.
- [ ] **Level 6 — Saturn** — navigate through ring debris (pre-placed orbiting asteroid belt).
- [ ] **Level 7 — Neptune** — dark level, Light2D visibility radius around ship, rest is black.
- [ ] **Level 8 — Pluto** — tiny target (20px), extreme precision. Minimal gravity. Random wind gusts.
- [ ] **Level 9 — Asteroid mining** — land on a moving asteroid (no gravity area, match velocity).
- [ ] **Level 10 — Space station** — dock with a rotating station (match rotation to land).

### Endgame Content
- [ ] **Procedural endless mode** — unlocked after Level 10. Random planets, random hazards, difficulty scales with run length. Leaderboard for furthest distance / most landings.
- [ ] **Boss Level — Martian Mothership** — large ship spawning smaller Martians. Must dodge and land on its pad.

### Level Features
- [ ] **Wormholes/portals** — teleport between two points on the map
- [ ] **Gravity slingshot** — use a planet's gravity to accelerate toward distant targets
- [ ] **Moving asteroids as obstacles** — pre-placed orbiting bodies
- [ ] **Solar wind** — constant directional force pushing the ship
- [ ] **Nebula zones** — areas that slow the ship or drain fuel
- [ ] **Black hole** — instant death if too close, extreme gravity pull


### 🎨 Visual & Audio

### Visual Polish
- [ ] **Planet atmospheres** — glow shader around planets
- [ ] **Parallax depth** — more background layers for depth perception
- [ ] **Landing animation** — ship settles, legs extend, dust particles
- [ ] **Ship skins** — unlockable via crypto, purely cosmetic
- [ ] **Starfield shader** — replace static background with animated procedural stars

### Audio
- [ ] **Per-level BGM** — different tracks for different vibes (calm for Moon, tense for Io)
- [ ] **Crypto pickup sound** — satisfying coin/ding sound
- [ ] **Landing countdown beeps** — audio feedback during 3s landing timer
- [ ] **Martian chase music** — intensity increases when being pursued
- [ ] **Victory fanfare** — upgrade from current single WAV


### 🔫 Combat 

- [ ] **Forward cannon** — shoot asteroids and martians (upgrade, costs 500 WOW)
- [ ] **Missile launcher** — homing missiles, limited ammo (buyable with crypto)
- [ ] **Laser beam** — continuous beam weapon, drains fuel to fire
- [ ] **Mine layer** — drop mines behind you to stop pursuing martians
- [ ] **EMP pulse** — disable all martians in radius for 5 seconds
- [ ] **Weapons as upgrades** — buy in the shop between levels


### 🌐 3D / First Person 

- [ ] **3D landing mode** — switch to 3D view for final approach/landing sequence
- [ ] **First-person cockpit** — HUD overlay with instruments, see out the window
- [ ] **3D level prototype** — one level fully in 3D as proof of concept
- [ ] **VR support** — Godot 4 has OpenXR, landing a rocket in VR would be insane

---

## 📱 Phase 5: Platform & Distribution

- [ ] **Web deployment** — HTML5 build hosted on itch.io (pay-what-you-want + ad rev share) and wownero.org
- [ ] **Android export** — signed APK/AAB, Google Play + F-Droid
- [ ] **iOS export** — Xcode build, TestFlight distribution
- [ ] **Desktop builds** — Windows .exe, macOS .dmg, Linux .AppImage via itch.io + GitHub Releases
- [ ] **Landscape lock** — ensure all platforms run in landscape only
- [ ] **Touch controls testing** — verify joystick + thrust buttons feel good on actual phones
- [ ] **Adaptive UI** — scale controls for different screen sizes/aspect ratios
- [ ] **Controller support** — gamepad input mapping (Xbox/PS/Switch Pro)

---

## 🔗 Wownero (WOW) Crypto Integration — App Store Strategy

> How to integrate real Wownero without getting rejected from Apple/Google.

### The Problem
Apple and Google ban apps that facilitate cryptocurrency **mining**, **trading**, or **unregulated payments**. They also reject apps that bypass their in-app purchase systems for digital goods. Violations result in rejection or removal.

### What IS Allowed ✅
- **Displaying crypto wallet addresses** for donations/tips (like Wikipedia does)
- **Linking to external websites** for crypto transactions (not in-app)
- **Using crypto branding/themes** purely as game flavor (our coins are fine)
- **Read-only blockchain data display** (showing balances, transactions, leaderboard entries)
- **QR codes for external wallets** — the user leaves the app to complete any transaction
- **Educational content** about cryptocurrency

### What is NOT Allowed ❌
- In-app crypto mining (even idle/simulated if it touches real chains)
- In-app crypto trading or swaps
- Sending/receiving real crypto within the app
- Using crypto to bypass IAP (e.g., "pay 10 WOW instead of $0.99")
- Unregistered financial services

### Recommended Integration Plan

#### Tier 1 — Safe & Simple (Day 1)
- **"Tip the Dev" button** on menu screen → shows a Wownero address as QR code + tap-to-copy. User opens their own wallet app externally. This is identical to how donation-funded apps work. **App store safe.**
- **Community donation counter** — fetch total donations from a public API endpoint, display "Community has tipped X WOW!" on menu. Read-only display. **App store safe.**
- **Crypto theme stays** — WOW/XMR/BTC/DOGE as in-game collectibles are purely cosmetic game flavor, not real tokens. **App store safe.**

#### Tier 2 — External Wallet Link (Post-Launch)
- **"Connect Wallet" (read-only)** — user enters their WOW address (or scans QR). Game displays their real WOW balance on the menu as a vanity feature. No transactions happen in-app. **App store safe** (same as portfolio tracker apps).
- **On-chain leaderboard viewer** — display leaderboard entries that were submitted as Wownero tx memos (submitted externally, viewed in-app). Read-only. **App store safe.**
- **Achievement badge links** — when player earns an achievement, show a "Claim on-chain badge" button that opens a website URL. Minting happens in browser, not in-app. **App store safe** (same as how OpenSea links work in apps).

#### Tier 3 — Web-Only Features (No App Store Restrictions)
The web build (itch.io / wownero.org) has **no app store rules**. These features should be web-exclusive:
- **Wownero wallet integration** — connect wallet, send/receive WOW directly in the web app
- **Play-to-earn mode** — earn real micro-WOW for completing levels (funded by developer/community pool)
- **On-chain score submission** — submit scores as Wownero transactions with memo data
- **Mining minigame** — idle Wownero mining between levels (WebAssembly miner, opt-in only)
- **WOW-gated content** — "Hold 100 WOW to unlock exclusive level" (verified via address balance check)

#### Implementation Architecture
```
┌─────────────────────────────────────────────────┐
│                  Game Client                     │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐ │
│  │ In-Game  │  │ Tip QR   │  │ Wallet Viewer │ │
│  │ WOW      │  │ (all     │  │ (read-only,   │ │
│  │ (fake)   │  │ platforms)│  │ all platforms)│ │
│  └──────────┘  └──────────┘  └───────────────┘ │
│                      │                           │
│  ┌──────────────────────────────────────────┐   │
│  │ Web-Only: Wallet Connect, P2E, Mining    │   │
│  │ (itch.io / wownero.org builds only)      │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
  ┌─────────────┐    ┌──────────────┐
  │ Such.Software│    │  Wownero     │
  │ Leaderboard  │    │  Blockchain  │
  │ API          │    │  (external)  │
  └─────────────┘    └──────────────┘
```

#### Key Principle
**In-game WOW is always fake/virtual.** It's an in-game currency that happens to be crypto-themed. Real Wownero interaction only happens externally (tip jar, wallet viewer) or on the unrestricted web build. This keeps Apple and Google happy while still letting the crypto community engage with real WOW through the web version.

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
- [ ] HTML5 build — IndexedDB save/load, HTTPRequest leaderboard, touch emulation
- [ ] Web ads (AdSense) display correctly in HTML5 build

### Known Bugs 🐛
- [x] ~~Level 4 "Next Level" button does nothing~~ — fixed, routes to UpgradeShop
- [x] ~~Completing Level 4 saves level=5~~ — fixed, caps at MAX_LEVEL
- [x] ~~Asteroids accelerate forever~~ — speed cap + despawn
- [x] ~~`eartharea.gd` prints to console every frame~~ — removed
- [x] ~~Gamma ray `get_collider()` has no null check~~ — null guard added
- [x] ~~Venus and Io don't orbit~~ — orbital scripts added
- [x] ~~`MoonLaunch.aab` and `.apk.idsig` still in repo~~ — deleted + gitignored
- [x] ~~Dead root scripts (`QuitButton.gd`, `helpbuttons.gd`)~~ — removed, unreferenced stubs
- [x] ~~`[dotnet]` section in project.godot~~ — removed, no C# code exists

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
