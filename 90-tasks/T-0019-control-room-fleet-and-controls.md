---
id: T-0019
title: Control room shell, Fleet page, Tenants, Runs with log viewer, pause/resume with blast-radius dialog, two-person kill switch
repo: ssp-control-room
tier: T2
status: ready
specs: [SSP-CR-001, SSP-CR-010..016, SSP-API-013]
depends_on: []
owner: platform
---

## Goal
Control room shell, Fleet page, Tenants, Runs with log viewer, pause/resume with blast-radius dialog, two-person kill switch.

## Context pack
- Read: 20-apps/21-control-room-spec.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-control-room`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-control-room`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Fleet tiles refresh every 15 s; kill switch flow requires two operators; cached snapshot shown when API is degraded.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
