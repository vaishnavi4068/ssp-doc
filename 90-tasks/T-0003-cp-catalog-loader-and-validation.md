---
id: T-0003
title: Catalog bundle loader from GCS index.json, ServiceSpec/schema validation, derive and guardrail evaluation, pricing evaluator, code view renderer
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-CAT-001..005, SSP-CP-002, SSP-CP-003]
depends_on: [T-0002]
owner: platform
---

## Goal
Catalog bundle loader from GCS index.json, ServiceSpec/schema validation, derive and guardrail evaluation, pricing evaluator, code view renderer.

## Context pack
- Read: 10-product/15-catalog-servicespec.md; 10-product/15-service-spec.schema.json; 40-repos/42-ssp-cp-structure.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Loads the fixture bundle gcp.spanner-instance@1.2.0 and rejects three malformed fixtures with precise errors.
2. derive rules produce multi-region for tier 1; guardrails inject labels and CMEK; deny rule fires for PU=150.
3. Pricing evaluator returns the receipt lines; code view equals render.RootModule output for one instance.
4. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
