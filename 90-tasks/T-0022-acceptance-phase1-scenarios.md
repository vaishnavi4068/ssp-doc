---
id: T-0022
title: (human-only) Write Phase 1 holdout scenarios: e2e for first service, 10 conversational scenarios with golden OrderInput, 5 chaos, 10 red-team; evaluator posts gate/evaluator
repo: ssp-acceptance
tier: T3
status: ready
specs: [SSP-FAC-002]
depends_on: []
owner: platform
---

## Goal
(human-only) Write Phase 1 holdout scenarios: e2e for first service, 10 conversational scenarios with golden OrderInput, 5 chaos, 10 red-team; evaluator posts gate/evaluator.

## Context pack
- Read: 70-acceptance/README.md; 50-factory/54-gates.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-acceptance`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-acceptance`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Evaluator runs against an ephemeral sandbox namespace and posts symptoms only.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
