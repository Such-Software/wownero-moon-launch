export const metadata = {
  title: "Hangar status",
  description:
    "Pinned offers and activation status for the Such Moon Launch storefront.",
  alternates: {
    canonical: "/store",
  },
};

const offers = [
  {
    id: "race_unlimited_lifetime_v1",
    title: "Unlimited Races",
    price: "$1.99",
    detail:
      "Lifetime unlock on every platform. The free tier is one CPU race per day. The mobile version also removes ads.",
  },
  {
    id: "moonrocks_10k_v1",
    title: "10,000 Moonrocks",
    price: "$1.99",
    detail: "Credits exactly 10,000 Moonrocks to your Moon Launch account.",
  },
  {
    id: "moonrocks_50k_v1",
    title: "50,000 Moonrocks",
    price: "$7.99",
    detail: "Credits exactly 50,000 Moonrocks to your Moon Launch account.",
  },
];

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
        <p className="eyebrow">Hangar catalog · pinned, inactive</p>
        <h1>Three offers. Checkout still sealed.</h1>
        <p>
          The release catalog is locked below. Checkout is closed while
          identity, signed Moonrock delivery, refund reversal, duplicate
          replay, and recovery evidence are completed. Nothing on this page can
          start a payment.
        </p>
        <div className="offer-catalog" aria-label="Pinned release offers">
          {offers.map((offer) => (
            <article key={offer.id}>
              <div>
                <h2>{offer.title}</h2>
                <strong>{offer.price}</strong>
              </div>
              <p>{offer.detail}</p>
              <code>{offer.id}</code>
            </article>
          ))}
        </div>
        <div className="status-list" role="list" aria-label="Store setup status">
          <div role="listitem">
            <span aria-hidden="true">✓</span>
            Catalog and exact grants pinned
          </div>
          <div role="listitem">
            <span aria-hidden="true">✓</span>
            Brand projection locked
          </div>
          <div role="listitem" className="status-pending">
            <span aria-hidden="true">○</span>
            Provider IDs and payment proof
          </div>
          <div role="listitem" className="status-pending">
            <span aria-hidden="true">○</span>
            Refund, restore, and replay proof
          </div>
        </div>
        <p className="store-policy">
          Official mobile purchases remain available only through Apple and
          Google native billing inside their apps. Web and self-distributed
          desktop checkout will use the dedicated Moon Launch storefront after
          its activation evidence passes.
        </p>
      </div>
    </main>
  );
}
