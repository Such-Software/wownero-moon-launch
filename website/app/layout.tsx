import type { Metadata } from "next";
import type { ReactNode } from "react";

import "./brand.css";
import "./globals.css";

const siteUrl =
  process.env.NEXT_PUBLIC_SITE_URL || "https://moonlaunch.space";

function reviewedUmamiUrl(value: string | undefined): string | null {
  if (!value) return null;

  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password) return null;
    return url.toString().replace(/\/+$/, "");
  } catch {
    return null;
  }
}

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Such Moon Launch",
    template: "%s · Such Moon Launch",
  },
  description:
    "Land your rocket, dodge asteroids, and cross the solar system in a playful Lunar Lander-inspired arcade game.",
  applicationName: "Such Moon Launch",
  category: "game",
  openGraph: {
    title: "Such Moon Launch",
    description: "Land softly. Fly farther. Such moon. Many landings. Wow.",
    type: "website",
    images: [
      {
        url: "/feature-graphic.png",
        width: 1024,
        height: 500,
        alt: "A cartoon rocket flying from Earth toward the Moon",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Such Moon Launch",
    description: "Land softly. Fly farther. Such moon. Many landings. Wow.",
    images: ["/feature-graphic.png"],
  },
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  const umamiUrl = reviewedUmamiUrl(process.env.NEXT_PUBLIC_UMAMI_URL);
  const configuredWebsiteId = process.env.NEXT_PUBLIC_UMAMI_WEBSITE_ID;
  const umamiWebsiteId =
    configuredWebsiteId &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      configuredWebsiteId,
    )
      ? configuredWebsiteId
      : null;

  return (
    <html lang="en">
      <body>
        {children}
        {umamiUrl && umamiWebsiteId ? (
          <script
            defer
            src={`${umamiUrl}/script.js`}
            data-website-id={umamiWebsiteId}
            data-do-not-track="true"
            data-domains="moonlaunch.space"
          />
        ) : null}
      </body>
    </html>
  );
}
