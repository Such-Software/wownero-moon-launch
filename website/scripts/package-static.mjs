import { rename, rm, stat } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const exported = path.join(root, "out");
const packaged = path.join(root, "dist");

const details = await stat(exported);
if (!details.isDirectory()) {
  throw new Error("Next.js static export did not produce out/");
}

await rm(packaged, { force: true, recursive: true });
await rename(exported, packaged);

console.log("PASS packaged static site in dist/");
