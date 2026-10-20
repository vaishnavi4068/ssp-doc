---
id: T-0001
title: Write the decided ADRs (G-0001..G-0005, C-GCP-0001, C-GCP-0002, A-0001..A-0003, B-0007) from the decisions register using the ADR template
repo: ssp-doc
tier: T0
status: ready
specs: [SSP-PRIN-001..012]
depends_on: []
owner: platform
---

## Goal
Write the decided ADRs (G-0001..G-0005, C-GCP-0001, C-GCP-0002, A-0001..A-0003, B-0007) from the decisions register using the ADR template.

## Context pack
- Read: 00-constitution/02-decisions-register.md; 60-adr/README.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-doc`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-doc`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Each ADR has frontmatter, Goal, Context, Decision, Requirements table with Verify-by for every MUST, Consequences, Open questions.
2. Requirement IDs follow REQ-<ADR>-<nn>; no duplicates (gate/ids).
3. Each ADR links the decision row (D-xx) it records; status accepted; owner and mailbox filled from the register.
4. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
