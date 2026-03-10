# Wownero Moon Launch — TODO

> Crypto-themed space landing game. Land your rocket on celestial bodies, dodge hazards, collect crypto, upgrade your ship.

---

## � Phase 1: Foundation & Web Export

- [x] **Remove `[dotnet]` config** — deleted the `[dotnet]` section from project.godot. No C# code exists; this is pure GDScript. Removes Mono dependency for clean web/mobile exports.
- [x] **Delete dead scripts** — removed `QuitButton.gd` + `.uid` and `helpbuttons.gd` + `.uid` from project root. Neither was referenced by any scene or script.
- [x] **Create export presets** — added `export_presets.cfg` with Web, Android, iOS, Windows, macOS, Linux targets. Export paths set to `builds/<platform>/`. Android package: `org.wownero.moonlaunch`.
- [ ] **Verify web build** — export HTML5, test in Chrome/Firefox/Safari: confirm save/load (IndexedDB), leaderboard API (HTTPRequest), touch input emulation all work
- [x] **Secure HMAC secret** — ScoreClient.gd `_get_hmac_secret()` returns production hex secret. All score submissions and cloud save uploads are HMAC-SHA256 signed with X-Timestamp + X-Signature headers. Server verifies within 5-minute window.
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
- [x] **WOW (Wownero)** — primary currency, common drop, converted to Moonrocks (🪨) on pickup
- [x] **XMR (Monero)** — rare, worth 10x, purple ring glow
- [x] **BTC (Bitcoin)** — very rare, worth 50x, golden glow
- [x] **DOGE** — uncommon, worth 5x, such wow
- [x] **Floating crypto sprites** — spin slowly, bob up/down, self-drawing (CryptoPickup.gd)
- [x] **Collection animation** — fly toward ship on pickup, +amount popup text
- [x] **Wallet HUD** — show current Moonrocks balance during gameplay (WalletHUD.gd)
- [x] **Crypto spawner** — drop-in CryptoSpawner.gd with weighted random types + min spacing

### Scoring & Progression
- [x] **Star rating** — 1-3 stars per level based on time + fuel remaining + crypto collected
- [x] **Best time per level** — save and display on level select
- [x] **Total crypto wallet** — persisted across sessions, shown in shop
- [ ] **Achievements** — "First Landing", "Speed Demon" (under 10s), "Pacifist" (no deaths), "Crypto Whale" (1000 Moonrocks), etc.
- [x] **Leaderboard** — backend API at api.such.software, per-level rankings, auto-submit on victory

### Cloud Save
- [x] **CloudSave autoload** — CloudSave.gd HTTP client for PUT/GET `/v1/moonlaunch/save`. HMAC-signed uploads (same secret as ScoreClient). Fire-and-forget upload on every save_game(). Download on demand via restore_from_cloud().
- [x] **Backend cloud save endpoints** — PUT `/save` (HMAC-verified, JSONB upsert, 64KB limit) and GET `/save` (device_uuid lookup). moonlaunch_saves table with device_uuid PK, nickname, save_data JSONB, platform, timestamps.
- [x] **Cloud restore logic** — globalvar.restore_from_cloud() downloads cloud save and overwrites local state only if cloud has more progress (higher level or wallet). Extracted _apply_save_data() shared by load_game() and cloud restore.
- [ ] **Restore UI** — "Restore from Cloud" button on main menu or settings screen. Shows confirmation before overwriting local progress.

---

## 💰 Phase 2: Monetization

### Ads (Primary Revenue)
- [x] **AdManager autoload** — platform-aware ad abstraction layer. Desktop always ad-free (itch.io sales). Web uses AdSense via JavaScriptBridge. Mobile has AdMob plugin stubs. IAP ad-removal persisted to user://adstate.json.
- [x] **Interstitial ads** — shown between Victory and Upgrade Shop. Also every 3rd retry on DeathScreen. No-op if ad-free.
- [x] **Rewarded video ads** — "Watch ad for 50 Moonrocks" button on DeathScreen and in Upgrade Shop. Opt-in only. Grants AdManager.REWARDED_AD_MOONROCKS crypto.
- [x] **Banner ad** — shown on Menu and Upgrade Shop screens. Hidden during gameplay (rocket.gd _ready).
- [x] **Web ad integration** — Google AdSense via JavaScriptBridge for HTML5 builds. JS shell functions: showInterstitialAd, showRewardedAd, showBannerAd, hideBannerAd.

