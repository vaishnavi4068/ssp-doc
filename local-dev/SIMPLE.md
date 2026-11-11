# Simplest local start

**Layout** (only requirement):

```text
~/ssp/ssp-doc/     ← you are in local-dev here
~/ssp/ssp-cp/
~/ssp/ssp-workers/
~/ssp/ssp-ui/
```

**Commands:**

```bash
cd ~/ssp/ssp-doc
git checkout cursor/local-dev-compose-b7b7 && git pull

cd local-dev
rm -f .env          # removes wrong SSP_*_REPO paths; recreate only for Sidekick key
git pull origin cursor/local-dev-compose-b7b7   # latest up.sh
./up.sh
```

Open http://localhost:3000

**Sidekick only:** create `.env` with just:

```bash
SSP_ASSISTANT_ENABLED=true
SSP_ASSISTANT_API_KEY=your-key
```

Do **not** put `SSP_CP_REPO=../ssp-cp` in `.env` — siblings are auto-detected.

Stop: `./down.sh`
