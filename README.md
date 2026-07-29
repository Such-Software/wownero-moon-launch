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

Generated products and logs go under `${SUCH_BUILD_ROOT:-$HOME/Build}`. The
checkout remains authoritative source; Build content is disposable and must
never contain signing keys.

Android export also requires the ignored `android/google-services.json`, the
Godot custom Android template at `android/build`, and the canonical upload key
under `~/keys`. On a persistent workstation, `android/build` may be an ignored
symlink into `~/Build/cache` so Gradle intermediates do not refill the checkout.

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

Signing identities and store credentials remain outside Git under `~/keys`.
The private Gitea rollout and release-lane prerequisites are tracked in
[CI.md](CI.md).
