---
id: T-0020
title: Migration wizard steps 1-6 against ImportWorkflow: source, inventory, mapping editor (schema-aware), onboard, dry-run diff, reconcile differences
repo: ssp-migrate
tier: T2
status: ready
specs: [SSP-MIG-001..008, SSP-WF-050..052]
depends_on: []
owner: platform
---

## Goal
Migration wizard steps 1-6 against ImportWorkflow: source, inventory, mapping editor (schema-aware), onboard, dry-run diff, reconcile differences.

## Context pack
- Read: 20-apps/22-migration-app-spec.md; 10-product/13-workflows-spec.md §6; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-migrate`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-migrate`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Fixture 1.0 project with 300 assets maps with suggested services; dry-run with a non-zero diff blocks execute and shows choices; execute is disabled until zero_changes.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
