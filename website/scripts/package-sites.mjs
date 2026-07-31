import { copyFile, mkdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const worker = path.join(root, "dist/server/index.js");
const vinextWorker = path.join(root, "dist/server/index.mjs");
const hostingSource = path.join(root, ".openai/hosting.json");
const hostingTarget = path.join(root, "dist/.openai/hosting.json");

const existingWorker = await stat(worker).catch(() => null);
const vinextDetails = await stat(vinextWorker).catch(() => null);

if (
  (!existingWorker?.isFile() || existingWorker.size === 0) &&
  (!vinextDetails?.isFile() || vinextDetails.size === 0)
) {
  throw new Error("vinext build did not produce a server entrypoint");
}

if (!existingWorker?.isFile() || existingWorker.size === 0) {
  await writeFile(
    worker,
    'export { default } from "./index.mjs";\nexport * from "./index.mjs";\n',
    "utf8",
  );
}

const details = await stat(worker);
if (!details.isFile() || details.size === 0) {
  throw new Error("Sites worker shim was not written to dist/server/index.js");
}

await mkdir(path.dirname(hostingTarget), { recursive: true });
await copyFile(hostingSource, hostingTarget);

console.log("PASS packaged Sites worker in dist/");
