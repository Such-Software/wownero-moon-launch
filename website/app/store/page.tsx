export const metadata = {
  title: "Hangar status",
  description:
    "Status of the inactive-first Such Moon Launch Medusa storefront.",
  alternates: {
    canonical: "/store",
  },
};

export default function StorePage() {
  return (
    <main className="status-page store-page">
      <a className="back-link" href="/">
        <span aria-hidden="true">←</span> Mission control
      </a>
      <div className="status-card">
        <img
          className="status-character"
          src="/martian.png"
          alt="Martian hangar attendant"
          width="240"
          height="240"
        />
        <p className="eyebrow">Hangar status · inactive</p>
        <h1>The shop doors are still sealed.</h1>
        <p>
          We are setting up a dedicated MoonLaunch storefront, catalog, and
          account-linked Premium system. Checkout is closed while identity,
          payment, entitlement replay, and recovery testing are completed.
        </p>
        <div className="status-list" role="list" aria-label="Store setup status">
          <div role="listitem">
            <span aria-hidden="true">✓</span>
            Dedicated staging tenant
          </div>
          <div role="listitem">
            <span aria-hidden="true">✓</span>
            Brand projection locked
          </div>
          <div role="listitem" className="status-pending">
            <span aria-hidden="true">○</span>
            Production catalog and payments
          </div>
          <div role="listitem" className="status-pending">
            <span aria-hidden="true">○</span>
            Activation and restore review
          </div>
        </div>
        <p className="store-policy">
          Mobile purchases remain available only through Apple and Google’s
          native billing inside their official apps.
        </p>
      </div>
    </main>
  );
}
