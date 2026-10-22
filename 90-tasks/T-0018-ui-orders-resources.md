---
id: T-0018
title: Order tracking page (SSE timeline, run panel, post-build checklist), Fulfilled Orders and Resources tables, resource detail actions
repo: ssp-ui
tier: T2
status: ready
specs: [SSP-PROD-045, SSP-PROD-046, SSP-UI-050]
depends_on: [T-0015]
owner: platform
---

## Goal
Order tracking page (SSE timeline, run panel, post-build checklist), Fulfilled Orders and Resources tables, resource detail actions.

## Context pack
- Read: experiences/portal-ui/16-ui-spec.md §4.4-4.5; 00-constitution/* (always).
- Repo structure and binding notes: experiences/portal-ui/44-ssp-ui-structure.md (for `ssp-ui`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-ui`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. SSE resume works; drift badges carry text; actions call the documented endpoints.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
