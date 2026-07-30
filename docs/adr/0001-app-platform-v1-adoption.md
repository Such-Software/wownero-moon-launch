# ADR 0001: App Platform v1 adoption

- Status: accepted for implementation, activation closed
- Date: 2026-07-29
- App: Such Moon Launch (`moon_launch`)
- Source base: `d50da4f886adc6782e82d4642de619f770b86d31`
- Contract: `docs@339e9dab6bf711d28df87d42d2a44c7cefb6ed6a`

## Decision

Such Moon Launch will adopt App Platform v1 through the seven review stages in
the consumer playbook. The existing shared Flask service remains the legacy
authority for supported clients until the private Nakama runtime, migration,
write-through adapter, recovery evidence, and dual-path client have passed
their respective gates.

The first relayed gameplay slice is a friendly, two-player Level 1
first-to-land room. It is intentionally non-ranked and non-economic:

- the result grants no Moonrocks, stars, inventory, progression, achievement,
  Premium capability, or leaderboard entry;
- each client continues to simulate its own rocket and sends only bounded,
  versioned race state through `NakamaRelayedTransport`;
- the UI calls it an online room, never nearby, local, LAN, offline, or P2P;
- disconnect, host departure, protocol mismatch, or relay failure ends the
  room without changing durable game state.

Any future ranked, reward-bearing, inventory-changing, paid, or anti-cheat
sensitive mode must use a server-authoritative match or RPC. Relayed client
claims are never economic evidence.

The source worktree remains below `~/src`. All runtime bundles, migrations,
tests, exports, captures, caches, IPA/AAB files, and generated brand/site
projections use `/home/jw/Build/such-moon-launch`. Approved marketing masters
alone may be promoted to `~/Seafile/Marketing Media/such-moon-launch`.

## Guest claim invariants

Claims are idempotent and preserve a playable guest if any step fails.

- Furthest progression, best stars, upgrades, unlocked content, owned skins,
  completion flags, and best endless wave merge monotonically.
- Best completion times retain the lowest valid positive value.
- Inventory is a union by stable content ID. The selected skin changes only
  when the resulting account owns that skin.
- Lifetime counters use the greater observed value; they are not summed.
- An empty target may accept the guest's soft-currency balance. A non-empty
  target keeps its authoritative balance and records any conflict for audit;
  spent or competitive values are never blindly summed.
- Premium, ad removal, native purchases, and web purchases are not inferred
  from client save data. They come from the neutral entitlement ledger and
  provider validation.
- The merge result is hashed and stored with the idempotency key before the
  guest mapping can be retired.

Tests must cover an empty target, an existing target, conflicts, interruption,
concurrent replay, wrong-app and expired/consumed tickets, and IdP timeout.

## Consequences and rollback

Identity, Nakama, entitlements, friendly rooms, shop links, and nearby P2P are
compile-time closed in the baseline. No endpoint, domain, tenant, channel,
OIDC client, callback, product, or credential is fabricated.

Rollback disables the new client path and leaves local guest play plus the
supported legacy adapter available. New durable writes move to Nakama only
after idempotent legacy write-through exists; symmetric dual authority is
forbidden.

The current recoverable client-side legacy HMAC material cannot establish
server trust and must be treated as public. Operations must rotate it when the
legacy write-through replacement and supported-client plan are ready.
