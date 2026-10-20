---
id: T-0006
title: Implement /destinations and /destinations/{id}/context from entitlements and tenant/APM records
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-PROD-001..003, SSP-PROD-030]
depends_on: [T-0005]
owner: platform
---

## Goal
Implement /destinations and /destinations/{id}/context from entitlements and tenant/APM records.

## Context pack
- Read: 10-product/12-api-spec.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Buyer sees only entitled tenants; context contains apm, quotas, budget headroom, paused flag.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
