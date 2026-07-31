import type { MetadataRoute } from "next";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  const indexingEnabled = process.env.NEXT_PUBLIC_SITE_INDEX === "true";

  return {
    rules: indexingEnabled
      ? { userAgent: "*", allow: "/" }
      : { userAgent: "*", disallow: "/" },
    sitemap: indexingEnabled
      ? "https://moonlaunch.space/sitemap.xml"
      : undefined,
  };
}
