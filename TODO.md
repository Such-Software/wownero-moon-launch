# Wownero Moon Launch — TODO

> Crypto-themed space landing game. Land your rocket on celestial bodies, dodge hazards, collect crypto, upgrade your ship.

---

## � Phase 1: Foundation & Web Export

- [x] **Remove `[dotnet]` config** — deleted the `[dotnet]` section from project.godot. No C# code exists; this is pure GDScript. Removes Mono dependency for clean web/mobile exports.
- [x] **Delete dead scripts** — removed `QuitButton.gd` + `.uid` and `helpbuttons.gd` + `.uid` from project root. Neither was referenced by any scene or script.
- [x] **Create export presets** — added `export_presets.cfg` with Web, Android, iOS, Windows, macOS, Linux targets. Export paths set to `builds/<platform>/`. Android package: `com.suchsoftware.wowneromoonlaunch`.
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
- [x] **Level select screen** — player-facing \"Levels\" button on Menu with star ratings, best times, lock icons. Debug shortcuts: D key on menu, 3-finger hold on mobile. Reads from globalvar.LEVEL_SCENES.
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
- [x] **Achievements** — 13 achievements on both platforms. Android: Google Play Games Services via PlayGamesManager.gd (GodotPlayGameServices v3.2.0 plugin). iOS: Game Center via GameCenterManager.gd (built-in singleton). Both autoloaded, both no-op on wrong platform. Milestones: First Landing through Mothership Docked. Mastery: Champion (all 3★), Speed Demon. Endurance: Endless Survivor, Grim Reaper (50 deaths), Moonrock Hoarder (5000 earned). Collection: Skin Collector (5 skins), Fully Upgraded. See DEPLOY.md §10 for PGS setup.
- [x] **Leaderboard** — backend API at api.such.software, per-level rankings, auto-submit on victory. Leaderboard viewer popup on Menu (fetches from backend, shows top scores in RichTextLabel table). Cross-platform (not PGS).
- [x] **Player-facing level select** — "Levels" button on Menu opens scrollable panel with star ratings, best times, and lock icons. Available to all players (not just debug). Debug D key and 3-finger hold still work as shortcuts.

