#!/usr/bin/env bash
# Preferred entrypoint: bootstrap if needed, then start Docker stack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$ROOT/../.." && pwd)"

need_bootstrap=false
for repo in ssp-cp ssp-workers ssp-ui; do
  if [[ ! -d "$WORKSPACE/$repo/.git" ]] || ! git -C "$WORKSPACE/$repo" rev-parse --is-inside-work-tree &>/dev/null; then
    need_bootstrap=true
    break
  fi
done

if [[ "${1:-}" == "--bootstrap" ]]; then
  need_bootstrap=true
fi

if [[ "$need_bootstrap" == true ]]; then
  echo "Running bootstrap for $WORKSPACE ..."
  "$ROOT/bootstrap.sh" "$WORKSPACE"
fi

if ! command -v docker >/dev/null; then
  echo "error: install Docker Desktop and ensure 'docker' works" >&2
  exit 1
fi

exec "$ROOT/up.sh"
