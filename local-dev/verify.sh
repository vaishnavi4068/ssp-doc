#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

API_PORT="${SSP_API_PORT:-8080}"
PORTAL_PORT="${SSP_PORTAL_PORT:-3000}"
TEMPORAL_UI_PORT="${TEMPORAL_UI_PORT:-8088}"

fail=0
check() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "ok  $name"
  else
    echo "FAIL $name"
    fail=1
  fi
}

check "postgres" "docker compose exec -T postgres pg_isready -U postgres -d spp_platform"
check "api" "curl -sf http://localhost:${API_PORT}/api/v1/healthz"
check "portal" "curl -sf -o /dev/null http://localhost:${PORTAL_PORT}/"
check "temporal-ui" "curl -sf -o /dev/null http://localhost:${TEMPORAL_UI_PORT}/"

exit "$fail"
