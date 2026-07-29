# Such Moon Launch App Platform v1

This repository consumes the shared contract pinned in
`config/app-platform-v1.json`. The app owns its gameplay and guest-claim rules;
it does not redefine shared identity, entitlement, commerce, or brand
semantics.

## Current posture

All App Platform services and product surfaces are disabled. The accepted
friendly room slice and merge invariants are recorded in
`docs/adr/0001-app-platform-v1-adoption.md`.

| Concern | Planned value | Current status |
| --- | --- | --- |
| App ID | `moon_launch` | registered |
| Nakama project | `such-moon-launch` | disabled; private runtime source present, no runtime promoted |
| Database | `nakama_moon_launch` | disabled |
| Backup tag | `nakama-moon-launch` | disabled |
| Shop label | Such Moon Launch Shop | planned |
| Medusa tenant/channel/client IDs | provisioned values only | `null` |
| Marketing/shop/play/API/admin domains | verified values only | `null` |
| Native OIDC client/redirect | provisioned exact values only | `null` |
| Shared Premium offer mapping | reviewed catalog only | not provisioned |
| Nearby P2P | separate future adapter | disabled |

The Medusa portfolio branch already declares Moon Launch as a disabled,
planned storefront. Provisioning must create a dedicated tenant, sales
channel, storefront, Wownero theme projection, OIDC shop client, catalog
namespace, outbox credential, and isolated restore proof before activation.
The app never derives any real identifier from `moon_launch`.

## Client and commerce boundaries

Native login will use the system browser with Authorization Code, S256 PKCE,
and a public app client. The shared issuer renders verified email,
Ethereum SIWE, and Smirk/Nostr methods. Wallet methods are labelled sign-in,
never payment.

Official iOS and Google Play profiles retain native billing and compile with
external digital checkout and cryptocurrency purchase surfaces closed. Web
commerce remains outside official mobile artifacts. Clients consume only the
neutral `premium` capability; they do not infer it from receipts, wallet
activity, Medusa orders, or local save flags.

The existing Flask score/save API remains the compatibility authority until a
reviewed migration moves writes through one idempotent adapter to app-owned
Nakama. Its recoverable client HMAC is legacy obfuscation, not a secret or a
trust boundary.

## Secrets

Vaultwarden is the human secret authority. OnlyKey may protect human
authentication and recovery access, but secret values are delivered to CI and
Fleet only through the approved non-echoing broker or ephemeral deployment
wrapper. No app-platform secret belongs in Git, a client bundle, Build output,
Seafile, a command line, or a new file under `~/keys`.

Existing `~/keys` files remain intact until each value has a uniquely named
Vaultwarden replacement, unattended-use path, independent recovery proof, and
accepted rotation. Their existence is not permission to read or copy them.

## Private runtime artifacts

`server/nakama` implements the common App Platform v1 runtime surface against
the Nakama 3.40.0 / runtime-types 1.47.0 compatibility pair. It includes the
one-use IdP ticket hook, readiness and build metadata, neutral entitlement
reads, independently signed ordered entitlement projection, hash-only
guest-claim proofs, the Moon Launch merge invariants, and recoverable guest
tombstones.

The checked-in build entry point installs and compiles only inside Build:

```bash
bash tools/ci/build_nakama_runtime.sh
```

It rejects uncommitted runtime inputs and writes the immutable bundle to:

```text
~/Build/such-moon-launch/nakama/<source-commit>/
  index.js
  migrations.sql
  runtime-manifest.json
  SHA256SUMS
  test-results/
```

Runtime and migration SHA-256 fields are computed independently. No
`node_modules`, compiler output, npm cache, test report, or generated manifest
belongs in the source worktree.

The protected integration lane supplies a reviewed immutable PostgreSQL image
and runs:

```bash
SML_POSTGRES_TEST_IMAGE='<registry/image@sha256:...>' \
  bash tools/ci/test_nakama_postgres.sh
```

This applies the migration bundle twice in a disposable tmpfs database and
exercises grant, duplicate, conflicting sequence, revoke, reinstate, full
projection convergence, guest merge, idempotent claim replay, and guest
tombstone preservation. A mutable image is never accepted by CI.

## Promotion gates

Before test activation:

1. confirm upgraded backend capacity from live Fleet facts;
2. build independently hashed runtime and migration artifacts from this repo;
3. provision exact private IdP and entitlement routes plus unique
   Vaultwarden-backed credentials;
4. provision and verify the five domain roles and OIDC callback;
5. complete real Nakama/PostgreSQL/IdP tests and two-device room evidence;
6. prove entitlement grant, duplicate, revoke, reinstate, and full replay;
7. restore the tagged app generation in isolation and measure RTO.

Before an official upload, run:

```bash
python3 tools/check_app_platform.py --expect-app moon_launch --promotion
```

Activation and store submission remain separate reviewed events.
