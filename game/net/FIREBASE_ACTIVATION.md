# Firebase activation runbook (the native half of v1.1.0 analytics)

The GDScript half is done: `Analytics.gd` (autoload) + dual-sink death-forensics +
call sites. It **no-ops until a native Firebase singleton exists**. This doc is the
remaining native/console/device work — it touches the mobile builds, so do it
deliberately and verify on-device.

Company procedure: `~/src/docs/engineering/app-analytics.md` +
`~/src/such-hq/private_docs/APP_ANALYTICS.md`. Reference bridge: `~/src/bloomword`.

## Decision: reuse the generic bridge vs rebuild renamed

The bridge is a **generic** Firebase wrapper. Its singleton name is cosmetic; the
`GoogleService-Info.plist` / `google-services.json` you ship decide which Firebase
app receives the data. So:

- **Option A — reuse the reviewed generic bridge already vendored here.**
  Keep `Analytics.gd` `FIREBASE_SINGLETON := "BloomwordFirebase"`. The singleton
  label is a provider-adapter implementation detail; it is never an app ID.
- **Option B — rebuild a shared/renamed bridge** (e.g. `SuchFirebase`). Cleaner long
  term, but needs the native toolchain (Xcode xcframework + Android `.aar`) and a
  rebuild of Bloomword too. Defer until the bridge is proven.

`Analytics.gd` currently targets the shared `BloomwordFirebase` wrapper. Its
`app_id` user property is always the canonical `moon_launch`; any historical
provider label remains confined to the provider/Fleet ingestion adapter.

## Operations-owned enrollment and delivery

Provider enrollment is an Operations ceremony against the exact release-contract
bundle/package IDs. App developers do not create provider apps, infer IDs, download
credentials into the checkout, or reuse Bloomword provider files. Operations stores
the uniquely named provider artifacts in the approved secret authority and delivers
them ephemerally to the protected release lane without echoing their contents.

- **iOS:** the reviewed seed contains the generic plugin/framework binaries. The
  protected workflow overlays the Moon Launch `GoogleService-Info.plist` into its
  ignored staging checkout immediately before export. The `.gdip` links that file.
- **Android:** the generic editor export plugin and AARs are already vendored. The
  protected workflow materializes the Moon Launch `google-services.json` below
  Build and passes its exact path as `SML_ANDROID_GOOGLE_SERVICES_PATH` to
  `tools/export_candidate.sh`.

No provider configuration belongs in Git, a developer command line, Seafile, or a
persistent source path. Release evidence records only identifiers and hashes safe to
disclose; it never records provider-file contents.

## Verify (before shipping)

- Run a debug device build with `SML_ANALYTICS_DEBUG=1` (Analytics is gated off in
  debug otherwise). Confirm `[Analytics]` prints, then events in GA4 **DebugView**.
- Play one full launch → confirm `launch_attempt`, `launch_complete`,
  `activation_moment`, and a death → `level_death` (bucketed) reach GA4; the raw
  forensics row still goes to `/v1/events` via `Telemetry.gd` (dual sink — keep both).
- BigQuery export auto-enrolls; data appears in `analytics_532410027` next day.

## Register in such-hq (cockpit picks it up)

- Fleet-generated inventory → canonical `moon_launch` with exact observed
  `bundles:{ios,android}` (separate provider IDs).
- `projects.yaml` → `analytics:{source:bigquery, app:moon_launch}` + `thresholds`
  (pull D1/D7/activation targets from the GTM/strategy doc). Activation = first
  successful launch.

## Also in this v1.1.0 pass (see [[project-firebase-v1-1-0-balance-events]])

- IAP → full GA4 `purchase` schema (`value`,`currency`,`transaction_id`,`items[]`),
  not the custom shape. `IAPManager.gd` currently logs to backend only.
- The event-dup bug is client-side in `Telemetry.gd` re-enqueue; Firebase becoming
  the funnel sink sidesteps it. Remove the temporary remote ad-config flag.
