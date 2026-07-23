# Such Moon Launch CI

The repository now has two separate lanes:

- `.github/workflows/verify.yml` is secret-free and runs on every push, pull
  request, or manual dispatch. It validates the committed iOS contract, imports
  the Godot 4.6.1 project, and runs the gdUnit suite.
- `.github/workflows/build-ios-testflight.yml` is a manual private-Mac lane.
  Its default is a signed, inspected, retained IPA candidate with **no upload**.
  Delivery requires `upload_to_testflight=true`, an explicit unused positive
  build number above the committed baseline, and the exact `refs/heads/main`.

The app contract and ignored native-input checksums live in
`ci/ios-app.json`. `tools/ci/seed_manifest.py` verifies the runner cache before
and after it is overlaid. The lane fails closed on profile name, team, bundle,
expiry, Game Center and TestFlight entitlements, minimum iOS, IPA identity,
signature, native plugin symbols, and required payload. Every candidate retains
the IPA, SHA-256, and provenance; an upload also retains the parsed altool
receipt and log.

## Rollout TODO (no external changes have been made)

- [ ] Reconcile `polish-onboarding` into the intended release history and
  establish `main`. Today this checkout is on `polish-onboarding`, while
  `origin/HEAD` points to `master`; the delivery guard intentionally cannot
  upload either branch.
- [ ] Create the private `Builds/such-moon-launch` Gitea repository, add a
  `gitea-builds` remote, and mirror the reviewed release SHA as `main`.
- [ ] Seed the Mac runner at
  `~/Library/Caches/such-ios-sdks/such-moon-launch-ios/` with the exact
  `ios/...` paths declared in `ci/ios-app.json`. From a materialized checkout,
  verify it on the Mac with:

  ```bash
  python3 tools/ci/seed_manifest.py \
    --root "$HOME/Library/Caches/such-ios-sdks/such-moon-launch-ios"
  ```

- [ ] Install all eight Gitea repository secrets with the API helper, never by
  pasting long base64 values into the web UI:

  ```bash
  ~/keys/suchsoftware/set-gitea-ios-secrets.sh \
    Builds/such-moon-launch \
    ~/keys/suchsoftware/certs/SuchMoonLaunch_AppStore.mobileprovision
  ```

- [ ] Dispatch a no-upload candidate first, install its retained IPA on a real
  iPhone/iPad, then dispatch a `main` upload with a never-used build number.

The on-hand profile was inspected without copying it into the repository:
`SuchMoonLaunch_AppStore`, team `D8PL9F7X33`, bundle
`com.suchsoftware.suchmoonlaunch`, Game Center and TestFlight enabled, expiry
2027-02-17. Rotation should preserve those identities; the workflow validates
them from the actual secret on every run.
