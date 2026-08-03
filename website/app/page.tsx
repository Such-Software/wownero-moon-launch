const APP_STORE_URL =
  "https://apps.apple.com/us/app/such-moon-launch/id6767909623";
const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=com.suchsoftware.suchmoonlaunch";
const BROWSER_URL = "https://suchsoftware.itch.io/such-moon-launch";

export const metadata = {
  alternates: {
    canonical: "/",
  },
};

const missions = [
  {
    number: "01",
    title: "Land the impossible",
    copy: "Balance thrust, fuel, and velocity as every world invents a new way to ruin a perfectly good rocket.",
  },
  {
    number: "02",
    title: "Cross eleven worlds",
    copy: "Fly from Earth to the Moon, Mars, the outer planets, a rotating station, and one deeply unfriendly mothership.",
  },
  {
    number: "03",
    title: "Build your machine",
    copy: "Earn upgrades, unlock ship skins, and bring the right weapons when gentle landing stops being enough.",
  },
];

function Header() {
  return (
    <header className="site-header">
      <a className="wordmark" href="/" aria-label="Such Moon Launch home">
        <img src="/app-icon.png" alt="" width="44" height="44" />
        <span>Such Moon Launch</span>
      </a>
      <nav aria-label="Main navigation">
        <a href="#mission">Mission</a>
        <a href="#gameplay">Gameplay</a>
        <a href="/store">Hangar</a>
      </nav>
      <a
        className="header-cta"
        href="/play"
        data-umami-event="cta_click"
        data-umami-event-target="play"
        data-umami-event-placement="header"
      >
        Play now
      </a>
    </header>
  );
}

function StoreButtons() {
  return (
    <div className="store-buttons" aria-label="Download Such Moon Launch">
      <a
        href={APP_STORE_URL}
        target="_blank"
        rel="noreferrer"
        data-umami-event="store_click"
        data-umami-event-store="ios"
        data-umami-event-placement="download"
      >
        <span className="button-kicker">Download on the</span>
        <strong>App Store</strong>
      </a>
      <a
        href={PLAY_STORE_URL}
        target="_blank"
        rel="noreferrer"
        data-umami-event="store_click"
        data-umami-event-store="android"
        data-umami-event-placement="download"
      >
        <span className="button-kicker">Get it on</span>
        <strong>Google Play</strong>
      </a>
    </div>
  );
}

export default function Home() {
  return (
    <main>
      <section className="hero">
        <Header />
        <div className="hero-art" aria-hidden="true" />
        <div className="hero-scrim" aria-hidden="true" />
        <div className="hero-copy">
          <p className="eyebrow">
            <span aria-hidden="true">●</span> Flight window open
          </p>
          <h1>
            Land softly.
            <br />
            <span>Fly farther.</span>
          </h1>
          <p className="hero-lede">
            A Lunar Lander-inspired arcade odyssey across the solar system.
            Dodge the debris. Watch your fuel. Try not to become a crater.
          </p>
          <div className="hero-actions">
            <a
              className="primary-action"
              href={BROWSER_URL}
              target="_blank"
              rel="noreferrer"
              data-umami-event="gameplay_open"
              data-umami-event-placement="hero"
            >
              Play in browser <span aria-hidden="true">↗</span>
            </a>
            <a className="secondary-action" href="#mission">
              Mission briefing <span aria-hidden="true">↓</span>
            </a>
          </div>
        </div>

        <div className="mission-control doge-callout">
          <img
            src="/spacedoge.png"
            alt="Spacedoge mission controller"
            width="220"
            height="220"
          />
          <p>
            <span>Mission control</span>
            “Easy on the thrust, pilot.”
          </p>
        </div>
        <div className="mission-control martian-callout">
          <p>
            <span>Unknown signal</span>
            “Your parking spot is ready.”
          </p>
          <img
            src="/martian.png"
            alt="Martian watching the launch"
            width="190"
            height="190"
          />
        </div>
        <a className="scroll-cue" href="#mission">
          Scroll to launch <span aria-hidden="true">↓</span>
        </a>
      </section>

      <section className="mission-section" id="mission">
        <div className="section-heading">
          <p className="eyebrow">Mission briefing</p>
          <h2>One small landing. Several spectacular failures.</h2>
          <p>
            Every attempt teaches you the machine. Every destination changes
            the rules.
          </p>
        </div>
        <div className="mission-grid">
          {missions.map((mission) => (
            <article key={mission.number}>
              <span>{mission.number}</span>
              <h3>{mission.title}</h3>
              <p>{mission.copy}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="gameplay-section" id="gameplay">
        <div className="gameplay-copy">
          <p className="eyebrow">Cockpit view</p>
          <h2>The universe is big. Your fuel tank is not.</h2>
          <p>
            Race the CPU, chase clean landings through story mode, or see how
            long you last in endless waves. Tilt and touch controls keep the
            rocket responsive wherever you fly.
          </p>
          <ul>
            <li>
              <strong>11</strong> story destinations
            </li>
            <li>
              <strong>13</strong> ship skins
            </li>
            <li>
              <strong>∞</strong> endless trouble
            </li>
          </ul>
        </div>
        <div className="screenshot-stack">
          <figure className="screenshot-main">
            <img
              src="/gameplay-flight.png"
              alt="A rocket leaving Earth while collecting fuel and Moonrocks"
              width="1920"
              height="1080"
            />
          </figure>
          <figure className="screenshot-side">
            <img
              src="/gameplay-cockpit.png"
              alt="The rocket cockpit warping toward the Moon"
              width="1920"
              height="888"
            />
          </figure>
        </div>
      </section>

      <section className="platform-section">
        <div>
          <p className="eyebrow">Choose your launchpad</p>
          <h2>Play wherever you keep your thumbs.</h2>
        </div>
        <StoreButtons />
        <a
          className="browser-link"
          href={BROWSER_URL}
          target="_blank"
          rel="noreferrer"
          data-umami-event="gameplay_open"
          data-umami-event-placement="platforms"
        >
          Browser and desktop builds <span aria-hidden="true">↗</span>
        </a>
      </section>

      <section className="hangar-teaser">
        <div className="hangar-orbit" aria-hidden="true">
          <span />
          <img src="/app-icon.png" alt="" width="180" height="180" />
        </div>
        <div>
          <p className="eyebrow">The Hangar</p>
          <h2>The release catalog is locked.</h2>
          <p>
            Unlimited Races and both Moonrock packs are pinned for web and
            desktop. Checkout stays closed during payment, refund, and wallet
            recovery testing.
          </p>
          <a
            className="secondary-action"
            href="/store"
            data-umami-event="cta_click"
            data-umami-event-target="store-status"
            data-umami-event-placement="hangar"
          >
            Check hangar status <span aria-hidden="true">→</span>
          </a>
        </div>
      </section>

      <footer>
        <div className="footer-brand">
          <img src="/app-icon.png" alt="" width="54" height="54" />
          <div>
            <strong>Such Moon Launch</strong>
            <span>Such moon. Many landings. Wow.</span>
          </div>
        </div>
        <div className="footer-links">
          <a href="https://such.software/support">Support</a>
          <a href="https://such.software/products/such-moon-launch/privacy">
            Privacy
          </a>
          <a href="mailto:apps@such.software">Contact</a>
        </div>
        <p>© 2026 Such Software LLC</p>
      </footer>
    </main>
  );
}
