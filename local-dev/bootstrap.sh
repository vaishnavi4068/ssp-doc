#!/usr/bin/env bash
# Clone or update all SPP repos for local Docker dev. Idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG="${SPP_GITHUB_ORG:-vaishnavi4068}"
TARGET="${1:-${SPP_LOCAL_ROOT:-$(cd "$ROOT/../.." && pwd)}}"

REPOS=(ssp-doc ssp-cp ssp-workers ssp-ui)
# After feature PRs merge to main, set SPP_LOCAL_USE_MAIN_ONLY=true to skip branch pins.
USE_MAIN_ONLY="${SPP_LOCAL_USE_MAIN_ONLY:-false}"

branch_for() {
  local name="$1"
  if [[ "$USE_MAIN_ONLY" == "true" ]]; then
    echo main
    return
  fi
  case "$name" in
    ssp-doc) echo cursor/local-dev-compose-b7b7 ;;
    ssp-cp) echo cursor/local-assistant-b7b7 ;;
    ssp-ui) echo cursor/local-assistant-ui-b7b7 ;;
    ssp-workers) echo cursor/go-workers-b7b7 ;;
    *) echo main ;;
  esac
}

echo "SPP local bootstrap → $TARGET"
mkdir -p "$TARGET"

if ! command -v git >/dev/null; then
  echo "error: git is required" >&2
  exit 1
fi

for name in "${REPOS[@]}"; do
  dest="$TARGET/$name"
  url="https://github.com/${ORG}/${name}.git"
  branch="$(branch_for "$name")"

  if [[ -d "$dest/.git" ]]; then
    echo "== $name (pull)"
    git -C "$dest" fetch origin
  else
    echo "== $name (clone)"
    git clone "$url" "$dest"
    git -C "$dest" fetch origin
  fi

  if git -C "$dest" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git -C "$dest" checkout -B "$branch" "origin/$branch"
    git -C "$dest" pull origin "$branch"
  elif git -C "$dest" show-ref --verify --quiet refs/remotes/origin/main; then
    echo "note: $name: branch $branch missing, using main"
    git -C "$dest" checkout main
    git -C "$dest" pull origin main
  fi

  if [[ "$name" == "ssp-doc" ]] && [[ ! -f "$dest/local-dev/up.sh" ]]; then
    echo "error: $name has no local-dev/up.sh — checkout a branch that includes local-dev" >&2
    exit 1
  fi
done

if ! command -v docker >/dev/null; then
  echo "warning: docker not in PATH — install Docker Desktop before ./up.sh" >&2
else
  docker compose version >/dev/null 2>&1 || echo "warning: need Docker Compose v2" >&2
fi

cat <<EOF

Repos ready under: $TARGET

Next:
  cd $TARGET/ssp-doc/local-dev
  ./install.sh        # starts stack (or: ./up.sh)

EOF
