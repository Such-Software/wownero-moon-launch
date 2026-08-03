// Public deployment configuration for the independent web profile. NO SECRETS.
// Docs and config/commerce-catalog-v1.json pin the three Moon Launch offers.
// Operations has not provisioned the OIDC/ledger/checkout facts, so checked-in
// source stays completely inert even though the release catalog is defined.
// Operations may replace these public values only after the owning systems and
// coordinated evidence gates admit them; app developers never invent the IDs.
window.SUCH_APP_CONFIG = {
  oidcIssuer: null,
  oidcClientId: null,
  ledgerBase: null,
  checkoutUrl: null,
  checkoutEnabled: false,
};
