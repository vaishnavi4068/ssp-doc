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

# Sibling layout: ~/ssp/{ssp-doc,ssp-cp,ssp-workers,ssp-ui}
WORKSPACE="$(cd "$ROOT/.." && pwd)"

is_git_repo() {
  git -C "$1" rev-parse --is-inside-work-tree &>/dev/null
}

expand_home() {
  local p="$1"
  if [[ "$p" == "~/"* ]]; then
    p="${HOME}/${p:2}"
  elif [[ "$p" == "~" ]]; then
    p="$HOME"
  fi
  printf '%s' "$p"
}

# Drop invalid paths from .env so siblings auto-detect (common typo: wrong /Users/... in .env)
for _var in SSP_CP_REPO SSP_WORKERS_REPO SSP_UI_REPO; do
  _p="${!_var:-}"
  if [[ -n "$_p" ]]; then
    _p="$(expand_home "$_p")"
    export "$_var=$_p"
    if ! is_git_repo "$_p"; then
      echo "note: ignoring $_var=$_p (not a git repo)" >&2
      unset "$_var"
    fi
  fi
done

resolve_repo() {
  local var="$1" name="$2" folder="$3"
  local candidates=()
  local path="${!var:-}"
  [[ -n "$path" ]] && candidates+=("$path")
  candidates+=("$WORKSPACE/$folder" "$ROOT/../$folder")

  local resolved=""
  for c in "${candidates[@]}"; do
    [[ -z "$c" ]] && continue
    if [[ "$c" == /* ]]; then
      [[ -d "$c" ]] || continue
      resolved="$(cd "$c" && pwd)"
    elif [[ -d "$ROOT/$c" ]]; then
      resolved="$(cd "$ROOT/$c" && pwd)"
    elif [[ -d "$c" ]]; then
      resolved="$(cd "$c" && pwd)"
    else
      continue
    fi
    if is_git_repo "$resolved"; then
      export "$var"="$resolved"
      return 0
    fi
  done
  echo "error: could not find $name. Put clones here (no .env paths needed):" >&2
  echo "  $WORKSPACE/$folder" >&2
  echo "Run: cd $WORKSPACE/$folder && pwd && git status" >&2
  exit 1
}

resolve_repo SSP_CP_REPO ssp-cp ssp-cp
resolve_repo SSP_WORKERS_REPO ssp-workers ssp-workers
resolve_repo SSP_UI_REPO ssp-ui ssp-ui

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
