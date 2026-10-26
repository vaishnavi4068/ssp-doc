---
id: T-0016
title: @ssp/form-renderer: steps, widgets (text, select, radio-cards, number+unit, toggle, table, key-value, derived read-only), Ajv validation, receipt bindings, Storybook
repo: ssp-ui
tier: T2
status: ready
specs: [SSP-UI-040..043, SSP-UI-022]
depends_on: []
owner: platform
---

## Goal
@ssp/form-renderer: steps, widgets (text, select, radio-cards, number+unit, toggle, table, key-value, derived read-only), Ajv validation, receipt bindings, Storybook.

## Context pack
- Read: experiences/portal-ui/16-ui-spec.md §4.3, §5; 10-product/15-catalog-servicespec.md §3-4; 00-constitution/* (always).
- Repo structure and binding notes: experiences/portal-ui/44-ssp-ui-structure.md (for `ssp-ui`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-ui`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Renders gcp.spanner-instance and the unknown-service fixture; unknown widget falls back with badge; 100% typed widget contracts.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
