---
id: T-0008
title: POST /orders with preview_hash check, order_event stream (SSE via LISTEN/NOTIFY), cancel, signoff, code endpoints
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-API-012, SSP-API-016, SSP-PROD-010..013, SSP-PROD-044..045]
depends_on: [T-0007]
owner: platform
---

## Goal
POST /orders with preview_hash check, order_event stream (SSE via LISTEN/NOTIFY), cancel, signoff, code endpoints.

## Context pack
- Read: 10-product/12-api-spec.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. 409 on stale hash; 202 with order; SSE resumes with Last-Event-ID; cancel allowed only before Included.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
