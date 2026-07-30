import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  const indexingEnabled = process.env.NEXT_PUBLIC_SITE_INDEX === "true";

  return {
    rules: indexingEnabled
      ? { userAgent: "*", allow: "/" }
      : { userAgent: "*", disallow: "/" },
  };
}
