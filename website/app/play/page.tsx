const BROWSER_URL = "https://suchsoftware.itch.io/such-moon-launch";

export const metadata = {
  title: "Play",
  description: "Launch the browser and desktop editions of Such Moon Launch.",
  alternates: {
    canonical: "/play",
  },
};

export default function PlayPage() {
  return (
    <main className="status-page play-page">
      <a className="back-link" href="/">
        <span aria-hidden="true">←</span> Mission control
      </a>
      <div className="status-card">
        <img
          className="status-character"
          src="/spacedoge.png"
          alt="Spacedoge in a spacesuit"
          width="260"
          height="260"
        />
        <p className="eyebrow">Browser flight deck</p>
        <h1>Ready when you are, pilot.</h1>
        <p>
          The web build launches on itch.io in a new tab. Fullscreen works
          best on a desktop browser, but touch controls are available too.
        </p>
        <a
          className="primary-action"
          href={BROWSER_URL}
          target="_blank"
          rel="noreferrer"
          data-umami-event="gameplay_open"
          data-umami-event-placement="play-page"
        >
          Open the flight deck <span aria-hidden="true">↗</span>
        </a>
        <small>
          The game opens separately because itch.io permits gameplay only on
          its own trusted pages.
        </small>
      </div>
    </main>
  );
}
