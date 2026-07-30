import type { Metadata } from "next";
import type { ReactNode } from "react";

import "./globals.css";

const siteUrl =
  process.env.NEXT_PUBLIC_SITE_URL || "https://moonlaunch.space";

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
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
