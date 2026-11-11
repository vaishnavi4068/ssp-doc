# Portable local SPP (any Mac / Linux laptop)

**Requirements:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose v2), `git`, ~8 GB RAM.

## Brand-new machine (one flow)

```bash
mkdir -p ~/ssp && cd ~/ssp
git clone https://github.com/vaishnavi4068/ssp-doc.git
cd ssp-doc
git fetch origin cursor/local-dev-compose-b7b7
git checkout cursor/local-dev-compose-b7b7

cd local-dev
chmod +x install.sh bootstrap.sh up.sh down.sh verify.sh
./install.sh --bootstrap
```

`install.sh --bootstrap` clones/updates **ssp-cp**, **ssp-workers**, **ssp-ui** as siblings of **ssp-doc**, then runs Docker Compose.

Open http://localhost:3000

## Already have ~/ssp layout

```bash
cd ~/ssp/ssp-doc/local-dev
./install.sh
```

No `.env` required. Optional Sidekick: copy `.env.example` → `.env`, set `SSP_ASSISTANT_*` only.

## Layout (fixed convention)

```text
~/ssp/                    ← SPP_LOCAL_ROOT (any path works if siblings stay together)
  ssp-doc/local-dev/      ← run scripts here
  ssp-cp/
  ssp-workers/
  ssp-ui/
```

Custom root:

```bash
export SPP_LOCAL_ROOT=/path/to/workspace
./bootstrap.sh "$SPP_LOCAL_ROOT"
cd "$SPP_LOCAL_ROOT/ssp-doc/local-dev" && ./up.sh
```

## Verify / stop

```bash
./verify.sh
./down.sh          # stop
./down.sh -v       # stop + wipe local Postgres volume
```

## After GitHub merges (simpler branches)

When [ssp-doc#8](https://github.com/vaishnavi4068/ssp-doc/pull/8), [ssp-cp#11](https://github.com/vaishnavi4068/ssp-cp/pull/11), [ssp-ui#4](https://github.com/vaishnavi4068/ssp-ui/pull/4), [ssp-workers#6](https://github.com/vaishnavi4068/ssp-workers/pull/6) are on `main`:

```bash
export SPP_LOCAL_USE_MAIN_ONLY=true
./bootstrap.sh ~/ssp
```

## Copying to teammates

Share this file + repo URLs. Do **not** copy `.env` (secrets). Data lives in Docker volume `spp-local_spp-pgdata` on each machine.
