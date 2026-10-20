---
id: T-0009
title: OrderWorkflow with ComputeApproval, gate loop (CR via ServiceNow twin, owner sign-off), hand-off to reconciler, finalize
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-WF-001..004, SSP-WF-010, SSP-WF-011, SSP-PROD-021..024]
depends_on: [T-0008]
owner: platform
---

## Goal
OrderWorkflow with ComputeApproval, gate loop (CR via ServiceNow twin, owner sign-off), hand-off to reconciler, finalize.

## Context pack
- Read: 10-product/13-workflows-spec.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Replay histories recorded for allow, deny, cr_pending paths; cancel honoured before Included; non-retryable errors classified.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
