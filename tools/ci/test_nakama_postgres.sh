#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

IMAGE="${SML_POSTGRES_TEST_IMAGE:-}"
BUILD_ROOT="${SML_NAKAMA_BUILD_ROOT:-${SML_BUILD_ROOT:-${SML_CI_BUILD_ROOT:-${SUCH_BUILD_ROOT:-$HOME/Build/such-moon-launch}}}}"
SOURCE_COMMIT="$(git rev-parse HEAD)"
RUN_ID="${SML_POSTGRES_TEST_RUN_ID:-local-$(date -u +%Y%m%dT%H%M%SZ)}"
REPORT_ROOT="$BUILD_ROOT/tests/nakama-postgres/$RUN_ID"
CONTAINER="sml-nakama-pg-${SOURCE_COMMIT:0:12}-$$"

if [[ -z "$IMAGE" ]]; then
  echo "FATAL: set SML_POSTGRES_TEST_IMAGE to an immutable PostgreSQL image." >&2
  exit 1
fi
if [[ ! "$IMAGE" =~ @sha256:[0-9a-f]{64}$ ]] &&
   [[ "${SML_POSTGRES_TEST_ALLOW_LOCAL_IMAGE_ID:-0}" != "1" ]]; then
  echo "FATAL: PostgreSQL integration images require a reviewed digest." >&2
  exit 1
fi
if docker ps -a --format '{{.Names}}' | awk -v name="$CONTAINER" '$0 == name { found = 1 } END { exit !found }'; then
  echo "FATAL: disposable PostgreSQL container name is already occupied." >&2
  exit 1
fi

mkdir -p "$REPORT_ROOT"

cleanup_container() {
  if docker ps -a --format '{{.Names}}' |
      awk -v name="$CONTAINER" '$0 == name { found = 1 } END { exit !found }'; then
    docker stop --time 5 "$CONTAINER" >/dev/null
  fi
}
trap cleanup_container EXIT

{
  echo "PostgreSQL test image: $IMAGE"
  docker image inspect --format 'Image ID: {{.Id}}' "$IMAGE"
  docker run --rm --detach \
    --name "$CONTAINER" \
    --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=512m \
    --env POSTGRES_HOST_AUTH_METHOD=trust \
    --env POSTGRES_DB=sml_test \
    "$IMAGE"

  ready=0
  for _attempt in {1..30}; do
    if docker exec "$CONTAINER" pg_isready --quiet --dbname sml_test; then
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "$ready" != "1" ]]; then
    docker logs "$CONTAINER"
    echo "FATAL: disposable PostgreSQL did not become ready." >&2
    exit 1
  fi

  docker cp server/nakama/migrations/001_app_platform_v1.sql \
    "$CONTAINER:/tmp/001_app_platform_v1.sql"
  docker cp server/nakama/migrations/002_friendly_room.sql \
    "$CONTAINER:/tmp/002_friendly_room.sql"
  docker cp server/nakama/test/migrations.integration.sql \
    "$CONTAINER:/tmp/migrations.integration.sql"

  docker exec "$CONTAINER" \
    psql --username postgres --dbname sml_test \
    --file /tmp/001_app_platform_v1.sql
  docker exec "$CONTAINER" \
    psql --username postgres --dbname sml_test \
    --file /tmp/002_friendly_room.sql
  docker exec "$CONTAINER" \
    psql --username postgres --dbname sml_test \
    --file /tmp/002_friendly_room.sql
  docker exec "$CONTAINER" \
    psql --username postgres --dbname sml_test \
    --file /tmp/001_app_platform_v1.sql
  docker exec "$CONTAINER" \
    psql --username postgres --dbname sml_test \
    --file /tmp/migrations.integration.sql

  echo "PASS disposable PostgreSQL migration integration ($REPORT_ROOT)"
} 2>&1 | tee "$REPORT_ROOT/postgres.log"