### Cosmetic IAP
- [x] **Ship skins** — 8 skins (retro, stealth, gold, alien, wownero, monero, bitcoin, litecoin) at art/ship/skins/. Purchasable with Moonrocks in Upgrade Shop skin gallery. Texture swap in rocket.gd _ready(). Premium skins planned (different shapes).
- [x] **Skin storage** — selected_skin + owned_skins persisted in savegame.json. globalvar SKIN_CATALOG maps skin_id to path/price/label.

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
- [x] **DeathScreen overlay** — replaces old "3s timer → menu" death flow. Animated panel with Retry Level (free), Watch Ad for Moonrocks (if ads supported), Quit to Menu. Interstitial every 3rd retry.
- [x] **Celestial waypoints (Levels 5+)** — rocket.gd detects entering a waypoint planet's gravity well (Area2D radius check) and saves checkpoint (position, velocity, fuel) to globalvar. Waypoints are all "targets" group bodies except the last (final target). Each waypoint visited only once per run.
- [ ] **Waypoint as gameplay** — waypoint planets double as gravity slingshot opportunities and refueling stations. Fuel pickups clustered near waypoints.
- [x] **Checkpoint retry (Levels 5+)** — DeathScreen shows green "Retry from [Planet]" button when checkpoint exists. Reloads level with globalvar.restore_checkpoint flag; rocket.gd defers position/velocity/fuel restore via _apply_checkpoint().
- [x] **Difficulty settings** — Easy/Normal/Hard toggle on main menu. Easy: spawn intervals ×1.4, enemy speed ×0.8, fuel drain ×0.8, starting fuel ×1.2. Hard: spawn intervals ×0.7, enemy speed ×1.2, fuel drain ×1.3, starting fuel ×0.9. Persisted in savegame. Cycling button in main menu with color-coded styling (green/gold/red).

### Visual Feedback
- [x] **Screen shake** — Camera2D offset randomized on death (intensity=12, decay over frames). Added to rocket.gd.
- [x] **Particle exhaust trail** — GPUParticles2D "ExhaustTrail" in Rocket.tscn (30 particles, 1.5s lifetime, world-space trail).
- [x] **Low fuel warning** — fuel bar flashes red at <20% (4Hz toggle), dark red background, pulsing border, "LOW FUEL" text.
- [x] **Landing proximity beeps** — `tone1.ogg` from Kenney Digital Audio, pitch scales 0.8→2.0 and volume -18→-3 dB as rocket approaches target (250px range), interval shrinks 0.6s→0.1s.
- [x] **Better explosion** — GPUParticles2D one-shot burst (40 particles, 0.8s, sphere emission, 80-200 velocity, fire gradient). Layered SFX: original explosion.wav + `explosionCrunch_000.ogg` + `lowFrequency_explosion_000.ogg` from Kenney Sci-Fi Sounds.
- [x] **Gravity field visualization** — translucent blue arc rings on all planets via `_draw()`, auto-detects gravity radius from Area2D child.

### Game Feel
- [x] **Slow-motion landing** — within 80px of target at speed < 80 → Engine.time_scale = 0.7. Reverts on death/land/menu. Added to rocket.gd.
- [x] **Crypto pickup VFX** — sparkle burst of 8-12 colored dots radiating outward on collection, type-colored with white accents, tween fade+shrink.
- [x] **UI animations** — Victory screen: score count-up (time rolls 0→final with ease-out, fuel/crypto fade in staggered, stars pop in one-by-one with elastic tween, NEW BEST slam-in). Victory buttons slide in from below with stagger. DeathScreen buttons stagger slide-in from right.
- [x] **Haptic feedback** — `Input.vibrate_handheld()` on death (200ms), landing (100ms), crypto pickup (30ms), cannon fire (20ms), wormhole teleport (80ms), black hole death (300ms). Zero-cost, mobile-only.

---

## 🗺️ Phase 3: Content Expansion

### Existing Levels (polish)
- [x] **Level 1 (Moon)** — tutorial prompts overlay ("Press UP to thrust!"). First-time only, saved to prefs.
- [ ] **Level 2 (Mars)** — rebalance Martians (see Phase 4), add crypto pickups as introduction
- [ ] **Level 3 (Venus)** — gamma rays + crypto scattered in the danger zone
- [ ] **Level 4 (Io)** — gamma rays + asteroids + crypto, the current "final" level

### New Levels (5–10)
- [x] **Level 5 — Jupiter** — 2x gravity (80.0), Moon as waypoint. 8 Martians (speed 35–50), gamma rays + asteroids. spacecadet_bgm.ogg.
- [x] **Level 6 — Saturn** — gravity 50.0, Moon + Jupiter as waypoints. 10 Martians (speed 38–55), tighter hazard timing. infinitedescent_bgm.ogg.
- [x] **Level 7 — Neptune** — Earth → Moon → Saturn waypoints → Neptune target. Gravity 65.0, 10 Martians (speed 40–55). ancientbgm.ogg.
- [x] **Level 8 — Pluto** — Earth → Moon → Neptune waypoints → Pluto target. Tiny target (0.06x scale, 25px collision, gravity 15). 10 Martians (speed 42–58). spacecadet_bgm.ogg.
- [x] **Level 9 — Asteroid Mining** — Earth → Moon → Jupiter waypoints → drifting AsteroidCluster target (7–10 randomly placed/rotated/shaded rocks). 12 Martians (speed 45–60). infinitedescent_bgm.ogg.
- [x] **Level 10 — Space Station** — Earth → Moon → Saturn → Neptune waypoints → rotating SpaceStation target. 12 Martians (speed 48–62), fastest hazard timing. ancientbgm.ogg.

