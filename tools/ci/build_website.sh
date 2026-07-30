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
    npm run build | tee "$OUTPUT/test-results/next-build.log"
)

install -m 0644 "$WORK/source/.next/BUILD_ID" "$OUTPUT/BUILD_ID"
install -m 0644 "$WORK/source/package-lock.json" "$OUTPUT/package-lock.json"

(
  cd "$OUTPUT"
  sha256sum BUILD_ID package-lock.json
) > "$OUTPUT/SHA256SUMS"

{
  printf '{\n'
  printf '  "build_id": "%s",\n' "$(tr -d '\r\n' < "$OUTPUT/BUILD_ID")"
  printf '  "node_version": "%s",\n' "$(node --version)"
  printf '  "schema_version": 1,\n'
  printf '  "source_commit": "%s",\n' "$SOURCE_COMMIT"
  printf '  "source_subtree": "website",\n'
  printf '  "verified_utc": "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '}\n'
} > "$OUTPUT/provenance.json"

echo "PASS Such Moon Launch website build ($OUTPUT)"
