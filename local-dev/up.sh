#!/usr/bin/env bash
# Start the full local SSP stack (infra + Go services). Requires Docker Compose v2.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

resolve_repo() {
  local var="$1" name="$2" default_rel="$3"
  local path="${!var:-}"
  if [[ -z "$path" ]]; then
    if [[ -d "$ROOT/$default_rel" ]]; then
      path="$(cd "$ROOT/$default_rel" && pwd)"
    else
      echo "error: set $var to your $name checkout (see .env.example)" >&2
      exit 1
    fi
  elif [[ "$path" != /* ]]; then
    if [[ ! -d "$ROOT/$path" ]] && [[ ! -d "$path" ]]; then
      echo "error: $var=$path is not a directory (cwd=$ROOT)" >&2
      exit 1
    fi
    path="$(cd "$ROOT/$path" 2>/dev/null && pwd)" || path="$(cd "$path" && pwd)"
  fi
  if [[ ! -e "$path/.git" ]]; then
    echo "error: $var=$path is not a git checkout (missing .git — re-clone with git clone)" >&2
    exit 1
  fi
  export "$var"="$path"
}

resolve_repo SSP_CP_REPO ssp-cp ../ssp-cp
resolve_repo SSP_WORKERS_REPO ssp-workers ../ssp-workers
resolve_repo SSP_UI_REPO ssp-ui ../ssp-ui

export SSP_CP_REPO SSP_WORKERS_REPO SSP_UI_REPO

echo "Using:"
echo "  SSP_CP_REPO=$SSP_CP_REPO"
echo "  SSP_WORKERS_REPO=$SSP_WORKERS_REPO"
echo "  SSP_UI_REPO=$SSP_UI_REPO"

docker compose up -d --build

API_PORT="${SSP_API_PORT:-8080}"
PORTAL_PORT="${SSP_PORTAL_PORT:-3000}"
TEMPORAL_UI_PORT="${TEMPORAL_UI_PORT:-8088}"

cat <<EOF

SPP local stack is up.

  Portal (end user):     http://localhost:${PORTAL_PORT}
  Control plane API:     http://localhost:${API_PORT}/api/v1/healthz
  Temporal Web UI:       http://localhost:${TEMPORAL_UI_PORT}
  Postgres:              localhost:${POSTGRES_PORT:-5432}  db=spp_platform  user=postgres

Auth is disabled for local dev (SSP_AUTH_DISABLED). OPA is skipped (SSP_OPA_SKIP).
Workers use in-memory Terraform (no real GKE Jobs).

Smoke test — GCS bucket request from the portal, or:

  curl -s -X POST http://localhost:${API_PORT}/api/v1/submissions \\
    -H 'Content-Type: application/json' \\
    -H 'X-SSP-User: requester' \\
    -d '{"kind":"gcs_bucket","metadata":{"apm_id":"apm12345","project_id":"local-dev","environment":"nonprod","lob":"spp","owner":"bucket.owner@example.com"},"spec":{"name":"spp-nonprod-orders-landing-a1b2","location":"us-east1"}}'

Stop:  $ROOT/down.sh
Logs:  docker compose -f $ROOT/docker-compose.yml logs -f ssp-cp ssp-workers ssp-ui

EOF
