---
name: spp-local-setup
description: Build and run the full SPP stack on localhost with Docker Compose—local Postgres (spp_platform), local Temporal, ssp-cp, ssp-workers, ssp-ui. Use when the user asks for local setup, laptop dev, E2E on localhost, docker compose, or pointing Claude Code at this repo for a runnable environment. Never use Cloud SQL or remote databases for this workflow.
---

# SPP local laptop setup (all infra on localhost)

This repository ships a **self-contained** dev stack under `local-dev/`. Every persistence layer runs **on the machine**:

| Service | Local? | How |
|---------|--------|-----|
| **Postgres** (`spp_platform`) | Yes | `postgres:16-alpine` container, port `localhost:5432` |
| **Temporal** | Yes | `temporalio/auto-setup` using the **same local Postgres** container |
| **Control plane DB URL** | Local only | `postgres://postgres:postgres@postgres:5432/spp_platform` inside Compose; `localhost:5432` from the host |

Do **not** point `SSP_DATABASE_URL` at Cloud SQL, AlloyDB, or any shared nonprod DB for local E2E. If the user pasted a cloud URL, replace it with the local URL above and use Compose.

## Preconditions

1. **Docker Engine 24+** with Compose v2 (`docker compose`).
2. Sibling git clones (or paths in `local-dev/.env`):
   - `ssp-cp`
   - `ssp-workers` (Go worker `Dockerfile` on branch/main you build from)
   - `ssp-ui`

```text
workspace/
  ssp-doc/      ← start Claude Code here (skill loads from .claude/skills/)
  ssp-cp/
  ssp-workers/
  ssp-ui/
```

## Build and start (default path)

From the repo root:

```bash
cd local-dev
cp -n .env.example .env    # optional: absolute SSP_*_REPO paths
chmod +x up.sh down.sh
./up.sh
```

`up.sh` resolves sibling repos, runs `docker compose up -d --build`, runs migrations against **local** Postgres, then starts API, worker, and portal.

## Verify

Wait until containers are up, then:

```bash
curl -sf http://localhost:8080/api/v1/healthz
docker compose -f local-dev/docker-compose.yml ps
docker compose -f local-dev/docker-compose.yml exec postgres pg_isready -U postgres -d spp_platform
```

Open **http://localhost:3000** (portal). Temporal UI: **http://localhost:8088**.

## Smoke test (API)

```bash
curl -s -X POST http://localhost:8080/api/v1/submissions \
  -H 'Content-Type: application/json' \
  -H 'X-SSP-User: requester' \
  -d '{"kind":"gcs_bucket","metadata":{"apm_id":"apm12345","project_id":"local-dev","environment":"nonprod","lob":"spp","owner":"bucket.owner@example.com"},"spec":{"name":"spp-nonprod-orders-landing-a1b2","location":"us-east1"}}'
```

## Stop / reset

```bash
cd local-dev
./down.sh       # stop containers
./down.sh -v      # stop and delete local Postgres volume (fresh DB)
```

## When the user works only in `ssp-cp` or another product repo

Still drive setup from **`ssp-doc/local-dev`**. Set in `local-dev/.env`:

```bash
SSP_CP_REPO=/absolute/path/to/ssp-cp
SSP_WORKERS_REPO=/absolute/path/to/ssp-workers
SSP_UI_REPO=/absolute/path/to/ssp-ui
```

## Host-native API (optional; DB stays local)

Infra in Docker, API on host — Postgres remains the **local** container:

```bash
cd local-dev
docker compose up -d postgres temporal temporal-ui
export SSP_DATABASE_URL=postgres://postgres:postgres@localhost:5432/spp_platform?sslmode=disable
cd "$SSP_CP_REPO" && go run ./cmd/migrate up
SSP_OPA_SKIP=true SSP_AUTH_DISABLED=true go run ./cmd/api
```

## Optional: Sidekick chat (LLM)

Put the provider key only in `local-dev/.env` (never in git or chat):

```bash
SSP_ASSISTANT_ENABLED=true
SSP_ASSISTANT_API_KEY=<user supplies in .env>
SSP_ASSISTANT_PROVIDER=anthropic   # or openai
```

Rebuild `ssp-cp`, open portal → **Sidekick** button (bottom right). API routes: `/v1/assistant/conversations` and `.../messages`.

## Out of scope for this stack

- Real Terraform apply / GKE (worker uses memory activities).
- OPA sidecar (skipped via `SSP_OPA_SKIP=true`).
- Full agentic submit/approve tools (chat is Q&A only locally).
- Terraform module repos: run `terraform test` on the host separately.

## Reference

Full URLs, troubleshooting, and UI dev-server option: `local-dev/README.md`.
