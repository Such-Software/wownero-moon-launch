#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BUILD_ROOT="${SML_BUILD_ROOT:-${SML_CI_BUILD_ROOT:-${SUCH_BUILD_ROOT:-$HOME/Build/such-moon-launch}}}"
SOURCE_COMMIT="$(git rev-parse HEAD)"
VERIFY_ID="${SML_VERIFY_RUN_ID:-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}}"
WORK_PARENT="$BUILD_ROOT/cache/website-work"
NPM_CACHE="$BUILD_ROOT/cache/website-npm"
OUTPUT="$BUILD_ROOT/website/$SOURCE_COMMIT/$VERIFY_ID"

[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40,64}$ ]] || {
  echo "FATAL: website source commit must be a full lowercase Git object ID." >&2
  exit 1
}

WEBSITE_STATUS="$(git status --porcelain --untracked-files=all -- \
  website \
  tools/ci/build_website.sh \
  tools/ci/verify.sh)"
if [[ -n "$WEBSITE_STATUS" ]]; then
  echo "FATAL: commit website inputs before producing a website build." >&2
  exit 1
fi

mkdir -p "$WORK_PARENT" "$NPM_CACHE" "$OUTPUT/test-results"
WORK="$(mktemp -d "$WORK_PARENT/$SOURCE_COMMIT.XXXXXX")"

cleanup_work() {
  if [[ -n "${WORK:-}" && "$WORK" == "$WORK_PARENT/"* ]]; then
    rm -rf -- "$WORK"
  fi
}
trap cleanup_work EXIT

git archive --format=tar --output="$WORK/source.tar" "$SOURCE_COMMIT:website"
mkdir -p "$WORK/source"
tar -xf "$WORK/source.tar" -C "$WORK/source"

(
  cd "$WORK/source"
  NEXT_TELEMETRY_DISABLED=1 \
    npm_config_cache="$NPM_CACHE" \
    npm ci --no-audit --no-fund \
    > "$OUTPUT/test-results/npm-ci.log"
  npm run validate | tee "$OUTPUT/test-results/validate.log"
  NEXT_TELEMETRY_DISABLED=1 \
    npm run build | tee "$OUTPUT/test-results/site-build.log"
)

[[ -s "$WORK/source/dist/server/index.js" ]] || {
  echo "FATAL: website build lacks the Sites worker entrypoint." >&2
  exit 1
}
[[ -s "$WORK/source/dist/.openai/hosting.json" ]] || {
  echo "FATAL: website build lacks its Sites project metadata." >&2
  exit 1
}

install -m 0644 "$WORK/source/dist/server/BUILD_ID" "$OUTPUT/BUILD_ID"
install -m 0644 "$WORK/source/package-lock.json" "$OUTPUT/package-lock.json"
sha256sum "$WORK/source/dist/server/index.js" |
  awk '{print $1}' > "$OUTPUT/worker-entrypoint.sha256"

(
  cd "$OUTPUT"
  sha256sum BUILD_ID package-lock.json worker-entrypoint.sha256
) > "$OUTPUT/SHA256SUMS"

VINEXT_VERSION="$(
  node -e '
    const fs = require("node:fs");
    const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(value.dependencies.vinext);
  ' "$WORK/source/package.json"
)"

{
  printf '{\n'
  printf '  "adapter": "vinext",\n'
  printf '  "adapter_version": "%s",\n' "$VINEXT_VERSION"
  printf '  "build_id": "%s",\n' "$(tr -d '\r\n' < "$OUTPUT/BUILD_ID")"
  printf '  "node_version": "%s",\n' "$(node --version)"
  printf '  "output_contract": "dist/server/index.js",\n'
  printf '  "schema_version": 1,\n'
  printf '  "source_commit": "%s",\n' "$SOURCE_COMMIT"
  printf '  "source_subtree": "website",\n'
  printf '  "worker_entrypoint_sha256": "%s",\n' \
    "$(tr -d '\r\n' < "$OUTPUT/worker-entrypoint.sha256")"
  printf '  "verified_utc": "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '}\n'
} > "$OUTPUT/provenance.json"

echo "PASS Such Moon Launch website build ($OUTPUT)"
