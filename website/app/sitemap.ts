import type { MetadataRoute } from "next";

const siteUrl = (
  process.env.NEXT_PUBLIC_SITE_URL || "https://moonlaunch.space"
).replace(/\/+$/, "");

export default function sitemap(): MetadataRoute.Sitemap {
  return ["", "/play", "/store"].map((path) => ({
    url: `${siteUrl}${path}`,
    changeFrequency: path ? "monthly" : "weekly",
    priority: path ? 0.8 : 1,
  }));
}
