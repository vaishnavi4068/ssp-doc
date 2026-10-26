---
id: T-0017
title: Configure & Checkout page with stepper, numbered fields with mono keys, sticky Order Summary (Summary|Code), debounced preflight, Place order with preview_hash
repo: ssp-ui
tier: T2
status: ready
specs: [SSP-UI-020..021, SSP-PROD-041..044, SSP-UIR-002]
depends_on: [T-0015, T-0016]
owner: platform
---

## Goal
Configure & Checkout page with stepper, numbered fields with mono keys, sticky Order Summary (Summary|Code), debounced preflight, Place order with preview_hash.

## Context pack
- Read: experiences/portal-ui/16-ui-spec.md §4.3; 00-constitution/* (always).
- Repo structure and binding notes: experiences/portal-ui/44-ssp-ui-structure.md (for `ssp-ui`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-ui`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Receipt matches server preflight; 409 path re-confirms; visual snapshots match the prototype layout in light and dark.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
