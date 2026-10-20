---
id: T-0015
title: App shell (top bar with destination selector, search ⌘K, Sidekick button, orders, theme), left nav with frequent SKUs, Storefront Home from catalog and destinations
repo: ssp-ui
tier: T2
status: ready
specs: [SSP-UI-001..005, SSP-UI-010, SSP-UIR-001, SSP-UIR-004]
depends_on: []
owner: platform
---

## Goal
App shell (top bar with destination selector, search ⌘K, Sidekick button, orders, theme), left nav with frequent SKUs, Storefront Home from catalog and destinations.

## Context pack
- Read: 10-product/16-ui-spec.md §3-4.1; 40-repos/44-ssp-ui-structure.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-ui`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-ui`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Home renders the sandbox catalog and destinations; command palette opens with ⌘K and finds SKUs/orders; tokens only from @ssp/ui; a11y >= 95.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
