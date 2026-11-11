# Local E2E ready checklist

Use this before your first laptop test. (This cloud agent cannot run Docker here.)

## 1. Branches (until PRs are merged)

| Repo | Branch | PR |
|------|--------|-----|
| `ssp-doc` | `cursor/local-dev-compose-b7b7` | [#8](https://github.com/vaishnavi4068/ssp-doc/pull/8) |
| `ssp-cp` | `cursor/local-assistant-b7b7` | [#11](https://github.com/vaishnavi4068/ssp-cp/pull/11) |
| `ssp-ui` | `cursor/local-assistant-ui-b7b7` | [#4](https://github.com/vaishnavi4068/ssp-ui/pull/4) |
| `ssp-workers` | `cursor/go-workers-b7b7` (or `main` if Go Dockerfile merged) | [#6](https://github.com/vaishnavi4068/ssp-workers/pull/6) |

```bash
# example: update siblings
for repo in ssp-doc ssp-cp ssp-ui ssp-workers; do
  cd ../$repo && git fetch origin && git checkout <branch-above> && git pull
done
```

## 2. Environment

```bash
cd ssp-doc/local-dev
cp -n .env.example .env
# edit .env — sibling paths if needed, and:
#   SSP_ASSISTANT_ENABLED=true
#   SSP_ASSISTANT_API_KEY=<your key>   # never commit
```

## 3. Start

```bash
chmod +x up.sh down.sh
./up.sh
```

Wait ~2–5 minutes for first image build.

## 4. Smoke tests

| Check | Command / URL |
|-------|----------------|
| API | `curl -sf http://localhost:8080/api/v1/healthz` |
| Portal | http://localhost:3000 |
| Sidekick | Open **Sidekick** (bottom-right), send “What is the GCS bucket name pattern?” |
| Submit (optional) | GCS form → submit, or curl in `up.sh` footer |
| Temporal UI | http://localhost:8088 |
| Local Postgres | `docker compose exec postgres psql -U postgres -d spp_platform -c 'select 1'` |

## 5. Stop

```bash
./down.sh
```

Fresh DB: `./down.sh -v`
