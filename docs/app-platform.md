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
| Shop label | Such Moon Launch Shop | provisioned inactive on staging |
| Medusa production tenant/channel/client IDs | provisioned values only | `null` |
| Medusa staging tenant/channel/theme | exact provisioned IDs | inactive |
| Marketing domain | `moonlaunch.space` | assigned; parked and inactive |
| Shop domain | `shop.moonlaunch.space` | assigned; DNS/route/TLS inactive |
| API domain | `api.moonlaunch.space` | assigned; route/TLS not provisioned |
| Play/admin domains | provisioned values only | `null` |
| Native OIDC client/redirect | provisioned exact values only | `null` |
| App Platform offers | canonical registry only | none registered |
| Nearby P2P | separate future adapter | disabled |

The Medusa portfolio branch already declares Moon Launch as a disabled,
planned storefront. The intended storefront is `shop.moonlaunch.space`, but
its production portfolio domain remains `null` until activation evidence
passes.
Provisioning must create a dedicated tenant, sales
channel, storefront, Wownero theme projection, OIDC shop client, catalog
namespace, outbox credential, and isolated restore proof before activation.
The app never derives any real identifier from `moon_launch`.

## Verified staging shop evidence

On 2026-07-30, the reviewed Medusa platform source at
`d607c7929d43aad92655f62672100cd892f3b8d4` provisioned the Moon Launch shop
twice on staging, with the second run reusing the first run's identifiers:

- channel: `sc_01KYS5WZX1VWAXHAKQ6KQHT09T`;
- tenant: `01KYS5WZY7ANBKGGR7JNAS0242`;
- theme: `01KYS5WZYCK52GJSSFZ2TTDX1W`.

The dedicated channel is disabled, the tenant is inactive with no live
domain, payment provider, catalog products, or production OIDC client, and
the tenant lookup and historical apex host route return `404`. The
Wownero projection matched the then-pinned consumer lock and the linked
publishable key count is exactly one. That historical staging proof predates
the current `92cec272…` projection and must be reconciled and re-proved before
activation; it is not current brand evidence. A validated pre-provision
database dump is retained under the staging host's `~/Build`; no credential or
database artifact was copied into this repository or Seafile.

The staged source archive SHA-256 is
`07785fc8b79391dff0b6739c90c1923d0fd23e9c92561bb2fdfa3161f5239282`.
The rollback dump SHA-256 is
`f5e9bfb39d392c3d72f65e0e9bee67b330c112b0db902fce9007f9cd618cb452`.
Targeted provisioner tests passed, backend health remained `200`, and all
service restart counters were unchanged.

## Domain and DNS posture

The App Platform registry at
`docs@75d167f230bc42b834e13ffbb2056dbeb2b719f4` assigns:

- marketing: `moonlaunch.space`;
- shop: `shop.moonlaunch.space`;
- API: `api.moonlaunch.space`;
- play and admin: `null`.

As observed on 2026-07-30, Namecheap BasicDNS still has the apex URL
forwarding to `www`, `www` on the parking CNAME, and `EmailType=FWD`.
The public forwarding MX and SPF records are active. The daily Such HQ DNS
timer on `deb` has a successful registrar XML snapshot for the domain; an
additional read-only snapshot was verified at `20260730_052721`.

Namecheap `setHosts` is replace-all. A reviewed cutover must fetch the live
zone immediately before writing, save the raw response, retain
`EmailType=FWD`, preserve unrelated records, and verify the complete zone
afterward. Do not publish the apex or API record until the matching edge
route, certificate path, health check, and rollback target are ready.

## Shop theme handoff

The registry-pinned Wownero projection is generated from Such Graphics commit
`9f05ca86c04cb252a3c2a159f3c08c3677dbf5dc`. Keep generated provisioner
input outside this source worktree:

```bash
PROJECTION_ROOT="$HOME/Build/such-graphics/brands"
PROJECTION_COMMIT=9f05ca86c04cb252a3c2a159f3c08c3677dbf5dc
PROJECTION_DIR="$PROJECTION_ROOT/$PROJECTION_COMMIT/wownero"
sha256sum "$PROJECTION_DIR/brand.lock.json"
```

The required lock SHA-256 is
`92cec272c4fb7dfda7595b14ec4b76cb285cf2d83d41db2ed641e3ca7086451f`.
Provisioning must reject any other projection. The inactive Medusa
provisioner still requires the real intended shop domain; no tenant, channel,
client, domain, catalog, price, payment, or offer identifier may be invented
from this handoff.

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

`config/storefront-content-v1.json` is the app-owned, brand-locked storefront
copy for the inactive tenant flow. `web/app-config.js` and `web/checkout.js`
adapt the Bauhaus Echo client pattern to the Godot web shell. Source public
configuration is all null/false, and the ordinary fallback remains the Hangar
status page. The canonical registry currently has `offers: []` for Moon Launch,
so Operations cannot enable digital checkout until a reviewed registry offer,
provider records, OIDC client, ledger route, and coordinated evidence exist.
The web client reads a resolved neutral Premium capability only in memory; it
never persists that projection into the local ad-removal save flag.

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

The runtime consumes Fleet's exact `SUCH_*` environment roles. Readiness
requires the reviewed app, schema, contract and source pins; independent
runtime and migration digests; exact private IdP and entitlement paths;
unique opaque secret roles; both native product catalogs; and Nakama 3.40.0
or newer. Legacy `APP_*`, `IDP_*`, and unscoped entitlement-key roles are
rejected by CI.

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

1. retain the successful 2026-07-30 Fleet capacity preflight evidence (3 CPUs,
   9951 MiB memory, 193746558976 bytes free on `/`, and no existing app
   containers on `such-backend`), while re-running all mutable content and
   dependency gates against the current pins;
2. build independently hashed runtime and migration artifacts from this repo;
3. provision exact private IdP and entitlement routes plus unique
   Vaultwarden-backed credentials;
4. provision and verify the five domain roles and OIDC callback;
5. complete real Nakama/PostgreSQL/IdP tests and two-device room evidence;
6. prove entitlement grant, duplicate, revoke, reinstate, and full replay;
7. restore the tagged app generation in isolation and measure RTO.

Capacity is no longer the activation blocker. Fleet remains disabled with an
empty selected-app list, and activation remains blocked on immutable image
releases, Vaultwarden-backed secret delivery, private routes, native product
catalogs, integration evidence, and isolated recovery proof.

The official iOS export now includes a reviewed ATT purpose string so the
UMP-configured IDFA explainer can present Apple's system prompt during device
testing. The pinned AdMob v6 native bridge still lacks UMP
`canRequestAds`, privacy-options requirement, and privacy-options form
bindings. Keep store promotion closed until a reviewed bridge upgrade exposes
those APIs, the app provides the required visible settings entry point, and
the complete consent/deny/offline/revisit flow passes on physical iOS and
Android devices.

Before an official upload, run:

```bash
python3 tools/check_app_platform.py --expect-app moon_launch --promotion
```

Activation and store submission remain separate reviewed events.
