// Public deployment configuration for the independent web profile. NO SECRETS.
// Docs registry currently has no Moon Launch offer and Operations has not
// provisioned the OIDC/ledger/checkout facts, so source stays completely inert.
// Operations may replace these public values only after the owning systems and
// coordinated evidence gates admit them; app developers never invent the IDs.
window.SUCH_APP_CONFIG = {
  oidcIssuer: null,
  oidcClientId: null,
  ledgerBase: null,
  checkoutUrl: null,
  checkoutEnabled: false,
};