### Cloud Save
- [x] **CloudSave autoload** — CloudSave.gd HTTP client for PUT/GET `/v1/moonlaunch/save`. HMAC-signed uploads (same secret as ScoreClient). Fire-and-forget upload on every save_game(). Download on demand via restore_from_cloud().
- [x] **Backend cloud save endpoints** — PUT `/save` (HMAC-verified, JSONB upsert, 64KB limit) and GET `/save` (device_uuid lookup). moonlaunch_saves table with device_uuid PK, nickname, save_data JSONB, platform, timestamps.
- [x] **Cloud restore logic** — globalvar.restore_from_cloud() downloads cloud save and overwrites local state only if cloud has more progress (higher level or wallet). Extracted _apply_save_data() shared by load_game() and cloud restore.
- [x] **Restore UI** — "Restore from Cloud" button on main menu bottom-right. AcceptDialog confirmation before downloading. Cloud restore keeps better save (won't overwrite if local is ahead).

---

## 💰 Phase 2: Monetization

### Ads (Primary Revenue)
- [x] **AdManager autoload** — platform-aware ad abstraction layer. Desktop always ad-free (itch.io sales). Web uses AdSense via JavaScriptBridge. Mobile has AdMob plugin stubs. IAP ad-removal persisted to user://adstate.json.
- [x] **Interstitial ads** — shown between Victory and Upgrade Shop. Also every 3rd retry on DeathScreen. No-op if ad-free.
- [x] **Rewarded video ads** — "Watch ad for 50 Moonrocks" button on DeathScreen and in Upgrade Shop. Opt-in only. Grants AdManager.REWARDED_AD_MOONROCKS crypto.
- [x] **Banner ad** — shown on Menu and Upgrade Shop screens. Hidden during gameplay (rocket.gd _ready).
- [x] **Web ad integration** — Google AdSense via JavaScriptBridge for HTML5 builds. JS shell functions: showInterstitialAd, showRewardedAd, showBannerAd, hideBannerAd.

### Cosmetic IAP
- [x] **Ship skins** — 8 purchasable skins (retro, stealth, gold, alien, wownero, monero, bitcoin, litecoin) + 4 achievement skins (champion, skull, crystalbeetle, steamboat) at art/ship/skins/. Purchasable with Moonrocks in Upgrade Shop skin gallery. Texture swap in rocket.gd _ready().
- [x] **Skin storage** — selected_skin + owned_skins persisted in savegame.json. globalvar SKIN_CATALOG maps skin_id to path/price/label.
- [x] **Remove Ads button** — "🚫 Remove Ads" button in Upgrade Shop. Calls AdManager.remove_ads(), persists to user://adstate.json, hides all ad UI permanently.
- [x] **Pilot Stats section** — "📊 PILOT STATS" panel in Upgrade Shop showing deaths, lifetime crypto, levels completed, best wave, skins owned.

### Premium Content
- [x] **Level pack unlock** — Levels 1-4 free. Levels 5+ require earning 2000 lifetime Moonrocks (tracked via total_crypto_earned). Lock popup with progress bar shown on Play/level-select. Level select shows lock icons. globalvar.is_level_unlocked() + levels_unlocked flag for future IAP.

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
- [x] **Waypoint as gameplay** — waypoint planets are refueling stations (10% max_fuel bonus on first visit with "+N FUEL — Planet Station" popup). Gravity slingshot detection tracks entry/exit speed from any planet's gravity well; net gain ≥40 px/s triggers "SLINGSHOT! +N" gold label, directional star-particle burst, haptic pulse, and ascending ding. FuelSpawners already clustered near waypoints in levels 5-10.
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

### UI & Documentation
- [x] **Multi-page Help screen** — 12 navigable pages covering all mechanics: Controls, Landing, Fuel, Crypto & Moonrocks, Upgrades, Weapons, Hazards & Enemies, Waypoints & Slingshots, Difficulty, Star Ratings, Leaderboard & Cloud Save, Ship Skins. RichTextLabel with BBCode formatting. Keyboard arrows, touch swipe, and Prev/Next buttons for navigation. Page counter indicator.
- [x] **Death tracking** — `total_deaths` counter in globalvar, incremented in rocket.gd death(), persisted to save. Used for skull achievement skin.
- [x] **Lifetime crypto tracking** — `total_crypto_earned` in globalvar (never decreases). Tracks cumulative Moonrocks for level pack unlock progress.

---

## 🗺️ Phase 3: Content Expansion

### Existing Levels (polish)
- [x] **Level 1 (Moon)** — tutorial prompts overlay ("Press UP to thrust!"). First-time only, saved to prefs.
- [x] **Level 2 (Mars)** — 2 Martians (speed 25), CryptoSpawner (4 pickups, r=300), FuelSpawner (1 canister). Smooth intro to enemies and collectibles.
- [x] **Level 3 (Venus)** — 4 Martians (speed 32-35), gamma ray timer (2-5s), 2 CryptoSpawners (6 common + 3 rare XMR/BTC), 1 FuelSpawner. Fixed BGM to non-positional AudioStreamPlayer.
- [x] **Level 4 (Io)** — 6 Martians (speed 40-45), gamma rays + asteroid timer (4-7s), 2 CryptoSpawners (5 + 3 rare), 2 FuelSpawners. Fixed BGM to non-positional AudioStreamPlayer.

### New Levels (5–10)
- [x] **Level 5 — Jupiter** — 2x gravity (80.0), Moon as waypoint. 8 Martians (speed 35–50), gamma rays + asteroids. spacecadet_bgm.ogg.
- [x] **Level 6 — Saturn** — gravity 50.0, Moon + Jupiter as waypoints. 10 Martians (speed 38–55), tighter hazard timing. infinitedescent_bgm.ogg.
- [x] **Level 7 — Neptune** — Earth → Moon → Saturn waypoints → Neptune target. Gravity 65.0, 10 Martians (speed 40–55). ancientbgm.ogg.
- [x] **Level 8 — Pluto** — Earth → Moon → Neptune waypoints → Pluto target. Tiny target (0.06x scale, 25px collision, gravity 15). 10 Martians (speed 42–58). spacecadet_bgm.ogg.
- [x] **Level 9 — Asteroid Mining** — Earth → Moon → Jupiter waypoints → drifting AsteroidCluster target (7–10 randomly placed/rotated/shaded rocks). 12 Martians (speed 45–60). infinitedescent_bgm.ogg.
- [x] **Level 10 — Space Station** — Earth → Moon → Saturn → Neptune waypoints → rotating SpaceStation target. 12 Martians (speed 48–62), fastest hazard timing. ancientbgm.ogg.

### Endgame Content
- [x] **Boss Level — Martian Mothership (Level 11)** — Mothership.gd/tscn: large 4x-scaled red ship that patrols (sine wave oscillation), spawns Martians periodically (speed 52-68), and fires gamma rays aimed at rocket. Landing pad on nose (green ColorRect in "targets" group). Earth → Moon → Jupiter waypoints. 12 pre-placed Martians (speed 50-65), BlackHole + Nebula hazards, 3 CryptoSpawners, 3 FuelSpawners. spacecadet_bgm.ogg.
- [x] **Procedural endless mode (Level 12)** — EndlessMode.gd/tscn: wave-based infinite mode. Each wave procedurally generates a random target planet at scaling distance (800+wave×200), optional waypoint (wave 3+), scaling Martian count (2+wave×2, cap 24, speed 30+wave×4 cap 80), orbiting asteroids around waypoints. Gamma rays start wave 2, asteroids wave 3, intervals tighten each wave. Crypto/fuel spawners scale with wave. Landing advances wave and reloads level. Best wave persisted in save. infinitedescent_bgm.ogg. Wave number shown with elastic pop-in label.

### Level Features
- [x] **Wormholes/portals** — Wormhole.gd/tscn drop-in component. Paired Area2D portals teleport rocket between points. Swirling animated ring visual, cooldown prevents re-teleport, haptic pulse on use. **Placed in:** Level 5 (shortcut mid-field), Level 8 (skip nebula), Level 10 (escape route).
- [x] **Gravity slingshot** — detected in rocket.gd `_check_slingshot()`. Tracks all StaticBody2D planets with Area2D gravity. Records entry speed when entering gravity radius, compares to exit speed. ≥40 px/s gain → gold "SLINGSHOT!" label, star particle burst in travel direction, haptic 50ms, ascending beep. Works on all planets in all levels.
- [x] **Moving asteroids as obstacles** — OrbitingAsteroid.gd/tscn drop-in component. CharacterBody2D orbits a planet node at configurable radius/speed with random start angle, spin direction, scale variation (0.7-1.2x), random texture. Spawned programmatically in levels 5-10 via `_spawn_orbiting()` helper. Count/speed scales with difficulty (L5: 5 total, L10: 16 total). Collision layer 4 = lethal to rocket via ShipArea overlap.
- [x] **Solar wind** — SolarWind.gd/tscn drop-in zone. Applies constant directional force (configurable direction + strength). Animated wind streak lines show force direction. **Placed in:** Level 6 (crosswind near Saturn), Level 9 (pushes toward black hole), Level 10 (approach deflection).
- [x] **Nebula zones** — Nebula.gd/tscn drop-in zone. Drains rocket fuel while inside, applies gentle speed damping. Soft pulsing gas blob visual. **Placed in:** Level 7 (deep space fog), Level 8 (between Neptune and Pluto), Level 10 (thick interference).
- [x] **Black hole** — BlackHole.gd/tscn drop-in hazard. Extreme gravity pull (inverse-distance), instant death at event horizon. Animated accretion disk rings + dark center. **Placed in:** Level 9 (solar wind pushes toward it), Level 10 (early obstacle).


### 🎨 Visual & Audio

### Visual Polish
- [x] **Planet atmospheres** — colored atmosphere glow rings on all 9 planets. Each planet has unique color (Earth=blue, Mars=rusty red, Venus=yellow-orange, Jupiter=amber, Saturn=gold, Neptune=icy blue, Pluto=pale frost, Moon=silver, Io=sulfur yellow). Auto-detects body collision radius.
- [x] **Parallax depth** — 4-layer parallax system: NebulaLayer (motion_scale 0.03, purple dust particles), deep stars (0.05), mid stars (0.2), MidgroundLayer (0.4, larger/brighter warm-tinted stars)
- [x] **Landing animation** — dust particle burst on successful landing (24 particles, warm tan, radial burst from feet). GPUParticles2D spawned programmatically in flagplanted().
- [x] **Ship skins** — 13 skins total: 1 default + 8 purchasable (retro, stealth, gold, alien, wownero, monero, bitcoin, litecoin) + 4 achievement skins (Champion for all 3★, Skull for 50 deaths, Crystal Beetle for completing all 11 levels, Steamboat for wave 10 endless). Achievement skins show 🔒 locked status in shop gallery, auto-unlock and become selectable. Death counter + lifetime crypto tracked in save.
- [x] **Starfield shader** — procedural animated starfield.gdshader replaces static JPEG. 3 star layers with hash-based placement, per-star twinkle animation, subtle nebula noise. Applied via ShaderMaterial on ColorRect in ParallaxBackground.tscn.

### Audio
- [x] **Per-level BGM** — Levels 1–4: ancientbgm.ogg, Level 5: spacecadet_bgm.ogg, Level 6: infinitedescent_bgm.ogg
- [x] **More BGM tracks** — 4 new "Star Overdrive" tracks wired in: Level 7=staroverdrive_1, Level 8=staroverdrive_2, Level 10=staroverdrive_3, Level 11=staroverdrive_4. Every level now has unique BGM.
- [x] **Crypto pickup sound** — procedural coin ding using proximity_beep.ogg pitched up. Pitch varies by crypto type: WOW=high ding, DOGE=mid, XMR=lower, BTC=deep rich tone. Light haptic on pickup.
- [x] **Landing countdown beeps** — accelerating beep ticks during 3s landing timer. Pitch scales 1.2→2.5 and volume -12→-2 dB as countdown progresses. Interval shrinks 0.5s→0.12s.
- [ ] **Martian chase music** — intensity increases when being pursued
- [ ] **Victory fanfare** — upgrade from current single WAV


### 🔫 Combat 

- [x] **Forward cannon** — Bullet.gd/tscn projectile + cannon system in rocket.gd. Auto-aim finds nearest CharacterBody2D enemy within 300px/70° cone. Hold-to-fire with cooldown. Mobile: FireButton.gd (red crosshair circle) above joystick, only shown when cannon purchased. Desktop: spacebar. Haptic on fire.
- [x] **Missile launcher** — Missile.gd/tscn homing projectile. Locks onto nearest CharacterBody2D within 500px (any direction), steers with 3.5 rad/s turn rate. Ammo = 2 × upgrade level per run. Desktop: M key. Mobile: WeaponButton.gd (red-orange, "M" icon). Explosion particles on impact/expiry. Base cost 200 Moonrocks.
- [x] **Laser beam** — LaserBeam.gd continuous ray weapon. Raycast forward, damages enemies on contact (0.15s tick). Drains 18 fuel/sec while active. Range = 200 + 40×level px. Desktop: L key (hold). Mobile: WeaponButton.gd (cyan, "L" icon). Procedural beam draw with glow + impact point. Base cost 250 Moonrocks.
- [ ] **Mine layer** — drop mines behind you to stop pursuing martians
- [x] **EMP pulse** — EMPPulse.gd area-of-effect weapon. Destroys all CharacterBody2D enemies within radius (150 + 30×level px). Charges = 1 per upgrade level per run. Desktop: E key. Mobile: WeaponButton.gd (blue, "E" icon). Expanding ring visual with electric sparks. Screen shake + haptic. Base cost 300 Moonrocks.
- [x] **Weapons as upgrades** — All 4 weapons (cannon, missile, laser, EMP) in globalvar upgrades dict (5 levels each). UpgradeShop auto-generates cards with icons (🔫/🚀/⚡/💥) and accent colors.


### 🌐 3D / First Person 

- [x] **Warp tunnel transition** — WarpTunnel.gd/tscn: 3D hyperspace tunnel plays when entering any level. 300 streaming star meshes accelerate from 5→120 speed, stretch into lines, blue-shift. Camera FOV widens 75→95°. Cockpit.png overlaid as CanvasLayer frame. Typewriter "WARPING TO [LEVEL]..." text. Speed lines procedural overlay. White flash exit → loads target level. WarpTransition.gd autoload with `warp_to(scene)` helper. Wired into Menu Play, level-select debug picker, and UpgradeShop Continue.
- [x] **3D landing mode** — switch to 3D view for final approach/landing sequence. LandingMode.gd: half-res SubViewport (512×300, own_world_3d), SphereMesh ground with simplex noise shader, Sprite3D rocket, chase camera. HUD: ALT/SPD readouts, tilt indicator with directional arrows, flashing LANDING text. Activates per-planet based on collision radius + 60px margin. Tilt measured relative to target direction; >35° = crash, >18° = warning. Difficulty scales crash/landing speed thresholds.
- [ ] **3D landing surface polish** — make planet/moon ground in landing mode more visually interesting without hurting performance (craters, terrain color variation, height displacement, per-planet theming)
- [ ] **First-person cockpit** — HUD overlay with instruments, see out the window
- [ ] **3D level prototype** — one level fully in 3D as proof of concept
- [ ] **VR support** — Godot 4 has OpenXR, landing a rocket in VR would be insane

---

## 📱 Phase 5: Platform & Distribution

- [ ] **Web deployment** — HTML5 build hosted on itch.io (pay-what-you-want + ad rev share) and wownero.org
- [ ] **Android export** — signed APK/AAB, Google Play + F-Droid
- [ ] **iOS export** — Xcode build, TestFlight distribution
- [ ] **Desktop builds** — Windows .exe, macOS .dmg, Linux .AppImage via itch.io + GitHub Releases
- [x] **Landscape lock** — orientation=4 (SCREEN_SENSOR_LANDSCAPE) set in project.godot and export_presets.cfg
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
- [ ] Victory → Next Level flow for all 11 story levels + endless mode
- [ ] Save persistence across app restarts
- [ ] EarthArea gravity — is it working or is it a dead scene?
- [ ] Edge case: rocket drifts infinitely far from all bodies
- [ ] Performance: confetti labels on victory screen
- [ ] HTML5 build — IndexedDB save/load, HTTPRequest leaderboard, touch emulation
- [ ] Web ads (AdSense) display correctly in HTML5 build
- [ ] PGS achievements — unlock/increment on real Android device
- [ ] PGS sign-in — auto-sign-in on launch, Achievements button visible

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

1. ~~Debug level picker~~ ✅
2. ~~Fix existing bugs~~ ✅
3. ~~Fuel system + HUD~~ ✅
4. ~~Crypto collectibles~~ ✅
5. ~~Upgrade shop~~ ✅
6. ~~Star rating + best times~~ ✅
7. ~~11 levels + endless mode~~ ✅
8. ~~Combat system~~ ✅
9. ~~Visual/audio polish~~ ✅
10. ~~Google Play Games Services~~ ✅ — PGS published, real IDs in code, Game Center configured for iOS
11. ~~AdMob production IDs~~ ✅ — 6 ad units + 2 App IDs configured
12. **Mobile deployment** — Android/iOS real device testing, store uploads *(release keystore ✅, Gradle build ✅, PGS OAuth credentials ✅)*
12. **Web build** — itch.io / wownero.org deployment
13. **iOS export** — Xcode build, TestFlight
14. 3D prototype (experimental, future phase)

---

## 🧪 Testing

### Automated Tests (GdUnit4)
- [x] **Install GdUnit4** — `addons/gdUnit4/` (v6.1.1), enabled in project.godot
- [x] **globalvar.gd unit tests** — 121 tests covering:
  - Difficulty multipliers (spawn interval, enemy speed, fuel drain, starting fuel × 3 difficulties)
  - Level unlock gate (free levels 1-4, locked 5+, flag unlock, grind unlock at 2000)
  - Upgrade stats (thrust, fuel, drain floor, crash/landing speed with difficulty, shield, torque, reverse thrust, magnet)
  - Upgrade costs & purchase (cost scaling, wallet deduction, max level rejection, sequential buys)
  - Crypto accounting (wallet, level crypto, total earned, total never decreases after spend)
  - Skin purchase & selection (buy, already owned, insufficient funds, nonexistent, select owned/unowned)
  - Star rating (time thresholds, fuel bonus, cap at 3, exact boundaries, best time/stars tracking)
  - Achievement skins (champion at all 3-stars, skull at 50 deaths, no duplicates)
  - Nickname generation (format, valid prefix+suffix)
  - Level routing (scene lookup, endless mode flag, fallback, has_next_level)
  - Per-run reset & checkpoint
  - Save/load roundtrip (all keys present, data integrity, missing keys default, default skin always present, new upgrades stay zero)
  - UUID format & uniqueness, platform string
- [x] **PlayGamesManager.gd unit tests** — 15 tests covering:
  - Availability check (non-Android returns false)
  - No-op safety for all public methods (unlock, increment, set_steps, show_achievements)
  - No-op safety for all game hooks (on_level_completed, on_death, on_endless_wave, on_crypto_earned, on_skin_owned, on_upgrade_maxed)
  - Achievement ID catalog (all 13 keys present, no empty IDs)
- **Total: 144 tests** across 2 test files
- **Run command:**
  ```
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
    --add "res://test/" --ignoreHeadlessMode
  ```

### Manual Testing Checklist
- [ ] **Gameplay — Core**
  - [ ] Launch Level 1, thrust to Moon, land gently → Victory screen with stars
  - [ ] Crash at high speed → Death screen → Retry works
  - [ ] Run out of fuel → drift without thrust, crash
  - [ ] Land at >35° tilt → rollover death
  - [ ] Collect crypto pickups → wallet increases in HUD
  - [ ] Collect fuel canisters → fuel bar increases
  - [ ] Gravity slingshot around a planet → "SLINGSHOT!" popup
  - [ ] Gamma ray fires → blocked by planet bodies, kills rocket
  - [ ] Waypoint checkpoint → die after checkpoint → respawn at waypoint
- [ ] **Progression**
  - [ ] Complete Level 1 → nowlevel advances, level 2 appears
  - [ ] Stars computed correctly (fast time = 3★, slow = 1★, fuel bonus +1★)
  - [ ] Buy upgrade → wallet deducted, upgrade level visible in shop
  - [ ] Buy skin → wallet deducted, skin applied to rocket in-game
  - [ ] Level 5+ locked without 2000 earned crypto or unlock flag
  - [ ] Debug: M key = +500 moonrocks (debug builds only), U key = unlock all, D key = level select
- [ ] **Save/Load**
  - [ ] Close and reopen game → progress restored (wallet, upgrades, stars, skins)
  - [ ] Cloud save upload succeeds silently
  - [ ] Cloud restore button downloads and applies if cloud has more progress
- [ ] **Menu & UI**
  - [ ] Title screen: planets drift in after 5-7s, ships fly across, explosions on collision
  - [ ] Earth/Moon render above background ships/planets
  - [ ] Nickname reroll generates new name, edit with >20 chars truncates
  - [ ] Difficulty cycles Easy → Normal → Hard → Easy, label color changes
  - [ ] Help screen: 12 pages, Next/Prev bounds, swipe on touch
- [ ] **Mobile (when applicable)**
  - [ ] Touch controls (joystick + buttons) functional
  - [ ] Haptic feedback on death, landing, slingshot, pickup
  - [ ] Banner ad on menu/shop (once real SDK integrated)

---

## 📺 Ad Integration

### Architecture
- **Desktop** (macOS/Win/Linux): Always ad-free (premium builds)
- **Web**: AdSense via custom HTML shell (`web/custom_shell.html`) + JS bridge
- **Mobile** (Android/iOS): AdMob via poing-studios/godot-admob-plugin
- **AdManager.gd**: Unified abstraction — all game code calls through it

### Status
- [x] AdManager.gd updated with real AdMob API calls (banner, interstitial, rewarded)
- [x] Custom HTML shell created with AdSense containers + JS ad bridge
- [x] export_presets.cfg updated to use custom HTML shell
- [x] Test ad unit IDs configured in AdManager.gd ADMOB_IDS dict
- [x] Install poing-studios AdMob plugin (v4.2.0 at `addons/admob/`)
- [x] Replace test ad IDs with production IDs (6 ad units + 2 App IDs)
- [ ] Register AdSense account and update HTML shell publisher/slot IDs
- [ ] Test on real Android device
- [ ] Test on real iOS device
- [ ] Test web build with AdSense

### Mobile: Install AdMob Plugin
1. In Godot editor: **AssetLib** → search `AdMob` by `poing.studios` → Download & Install
2. Or manually: download from [poingstudios/godot-admob-android releases](https://github.com/poingstudios/godot-admob-android/releases)
3. **Project → Install Android Build Template** (required for custom plugins)
4. Enable plugin: **Project → Project Settings → Plugins → AdMob**
5. The plugin provides `MobileAds`, `AdView`, `InterstitialAdLoader`, `RewardedAdLoader` classes
6. AdManager.gd already has full integration code — it checks `ClassDB.class_exists(&"MobileAds")` and gracefully falls back if the plugin isn't installed

### Mobile: Production Ad IDs
When ready for release, update `ADMOB_IDS` dict in AdManager.gd:
1. Register app on [AdMob](https://admob.google.com/)
2. Create ad units: Banner, Interstitial, Rewarded (for both Android and iOS)
3. Replace the `ca-app-pub-3940256099942544/...` test IDs with your production IDs
4. Add your AdMob App ID to: Android manifest (`com.google.android.gms.ads.APPLICATION_ID`), iOS `GADApplicationIdentifier`

### Web: AdSense Setup
1. Register on [Google AdSense](https://adsense.google.com/)
2. In `web/custom_shell.html`, replace the placeholder values:
   - `$ADSENSE_CLIENT_ID` → your publisher ID (e.g. `ca-pub-1234567890123456`)
   - `$ADSENSE_BANNER_SLOT` → your banner ad slot ID
   - `$ADSENSE_INTERSTITIAL_SLOT` → your interstitial/display ad slot ID
3. The custom shell provides `showBannerAd()`, `hideBannerAd()`, `showInterstitialAd(id)`, `showRewardedAd(id)` — all called by AdManager.gd via JavaScriptBridge

### Testing Checklist
- [ ] Mobile: Banner shows on Menu and UpgradeShop, hides during gameplay
- [ ] Mobile: Interstitial shows on death→retry and victory→shop transitions
- [ ] Mobile: Rewarded ad grants 50 moonrocks, button text updates correctly
- [ ] Mobile: "Remove Ads" persists via `adstate.json`, hides all ad UI
- [ ] Web: Banner displays at bottom of page on menu/shop screens
- [ ] Web: Interstitial overlay shows between levels with 5s close timer
- [ ] Web: Rewarded overlay shows for 15s then grants moonrocks
- [ ] Desktop: No ads shown, `is_ad_free()` returns true

---

## 🎮 Google Play Games Services (PGS)

### Status
- [x] GodotPlayGameServices plugin v3.2.0 installed (`addons/GodotPlayGameServices/`) — by Jacob Ibáñez Sánchez
- [x] GodotPlayGameServices autoload registered in project.godot (required by plugin v3.x)
- [x] `android/build/res/values/games-ids.xml` created (`game_services_project_id = 412379035812`)
- [x] Gradle build enabled (`export_presets.cfg` → `use_gradle_build=true`)
- [x] PlayGamesManager.gd autoload — achievements-only, all no-op on non-Android
- [x] GameCenterManager.gd autoload — iOS Game Center achievements, mirrors PlayGamesManager API
- [x] 13 achievement hooks wired into game logic (globalvar.gd ×9, rocket.gd ×1) — both managers called
- [x] Achievements button on Menu (Android: PGS overlay, iOS: Game Center overlay)
- [x] Google Cloud project created (Project ID: 412379035812)
- [x] OAuth credential — Debug: "Wownero Moon Launch Debug OAuth" (SHA-1: `C0:77:E2:83:...`, Client ID: `412379035812-d3n3...`)
- [x] OAuth credential — Release: "Wownero Moon Launch Prod OAuth" (SHA-1: `BC:6B:16:08:...`, Client ID: `412379035812-c089...`)
- [x] 13 achievements created in Play Console (bulk-imported via ZIP)
- [x] Achievement IDs pasted into `PlayGamesManager.gd`
- [x] PGS project published
- [x] 13 achievements created in App Store Connect (Game Center)
- [x] Game Center entitlement enabled in iOS export preset
- [ ] Test on real Android device
- [ ] Test on real iOS device

### Architecture
- **Leaderboards**: Own backend at `api.such.software` (cross-platform, not PGS)
- **Achievements (Android)**: PGS via GodotPlayGameServices v3.2.0 plugin
- **Achievements (iOS)**: Game Center via built-in Godot singleton
- **Sidekick**: Automatic with PGS v2 sign-in (no extra code)
- **Package name**: `com.suchsoftware.wowneromoonlaunch`

See **DEPLOY.md §10** for full PGS setup guide and achievement creation table.
