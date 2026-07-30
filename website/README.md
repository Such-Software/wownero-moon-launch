# Such Moon Launch website

This is the intentional apex marketing/play surface for `moonlaunch.space`.
Commerce belongs on the dedicated Medusa tenant at
`shop.moonlaunch.space`; `/store` reports its inactive setup status and
contains no checkout.

The website consumes the generated Wownero `brand.css` projection pinned by
`config/app-platform-v1.json`. Do not hand-copy Such Graphics palette or
motion tokens into this site. Local dependencies, builds, test output, and
deployment packaging belong under `~/Build/such-moon-launch/website`, not in
this directory.

The connected Sites project is recorded only in `.openai/hosting.json` after
creation. Non-production builds remain `noindex`. An indexed marketing-only
release sets `NEXT_PUBLIC_SITE_INDEX=true` after its DNS, TLS, support,
privacy, analytics, rollback, and link checks pass; it does not activate the
store, identity, entitlements, multiplayer, or purchase surfaces.

Self-hosted Umami is optional and observed-only. Fleet projects
`NEXT_PUBLIC_UMAMI_URL` and `NEXT_PUBLIC_UMAMI_WEBSITE_ID` after provisioning;
an absent value means no tracker is emitted. Never invent an analytics ID.
