---
id: T-0014
title: Create ssp-module-gcs-bucket (or spanner) from the module template: module, ServiceSpec, request schema, ui.yaml, pricing, policies, import mapping, tests, release workflow
repo: ssp-module-gcs-bucket
tier: T1
status: ready
specs: [SSP-MOD-001..007, SSP-CAT-001..005, SSP-POL-300..303]
depends_on: []
owner: platform
---

## Goal
Create ssp-module-gcs-bucket (or spanner) from the module template: module, ServiceSpec, request schema, ui.yaml, pricing, policies, import mapping, tests, release workflow.

## Context pack
- Read: 40-repos/45-ssp-module-template.md; 10-product/15-catalog-servicespec.md; 10-product/14-policy-spec.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-module-gcs-bucket`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-module-gcs-bucket`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. catalogctl validate passes; terraform test unit passes with one assertion per MUST guardrail; opa coverage >= 90%; release publishes bundle to ssp-catalog-sandbox and updates index.json.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
