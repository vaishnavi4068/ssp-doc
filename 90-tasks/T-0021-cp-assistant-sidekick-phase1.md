---
id: T-0021
title: Assistant gateway: context assembly, router, knowledge path via Grounded interface (contextual/vertexrag), action path with preflight cards, SSE events; Sidekick panel wiring in ssp-ui
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-CHAT-001..003, SSP-CHAT-010..014, SSP-CHAT-020..023, SSP-CHAT-030..031, SSP-UI-030]
depends_on: [T-0007, T-0015]
owner: platform
---

## Goal
Assistant gateway: context assembly, router, knowledge path via Grounded interface (contextual/vertexrag), action path with preflight cards, SSE events; Sidekick panel wiring in ssp-ui.

## Context pack
- Read: 10-product/17-conversational-provisioning-spec.md; 10-product/12-api-spec.md (assistant); 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Provision intent for a Tier 1 Spanner yields a preflight card with multi-region derived and citations; no Place order without preview_hash; injected instruction in a resource name produces no tool call; unsourced policy question returns abstention with ticket link.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
