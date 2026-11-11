# Simplest local start

**New laptop:** see **[PORTABLE.md](PORTABLE.md)** — one command: `./install.sh --bootstrap`

**Daily use** (repos already under `~/ssp`):

```bash
cd ~/ssp/ssp-doc/local-dev
./install.sh
```

Open http://localhost:3000 · stop: `./down.sh` · check: `./verify.sh`

**Sidekick only:** `.env` with `SSP_ASSISTANT_ENABLED=true` and `SSP_ASSISTANT_API_KEY=...` (never `SSP_*_REPO` lines).
