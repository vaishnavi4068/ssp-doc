---
id: T-0012
title: tf-runner image (Dockerfile.runner, runner.sh, provider mirror, gcsutil) exactly as 30-infra/tf-worker
repo: ssp-workers
tier: T3
status: ready
specs: [SSP-RUN-001..004]
depends_on: []
owner: platform
---

## Goal
tf-runner image (Dockerfile.runner, runner.sh, provider mirror, gcsutil) exactly as 30-infra/tf-worker.

## Context pack
- Read: 30-infra/33-terraform-worker-on-gke.md §3; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-workers`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-workers`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Image non-root, read-only FS, pinned Terraform and OPA; runner.sh exit codes 0/10/20/30/40 verified with fixtures; no registry egress (tfrc test).
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
