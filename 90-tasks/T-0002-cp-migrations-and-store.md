---
id: T-0002
title: Create Postgres migration 0001 from the domain model, sqlc queries and the store package
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-DM-001..006, SSP-DB-001, SSP-DB-004]
depends_on: []
owner: platform
---

## Goal
Create Postgres migration 0001 from the domain model, sqlc queries and the store package.

## Context pack
- Read: 10-product/11-domain-model.md; 40-repos/42-ssp-cp-structure.md; 30-infra/34-control-plane-postgres.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. `make generate` produces sqlc code with no diff; `goose up` then `goose down` succeed on a clean testcontainers Postgres.
2. `TransitionOrder` inserts the order_event in the same transaction (unit test SSP-DM-001).
3. order_event and audit_event are partitioned by month; a test inserts across two months.
4. No column can hold secrets: gate/secrets corpus against fixtures passes.
5. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
