# Such Moon Launch

Arcade rocket landing across the solar system, built with Godot 4.6.1.

- [App Store](https://apps.apple.com/us/app/such-moon-launch/id6767909623)
- [Google Play](https://play.google.com/store/apps/details?id=com.suchsoftware.suchmoonlaunch)
- [Web and desktop](https://suchsoftware.itch.io/such-moon-launch)

## Verify and export

Run the pinned source-verification gate:

```bash
GODOT_BIN=/path/to/Godot_v4.6.1 tools/ci/verify.sh
```

Create a release candidate outside the source checkout:

```bash
GODOT_BIN=/path/to/Godot_v4.6.1 tools/export_candidate.sh Android
```

Generated products, logs, tests, and caches go under
`${SUCH_BUILD_ROOT:-$HOME/Build/such-moon-launch}`. The checkout remains
authoritative source; Build content is disposable and must never contain
signing keys.

Android export requires the Godot custom template at `android/build` plus these
Vaultwarden-provisioned values in the current shell:

```text
GODOT_ANDROID_KEYSTORE_RELEASE_PATH
GODOT_ANDROID_KEYSTORE_RELEASE_USER
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
SML_ANDROID_GOOGLE_SERVICES_PATH
```

Materialize secret files only into a protected temporary directory, never the
checkout, Build deliverables, or Seafile. On a persistent workstation,
`android/build` may be an ignored symlink into
`~/Build/such-moon-launch/cache` so Gradle intermediates do not refill the
checkout.

Marketing renders also default to Build scratch/review space. Promote only an
approved delivery into:

```text
~/Seafile/Marketing Media/such-moon-launch/
  source/
  work/
  deliveries/YYYY-MM-DD-slug/
  archive/
```

An accepted delivery needs a README, manifest, SHA256SUMS, byte counts, review
evidence, and verifier. See [marketing/README.md](marketing/README.md).

Real worktrees live under `~/src`; this repository should be worked from
`~/src/WowneroMoonLaunch`. `~/Seafile/Source` is Fleet-managed recovery only:
never clone, edit, build, seed, rename, delete, or manually synchronize it.
Credentials remain in Vaultwarden. The private Gitea rollout and release-lane
prerequisites—including manual TestFlight and Google Play internal
candidates—are tracked in [CI.md](CI.md).
