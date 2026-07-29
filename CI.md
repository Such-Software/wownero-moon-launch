# Such Moon Launch mobile CI and internal delivery

The repository has four deliberately separate lanes:

- `.github/workflows/verify.yml` is a secret-free public-review gate.
- `.gitea/workflows/verify.yml` runs the same gate on the private mirror.
- `.gitea/workflows/build-ios-testflight.yml` is the iOS signing and delivery
  lane. It is manual, `main`-only, and bound to the unique
  `such-m5-release` runner label.
- `.gitea/workflows/build-android-candidate.yml` is the Android signing and
  optional Play-internal lane. It is manual, `main`-only, and bound to the
  unique `such-android-release` runner label.

The platform contracts are committed in `ci/ios-app.json` and
`ci/android-app.json`. The iOS signing lane fails
closed on the request, source ref, Xcode/iOS SDK generation, seed checksums,
certificate/profile membership and expiry, team, bundle, Game Center and
TestFlight entitlements, IPA identity, signature, encryption declaration,
native plugin symbols, privacy manifests, and required payload.

A no-upload dispatch retains the signed App Store IPA, checksum, and
provenance. An upload dispatch additionally:

1. checks App Store Connect before building to prove the requested build number
   is unused;
2. validates and uploads the inspected IPA, requiring `altool` exit status 0;
3. polls App Store Connect until the exact build becomes `VALID`;
4. verifies `usesNonExemptEncryption=false`;
5. assigns the build to the configured internal TestFlight group; and
6. retains a processing/distribution receipt and upload logs.

“Upload accepted” is not treated as release success. Apple processing and
internal-group assignment must both complete.

The Android lane uses a verified Godot/template toolchain and bundletool,
materializes signing/Firebase inputs only in a protected temporary directory,
keeps its custom Gradle template and project cache under Build, and verifies
the exact package, version, API levels, native-plugin manifest markers,
Firebase client, JAR signature, and signing-certificate fingerprint in the
finished AAB. A no-upload dispatch retains the inspected AAB, checksums, and
provenance. An upload dispatch validates and publishes that same AAB to the
Google Play internal track with pinned fastlane, then retains a receipt and
logs.

Godot 4.6.1's stock disposable Gradle template is API 35 / AGP 8.6.1. The
candidate wrapper prepares only the copy below Build with compile/target API
36, Build Tools 36.0.0, AGP 8.9.1, and Gradle 8.11.1; unexpected template
drift fails closed. It also materializes the committed public Play Games
project ID into that copy. No generated Gradle template is committed.

## Release-Mac prerequisites

- Register one locked-down Apple Silicon runner with the exact
  `such-m5-release` label. Its runner workspace must be below `~/src/_ci`, not
  Seafile.
- Install Xcode 26 or newer with the iOS 26 SDK or newer, accept its license,
  and select it with `xcode-select`.
- Install the private Git server CA as a trusted certificate for the runner
  account and Node actions. The workflows contain no TLS-verification bypass.
- Seed `~/Build/such-moon-launch/cache/ios-seed/` with the exact `ios/...`
  paths declared in `ci/ios-app.json`, then validate it:

  ```bash
  python3 tools/ci/seed_manifest.py \
    --root "$HOME/Build/such-moon-launch/cache/ios-seed"
  ```

- Provision these Gitea repository secrets from Vaultwarden through the
  approved non-echoing secret broker:

  ```text
  APPLE_TEAM_ID
  APPLE_DIST_CERT_P12_BASE64
  APPLE_DIST_CERT_P12_PASSWORD
  APPLE_PROVISIONING_PROFILE_BASE64
  APPLE_KEYCHAIN_PASSWORD
  APPLE_KEY_ID
  APPLE_ISSUER_ID
  APPLE_API_KEY_P8_BASE64
  APPLE_BETA_GROUP_ID
  ```

  The API key needs sufficient App Store Connect access to read builds and add
  a build to the selected internal beta group. Credentials belong in
  Vaultwarden, never Git, Build artifacts, or Seafile Source.

- Publish the reviewed release history as `main` in the intended private Gitea
  repository. The delivery workflow rejects every other ref.

## First rollout

1. Run the secret-free Gitea verifier.
2. Dispatch a no-upload candidate from `main`; inspect its retained IPA,
   checksum, and provenance.
3. For physical-device testing, use TestFlight. An App Store-signed IPA is
   inspection-only and is not a direct-install test package. A separate Ad Hoc
   profile containing registered devices would be required for direct install.
4. Dispatch an upload with an explicit positive build number above the
   committed baseline. The workflow also checks Apple to ensure it has never
   been used.
5. Confirm internal testers can install it and register reviewer/test devices
   as AdMob test devices before interacting with production ad units.

Temporary keychains, profiles created by the run, P12/P8 files, and the
keychain search list are scoped and restored by the always-run cleanup step.
All products, logs, test reports, downloads, and caches are rooted below
`~/Build/such-moon-launch`.

## Android-runner prerequisites

- Register one locked-down Linux runner with the exact
  `such-android-release` label. Its runner workspace must be below `~/src/_ci`,
  not Seafile.
- Install JDK 17, Android SDK platform 36, and Build Tools 36.0.0. Accept the
  Android SDK licenses for the runner account and export `ANDROID_HOME`.
- The lane resolves Godot's stock template only below `~/Build`, upgrades it to
  AGP 8.9.1 / compile and target API 36, and rejects a final bundle unless
  bundletool reports `PAGE_ALIGNMENT_16K`.
- Install the private Git server CA as trusted for Git, curl, and Node actions.
  Do not bypass TLS verification.
- Preinstall fastlane `2.237.0` for optional Play delivery.
- Provision these Gitea repository secrets from Vaultwarden through the
  approved non-echoing secret broker:

  ```text
  ANDROID_KEYSTORE_BASE64
  ANDROID_KEYSTORE_PASSWORD
  ANDROID_KEY_ALIAS
  ANDROID_GOOGLE_SERVICES_BASE64
  ANDROID_PLAY_SERVICE_ACCOUNT_JSON_BASE64
  ```

  The Play service account needs access to the app and internal track.
  Credentials belong in Vaultwarden, never Git, Build artifacts, or Seafile
  Source.

For first rollout, run the secret-free verifier, dispatch a no-upload Android
candidate from `main`, inspect its retained AAB/checksums/provenance, and test
an internal build on physical devices. Only then dispatch with
`upload_to_play=true`.
