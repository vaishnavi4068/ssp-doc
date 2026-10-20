---
id: T-0007
title: Implement POST /orders/preflight via approval.Compute (shared with ComputeApproval)
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-API-010, SSP-API-011, SSP-PROD-020, SSP-PROD-030, SSP-PROD-031, SSP-CP-001, SSP-CP-002]
depends_on: [T-0003, T-0004, T-0006]
owner: platform
---

## Goal
Implement POST /orders/preflight via approval.Compute (shared with ComputeApproval).

## Context pack
- Read: 10-product/12-api-spec.md; 10-product/10-product-spec.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Stable preview_hash; policy deny returned as 200 with result=deny; entitlement failure 403; p95 < 300 ms on fixture.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
