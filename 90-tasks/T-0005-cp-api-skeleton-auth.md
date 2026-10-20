---
id: T-0005
title: oapi-codegen strict server from 12-openapi.yaml, chi wiring, middleware (request id, OTel, JWT auth, persona, entitlement, idempotency, problem details), /healthz /readyz
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-API-001..005, SSP-PROD-001..003, SSP-PROD-100..101]
depends_on: [T-0002]
owner: platform
---

## Goal
oapi-codegen strict server from 12-openapi.yaml, chi wiring, middleware (request id, OTel, JWT auth, persona, entitlement, idempotency, problem details), /healthz /readyz.

## Context pack
- Read: 10-product/12-api-spec.md; 10-product/12-openapi.yaml; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. All operations return 501 stubs except health; JWT with bad audience -> 401 problem; replayed Idempotency-Key returns cached response with header.
2. oasdiff against ssp-doc copy shows identical spec.
3. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
