---
id: T-0011
title: tf-worker: RunTerraform activity with deterministic Job names, re-attach, polling with heartbeats, result.json as source of truth, cancellation cleanup, metrics
repo: ssp-workers
tier: T2
status: ready
specs: [SSP-WK-001..003, SSP-RUN-005]
depends_on: []
owner: platform
---

## Goal
tf-worker: RunTerraform activity with deterministic Job names, re-attach, polling with heartbeats, result.json as source of truth, cancellation cleanup, metrics.

## Context pack
- Read: 30-infra/33-terraform-worker-on-gke.md; 40-repos/43-ssp-workers-structure.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-workers`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-workers`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. kind integration test: kill worker mid-run -> same Job name, no second Job; cancel deletes Job; LockError retryable, TerraformError not.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