### Endgame Content
- [ ] **Procedural endless mode** — unlocked after Level 10. Random planets, random hazards, difficulty scales with run length. Leaderboard for furthest distance / most landings.
- [ ] **Boss Level — Martian Mothership** — large ship spawning smaller Martians. Must dodge and land on its pad.

### Level Features
- [x] **Wormholes/portals** — Wormhole.gd/tscn drop-in component. Paired Area2D portals teleport rocket between points. Swirling animated ring visual, cooldown prevents re-teleport, haptic pulse on use. **Placed in:** Level 5 (shortcut mid-field), Level 8 (skip nebula), Level 10 (escape route).
- [ ] **Gravity slingshot** — use a planet's gravity to accelerate toward distant targets
- [ ] **Moving asteroids as obstacles** — pre-placed orbiting bodies
- [x] **Solar wind** — SolarWind.gd/tscn drop-in zone. Applies constant directional force (configurable direction + strength). Animated wind streak lines show force direction. **Placed in:** Level 6 (crosswind near Saturn), Level 9 (pushes toward black hole), Level 10 (approach deflection).
- [x] **Nebula zones** — Nebula.gd/tscn drop-in zone. Drains rocket fuel while inside, applies gentle speed damping. Soft pulsing gas blob visual. **Placed in:** Level 7 (deep space fog), Level 8 (between Neptune and Pluto), Level 10 (thick interference).
- [x] **Black hole** — BlackHole.gd/tscn drop-in hazard. Extreme gravity pull (inverse-distance), instant death at event horizon. Animated accretion disk rings + dark center. **Placed in:** Level 9 (solar wind pushes toward it), Level 10 (early obstacle).


### 🎨 Visual & Audio

### Visual Polish
- [x] **Planet atmospheres** — colored atmosphere glow rings on all 9 planets. Each planet has unique color (Earth=blue, Mars=rusty red, Venus=yellow-orange, Jupiter=amber, Saturn=gold, Neptune=icy blue, Pluto=pale frost, Moon=silver, Io=sulfur yellow). Auto-detects body collision radius.
- [ ] **Parallax depth** — more background layers for depth perception
- [x] **Landing animation** — dust particle burst on successful landing (24 particles, warm tan, radial burst from feet). GPUParticles2D spawned programmatically in flagplanted().
- [ ] **Ship skins** — more skins: achievement-unlocked (gold for all 3★, skull for 50 deaths), premium IAP skins with different shapes
- [ ] **Starfield shader** — replace static background with animated procedural stars

### Audio
- [x] **Per-level BGM** — Levels 1–4: ancientbgm.ogg, Level 5: spacecadet_bgm.ogg, Level 6: infinitedescent_bgm.ogg
- [ ] **More BGM tracks** — source/compose additional looping tracks for Levels 7–10 (currently reusing existing 3 tracks)
- [x] **Crypto pickup sound** — procedural coin ding using proximity_beep.ogg pitched up. Pitch varies by crypto type: WOW=high ding, DOGE=mid, XMR=lower, BTC=deep rich tone. Light haptic on pickup.
- [x] **Landing countdown beeps** — accelerating beep ticks during 3s landing timer. Pitch scales 1.2→2.5 and volume -12→-2 dB as countdown progresses. Interval shrinks 0.5s→0.12s.
- [ ] **Martian chase music** — intensity increases when being pursued
- [ ] **Victory fanfare** — upgrade from current single WAV


### 🔫 Combat 

- [x] **Forward cannon** — Bullet.gd/tscn projectile + cannon system in rocket.gd. Auto-aim finds nearest CharacterBody2D enemy within 300px/70° cone. Hold-to-fire with cooldown. Mobile: FireButton.gd (red crosshair circle) above joystick, only shown when cannon purchased. Desktop: spacebar. Haptic on fire.
- [ ] **Missile launcher** — homing missiles, limited ammo (buyable with crypto)
- [ ] **Laser beam** — continuous beam weapon, drains fuel to fire
- [ ] **Mine layer** — drop mines behind you to stop pursuing martians
- [ ] **EMP pulse** — disable all martians in radius for 5 seconds
- [x] **Weapons as upgrades** — cannon upgrade in globalvar (10th upgrade, base cost 150 Moonrocks, 5 levels). Faster fire rate per level (0.4s→0.15s). UpgradeShop shows cannon with 🔫 icon and fiery orange accent.


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
