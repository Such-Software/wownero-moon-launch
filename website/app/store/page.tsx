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
    detail: "Lifetime unlock. The mobile version also removes ads.",
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
        <p className="eyebrow">Hangar catalog · preview</p>
        <h1>Three offers. Checkout opens soon.</h1>
        <p>
          Here is what the launch catalog will include. Checkout is not open
          yet while we finish sign-in, Moonrock delivery, and refund handling.
          Nothing on this page can start a payment.
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
            Catalog and offers set
          </div>
          <div role="listitem">
            <span aria-hidden="true">✓</span>
            Store design finished
          </div>
          <div role="listitem" className="status-pending">
            <span aria-hidden="true">○</span>
            Payments
          </div>
          <div role="listitem" className="status-pending">
            <span aria-hidden="true">○</span>
            Refund and restore testing
          </div>
        </div>
        <p className="store-policy">
          Mobile purchases are handled by Apple and Google billing inside
          their apps. Web and desktop checkout will run through the Moon
          Launch storefront once it opens.
        </p>
      </div>
    </main>
  );
}
