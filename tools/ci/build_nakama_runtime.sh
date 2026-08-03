#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

BUILD_ROOT="${SML_NAKAMA_BUILD_ROOT:-${SML_BUILD_ROOT:-${SML_CI_BUILD_ROOT:-${SUCH_BUILD_ROOT:-$HOME/Build/such-moon-launch}}}}"
SOURCE_COMMIT="$(git rev-parse HEAD)"

[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40,64}$ ]] || {
  echo "FATAL: Nakama source commit must be a full lowercase Git object ID." >&2
  exit 1
}

RUNTIME_INPUT_STATUS="$(git status --porcelain --untracked-files=all -- \
  config/app-platform-v1.json \
  config/commerce-catalog-v1.json \
  server/nakama \
  tools/ci/build_nakama_runtime.sh \
  tools/ci/render_nakama_artifacts.mjs)"
if [[ -n "$RUNTIME_INPUT_STATUS" ]]; then
  echo "FATAL: commit the runtime inputs before producing immutable artifacts." >&2
  exit 1
fi

WORK_PARENT="$BUILD_ROOT/cache/nakama-work"
NPM_CACHE="$BUILD_ROOT/cache/npm"
OUTPUT="$BUILD_ROOT/nakama/$SOURCE_COMMIT"
mkdir -p "$WORK_PARENT" "$NPM_CACHE" "$OUTPUT/test-results"
WORK="$(mktemp -d "$WORK_PARENT/$SOURCE_COMMIT.XXXXXX")"
STAGE="$WORK/artifact"
mkdir -p "$STAGE/test-results" "$WORK/src"

cleanup_work() {
  if [[ -n "${WORK:-}" && "$WORK" == "$WORK_PARENT/"* ]]; then
    rm -rf -- "$WORK"
  fi
}
trap cleanup_work EXIT

cp server/nakama/package.json server/nakama/package-lock.json \
  server/nakama/tsconfig.json "$WORK/"
cp server/nakama/src/*.ts "$WORK/src/"

(
  cd "$WORK"
  npm_config_cache="$NPM_CACHE" \
    npm ci --ignore-scripts --no-audit --no-fund \
    > "$STAGE/test-results/npm-ci.log"
  ./node_modules/.bin/tsc --project tsconfig.json \
    --outFile "$STAGE/index.js" \
    > "$STAGE/test-results/typescript.log"
)

MIGRATIONS=("$ROOT"/server/nakama/migrations/*.sql)
if [[ ! -f "${MIGRATIONS[0]}" ]]; then
  echo "FATAL: no ordered Nakama migrations found." >&2
  exit 1
fi
awk 'FNR == 1 && NR != 1 { print "" } { print }' \
  "${MIGRATIONS[@]}" > "$STAGE/migrations.sql"

NAKAMA_RUNTIME_ARTIFACT="$STAGE/index.js" \
NAKAMA_MIGRATION_ARTIFACT="$STAGE/migrations.sql" \
  node --test server/nakama/test/*.test.js \
  > "$STAGE/test-results/runtime.tap"

node tools/ci/render_nakama_artifacts.mjs \
  --artifact-dir "$STAGE" \
  --source-commit "$SOURCE_COMMIT"

install -m 0644 "$STAGE/index.js" "$OUTPUT/index.js"
install -m 0644 "$STAGE/migrations.sql" "$OUTPUT/migrations.sql"
install -m 0644 "$STAGE/runtime-manifest.json" \
  "$OUTPUT/runtime-manifest.json"
install -m 0644 "$STAGE/SHA256SUMS" "$OUTPUT/SHA256SUMS"
for result in "$STAGE"/test-results/*; do
  install -m 0644 "$result" "$OUTPUT/test-results/$(basename "$result")"
done

echo "PASS Such Moon Launch Nakama runtime ($OUTPUT)"
