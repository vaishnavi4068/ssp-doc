# Local laptop stack (Docker Compose)

One-command dev environment for **Postgres**, **Temporal**, **ssp-cp** (Go API), **ssp-workers** (Go workflows, memory Terraform), and **ssp-ui** (portal). Use this when porting SPP to company laptops or doing end-to-end tests without GKE.

**Local-only data plane:** Postgres runs in Docker on `localhost:5432` (volume `spp-pgdata`). Temporal uses that same local Postgres instance. The control plane never talks to Cloud SQL in this profile.

**Claude Code:** project skill **`.claude/skills/spp-local-setup/SKILL.md`** — invoke `/spp-local-setup` or ask to build local E2E; the agent should run `local-dev/up.sh`, not cloud DB URLs.

## Prerequisites

- Docker Engine 24+ with Compose v2 (`docker compose`)
- ~8 GB RAM free for images
- Git clones of product repos as **siblings** of `ssp-doc`:

```text
your-workspace/
  ssp-doc/          ← this repo (local-dev lives here)
  ssp-cp/
  ssp-workers/
  ssp-ui/
```

Or copy `.env.example` → `.env` and set `SSP_CP_REPO`, `SSP_WORKERS_REPO`, `SSP_UI_REPO` to absolute paths.

## Quick start

```bash
cd ssp-doc/local-dev
cp -n .env.example .env   # optional
chmod +x up.sh down.sh
./up.sh
```

Open **http://localhost:3000** (portal). Submit a GCS bucket request; approve via API or portal when auth is enabled in your branch.

| URL | Purpose |
|-----|---------|
| http://localhost:3000 | Portal (end user) |
| http://localhost:8080 | Control plane API (`/api/v1/*`, `/healthz`) |
| http://localhost:8088 | Temporal Web UI |
| localhost:5432 | Postgres (`spp_platform` / `postgres` / `postgres`) |

Stop everything:

```bash
./down.sh
```

Remove DB volume: `./down.sh -v`

## What is (and isn’t) included

| Component | Local behavior |
|-----------|----------------|
| **Postgres** | Real DB; migrations from `ssp-cp` `db/migrations` |
| **Temporal** | Real server; namespace `default`; queue `spp-gcs-provisioning` |
| **OPA** | Skipped (`SSP_OPA_SKIP=true`) — fast laptop setup |
| **Auth** | Disabled (`SSP_AUTH_DISABLED=true`) — use `X-SSP-User` header |
| **Terraform apply** | **Not** run — worker uses memory activities (no K8s/GCS) |
| **Terraform CLI** | Not in compose; module repos tested with `terraform test` on the host |
| **Sidekick chat (portal)** | Needs `SSP_ASSISTANT_ENABLED=true` + `SSP_ASSISTANT_API_KEY` in `.env`, then **Sidekick** button on http://localhost:3000 (calls `ssp-cp` `/v1/assistant/*`; key stays on server) |

To exercise **real** plan/apply you still need GKE + runner image (see `ssp-workers` README). This stack validates **intake → approval → Temporal dispatch → worker workflow** on a laptop.

### Enable Sidekick (local LLM)

1. Copy `.env.example` → `.env` if you have not already.
2. Set (do **not** commit):

   ```bash
   SSP_ASSISTANT_ENABLED=true
   SSP_ASSISTANT_API_KEY=sk-ant-...   # or OPENAI via SSP_ASSISTANT_PROVIDER=openai
   ```

3. Rebuild API: `docker compose up -d --build ssp-cp` (or full `./up.sh`).

This is a **local-dev slice** of SSP-CHAT (Q&A only—no tool submit/approve yet). Production uses Vertex/enterprise endpoints per spec.

## Optional: UI dev server instead of container

```bash
# Terminal 1 — infra only
docker compose up -d postgres temporal temporal-ui migrate ssp-cp ssp-workers

# Terminal 2 — hot reload UI
cd ../ssp-ui
VITE_SPP_API_URL=http://localhost:8080 npm run dev
```

## Optional: host-native API (no API container rebuild)

```bash
docker compose up -d postgres temporal temporal-ui
export SSP_DATABASE_URL=postgres://postgres:postgres@localhost:5432/spp_platform?sslmode=disable
cd ../ssp-cp && go run ./cmd/migrate up && SSP_OPA_SKIP=true SSP_AUTH_DISABLED=true go run ./cmd/api
```

## Troubleshooting

- **Build fails** — confirm the three repo paths in `.env` and that `main` builds (`go test ./...` in cp/workers).
- **Portal cannot reach API** — `SPP_API_URL` must be `http://localhost:8080` (browser calls host, not Docker DNS).
- **Temporal workflows idle** — check `docker compose logs ssp-workers`; worker must share namespace `default` and queue `spp-gcs-provisioning` with API env in compose file.
- **Port in use** — set `SSP_API_PORT`, `SSP_PORTAL_PORT`, `POSTGRES_PORT` in `.env`.

## Files

| File | Role |
|------|------|
| `docker-compose.yml` | Service definitions |
| `up.sh` / `down.sh` | Wrappers |
| `init/01-spp-platform.sql` | Creates `spp_platform` database |
| `.env.example` | Repo path overrides |
