---
id: T-0004
title: Embedded OPA request-stage evaluation, baseline platform rules SSP-POL-1xx with tests, bundle fetch by digest
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-POL-001, SSP-POL-100..151, SSP-POL-300..303]
depends_on: [T-0003]
owner: platform
---

## Goal
Embedded OPA request-stage evaluation, baseline platform rules SSP-POL-1xx with tests, bundle fetch by digest.

## Context pack
- Read: 10-product/14-policy-spec.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. opa test coverage >= 90% on policy/platform.
2. Deny on missing cost_center label; gate cr_required for prod change; budget_exceeded gate computed.
3. Decision document shape matches 14 §2 exactly (golden JSON test).
4. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
