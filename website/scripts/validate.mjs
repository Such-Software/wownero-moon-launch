import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const requiredAssets = [
  "public/app-icon.png",
  "public/computer-speak.ttf",
  "public/feature-graphic.png",
  "public/gameplay-cockpit.png",
  "public/gameplay-flight.png",
  "public/martian.png",
  "public/spacedoge.png",
];
const sourceFiles = [
  "app/brand.css",
  "app/brand.json",
  "app/layout.tsx",
  "app/page.tsx",
  "app/play/page.tsx",
  "app/store/page.tsx",
  "app/sitemap.ts",
  "app/globals.css",
];

const errors = [];
const packageJson = JSON.parse(
  await readFile(path.join(root, "package.json"), "utf8"),
);
const packageLock = JSON.parse(
  await readFile(path.join(root, "package-lock.json"), "utf8"),
);
const hosting = JSON.parse(
  await readFile(path.join(root, ".openai/hosting.json"), "utf8"),
);
const source = (
  await Promise.all(
    sourceFiles.map((file) => readFile(path.join(root, file), "utf8")),
  )
).join("\n");

const lockedPackages = packageLock.packages || {};
for (const dependency of ["next", "react", "react-dom"]) {
  const requested = packageJson.dependencies?.[dependency];
  const locked = lockedPackages[`node_modules/${dependency}`]?.version;
  if (!requested || requested !== locked) {
    errors.push(
      `${dependency} dependency and lock differ (${requested || "missing"} vs ${locked || "missing"})`,
    );
  }
}

for (const [dependency, expected] of [
  ["postcss", "8.5.25"],
  ["sharp", "0.35.3"],
]) {
  const locked = lockedPackages[`node_modules/${dependency}`]?.version;
  if (locked !== expected) {
    errors.push(`${dependency} must remain locked to reviewed ${expected}`);
  }
}

if (
  typeof hosting.project_id !== "string" ||
  !/^appgprj_[a-z0-9]+$/.test(hosting.project_id)
) {
  errors.push("Sites project_id is missing or malformed");
}

for (const asset of requiredAssets) {
  try {
    const details = await stat(path.join(root, asset));
    if (!details.isFile() || details.size === 0) {
      errors.push(`${asset} is empty or not a file`);
    }
  } catch {
    errors.push(`${asset} is missing`);
  }
}

for (const marker of ["TODO", "FIXME", "href=\"#\"", "$ADSENSE_", "PLACEHOLDER"]) {
  if (source.includes(marker)) {
    errors.push(`source contains unfinished marker ${marker}`);
  }
}

for (const required of [
  "https://apps.apple.com/us/app/such-moon-launch/id6767909623",
  "https://play.google.com/store/apps/details?id=com.suchsoftware.suchmoonlaunch",
  "https://suchsoftware.itch.io/such-moon-launch",
  "Checkout is closed",
  "Mobile purchases remain available only through Apple and Google",
  "NEXT_PUBLIC_UMAMI_WEBSITE_ID",
  "data-umami-event=\"cta_click\"",
  "data-umami-event=\"store_click\"",
  "data-umami-event=\"gameplay_open\"",
  "--bg: var(--sg-bg)",
]) {
  if (!source.includes(required)) {
    errors.push(`required policy or distribution copy is missing: ${required}`);
  }
}

for (const forbidden of ["BEGIN PRIVATE KEY", "BEGIN CERTIFICATE", "api_key="]) {
  if (source.includes(forbidden)) {
    errors.push(`website source contains forbidden credential material: ${forbidden}`);
  }
}

if (errors.length) {
  console.error(errors.map((error) => `FAIL ${error}`).join("\n"));
  process.exit(1);
}

console.log(
  `PASS MoonLaunch website validation (${sourceFiles.length} source files, ${requiredAssets.length} assets)`,
);
