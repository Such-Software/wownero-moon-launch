# Firebase activation runbook (the native half of v1.1.0 analytics)

The GDScript half is done: `Analytics.gd` (autoload) + dual-sink death-forensics +
call sites. It **no-ops until a native Firebase singleton exists**. This doc is the
remaining native/console/device work — it touches the mobile builds, so do it
deliberately and verify on-device.

Company procedure: `~/src/docs/engineering/app-analytics.md` +
`~/src/such-hq/private_docs/APP_ANALYTICS.md`. Reference bridge: `~/src/bloomword`.

## Decision: reuse Bloomword's bridge (fastest) vs rebuild renamed (cleaner)

The bridge is a **generic** Firebase wrapper. Its singleton name is cosmetic; the
`GoogleService-Info.plist` / `google-services.json` you ship decide which Firebase
app receives the data. So:

- **Option A — reuse Bloomword's compiled bridge as-is (recommended to start).**
  Copy its binaries into moonlaunch, ship such_moon's GoogleService files, and set
  `Analytics.gd` `FIREBASE_SINGLETON := "BloomwordFirebase"`. No Xcode/Gradle build.
  Matches JW's "co-debug between bloomword and here" — literally the same bridge.
- **Option B — rebuild a shared/renamed bridge** (e.g. `SuchFirebase`). Cleaner long
  term, but needs the native toolchain (Xcode xcframework + Android `.aar`) and a
  rebuild of Bloomword too. Defer until the bridge is proven.

`Analytics.gd` currently targets `MoonLaunchFirebase` — change that constant to match
whichever bridge you ship (1 line).

## iOS

1. Copy from `~/src/bloomword/godot/ios/`:
   - `plugins/BloomwordFirebase.{gdip,release.xcframework,debug.xcframework}` → moonlaunch `ios/plugins/`
   - `framework/Firebase*.xcframework` + `Google*`, `Promises`, `nanopb` → moonlaunch `ios/framework/`
2. The `.gdip` already lists the linked frameworks, system frameworks, linker flags
   (`-ObjC -lc++ -lsqlite3 -lz`), and `files=["GoogleService-Info.plist"]`.
3. Firebase console → add the such_moon **iOS** app (bundle id) to the
   `suchsoftwareapps` project → download `GoogleService-Info.plist` → drop in `ios/`
   (already gitignored).
4. Export preset (iOS): enable the plugin (`plugins/BloomwordFirebase=true`).

## Android

1. Copy `~/src/bloomword/godot/addons/BloomwordFirebase/` → moonlaunch `addons/`
   (the EditorExportPlugin that injects the Firebase Maven deps:
   `firebase-analytics:23.2.0`, `firebase-crashlytics:20.0.6`, `firebase-common:22.1.0`)
   and its `bin/{debug,release}/*.aar`.
2. Enable the plugin in Project Settings → Plugins.
3. Firebase console → add the such_moon **Android** app (package name) → download
   `google-services.json` → drop in `android/` (already gitignored).

## Verify (before shipping)

- Run a debug device build with `SML_ANALYTICS_DEBUG=1` (Analytics is gated off in
  debug otherwise). Confirm `[Analytics]` prints, then events in GA4 **DebugView**.
- Play one full launch → confirm `launch_attempt`, `launch_complete`,
  `activation_moment`, and a death → `level_death` (bucketed) reach GA4; the raw
  forensics row still goes to `/v1/events` via `Telemetry.gd` (dual sink — keep both).
- BigQuery export auto-enrolls; data appears in `analytics_532410027` next day.

## Register in such-hq (cockpit picks it up)

- `inventory.yaml` `apps:` → such_moon row with `bundles:{ios,android}` (separate ids).
- `projects.yaml` → `analytics:{source:bigquery, app:such_moon}` + `thresholds`
  (pull D1/D7/activation targets from the GTM/strategy doc). Activation = first
  successful launch.

## Also in this v1.1.0 pass (see [[project-firebase-v1-1-0-balance-events]])

- IAP → full GA4 `purchase` schema (`value`,`currency`,`transaction_id`,`items[]`),
  not the custom shape. `IAPManager.gd` currently logs to backend only.
- The event-dup bug is client-side in `Telemetry.gd` re-enqueue; Firebase becoming
  the funnel sink sidesteps it. Remove the temporary remote ad-config flag.
