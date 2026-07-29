#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import {fileURLToPath} from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(scriptPath), "../..");

function fatal(message) {
  process.stderr.write(`FATAL: ${message}\n`);
  process.exit(1);
}

function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined) {
      fatal("expected --artifact-dir and --source-commit.");
    }
    values[key.slice(2)] = value;
  }
  return values;
}

function sha256(filePath) {
  return crypto
    .createHash("sha256")
    .update(fs.readFileSync(filePath))
    .digest("hex");
}

function listFiles(directory, prefix) {
  if (!fs.existsSync(directory)) {
    return [];
  }
  const files = [];
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const absolute = path.join(directory, entry.name);
    const relative = path.posix.join(prefix, entry.name);
    if (entry.isDirectory()) {
      files.push(...listFiles(absolute, relative));
    } else if (entry.isFile()) {
      files.push(relative);
    } else {
      fatal(`artifact evidence must not contain symlinks: ${relative}`);
    }
  }
  return files.sort();
}

const args = parseArguments(process.argv.slice(2));
const artifactDirectory = path.resolve(args["artifact-dir"] || "");
const sourceCommit = args["source-commit"] || "";

if (!artifactDirectory.split(path.sep).includes("Build")) {
  fatal("Nakama artifacts must be rendered below a Build directory.");
}
if (artifactDirectory.includes(`${path.sep}Seafile${path.sep}Source${path.sep}`)) {
  fatal("Seafile Source is never an artifact destination.");
}
if (!/^[0-9a-f]{40,64}$/.test(sourceCommit)) {
  fatal("source commit must be a full lowercase Git object ID.");
}

const runtimePath = path.join(artifactDirectory, "index.js");
const migrationPath = path.join(artifactDirectory, "migrations.sql");
for (const required of [runtimePath, migrationPath]) {
  if (!fs.statSync(required, {throwIfNoEntry: false})?.isFile()) {
    fatal(`missing artifact: ${required}`);
  }
}

const templatePath = path.join(
  root,
  "server/nakama/runtime-manifest.template.json"
);
const manifest = JSON.parse(fs.readFileSync(templatePath, "utf8"));
manifest.source_commit = sourceCommit;
manifest.runtime.sha256 = sha256(runtimePath);
manifest.migrations.sha256 = sha256(migrationPath);
manifest.tests.status = "passed";
manifest.tests.files = listFiles(
  path.join(artifactDirectory, manifest.tests.directory),
  manifest.tests.directory
);

const manifestPath = path.join(artifactDirectory, "runtime-manifest.json");
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, {
  mode: 0o644
});

const checksumFiles = [
  "index.js",
  "migrations.sql",
  "runtime-manifest.json",
  ...manifest.tests.files
];
const checksumLines = checksumFiles.map((relative) =>
  `${sha256(path.join(artifactDirectory, relative))}  ${relative}`
);
fs.writeFileSync(
  path.join(artifactDirectory, "SHA256SUMS"),
  `${checksumLines.join("\n")}\n`,
  {mode: 0o644}
);

process.stdout.write(
  `PASS Nakama artifacts (${artifactDirectory}, runtime ` +
  `${manifest.runtime.sha256}, migrations ${manifest.migrations.sha256})\n`
);
