# ADR-XXXX: [Short Descriptive Title]

- **ADR ID:** ADR-XXXX
- **Level:** [global | business-process | endpoint-service | per-cloud (gcp) | automation]
- **Status:** Proposed
- **Owner:** TBD (Shared Mailbox: `<team-mailbox@tbd>`, Named Owner: `TBD`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], `<Domain Owner>`)
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

State the single-purpose objective this architecture decision achieves for the Self-Service Provisioning Platform (SPP) and its AI Software Factory (`spp-factory-foundation`).

## Context

Describe the architectural, operational, security, and business forces driving this decision. Reference facts from the design session digest and existing platform constraints without inventing undocumented decisions.

## Decision

State the chosen architecture or governance rule clearly and concisely.

## Requirements

Requirements must use RFC 2119 / STE-100 keywords (`MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`) and be directly verifiable by an automated factory gate, OPA/Rego policy test, schema validator, or integration test.

- **REQ-1 (MUST):** [Testable requirement statement]
- **REQ-2 (MUST):** [Testable requirement statement]
- **REQ-3 (SHOULD):** [Testable requirement statement]

## Guardrails

Non-negotiable boundaries that neither human engineers nor factory agents may violate.

- **GR-1:** [Hard security, state, or operational constraint]
- **GR-2:** [Hard blast-radius or scope constraint]

## Consequences

### Positive

- [Benefit, risk reduction, or factory automation enablement]

### Negative / Trade-offs

- [Operational complexity, migration constraint, or bounded overhead]

## Acceptance Criteria

- [ ] [Criterion 1: Concrete artifact, schema, Rego policy, or runtime check required]
- [ ] [Criterion 2: Gate verification or stakeholder sign-off required]

## Success Criteria

Testable acceptance scenarios expressed in Given/When/Then format (validated by the factory `lint_adrs.py` gate).

- **SC-1:**
  - **Given** [precondition / input state]
  - **When** [action, workflow step, or gate execution occurs]
  - **Then** [observable, verifiable outcome]
- **SC-2:**
  - **Given** [precondition / input state]
  - **When** [action, workflow step, or gate execution occurs]
  - **Then** [observable, verifiable outcome]

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Prerequisite ADR definition and cross-ADR traceability |
| `ssp-cp` | Control plane API, DB migrations, policy enrichment, or per-service ADRs |
| `ssp-workers` | Temporal workflows/activities or Kubernetes Job runner launcher |
| `ssp-ui` | Portal catalog templates, persona field rules, or chat flows |
| `ssp-module-<type>` | Terraform resource module, Rego policies, examples, and `terraform test` |
| `spp-factory-foundation` | Factory role skills (`agents/skills/`), schemas, or reusable gates (`gates/`) |

## Open Questions

Mark any assumption, unconfirmed parameter, or cross-team dependency as an explicit Open Question (`OQ-*`) rather than inventing facts. All open questions must be resolved and signed off before transitioning `Status` from `Proposed` to `Accepted`.

- [ ] **OQ-1:** [Description of assumption or unresolved question and accountable stakeholder]

## Related ADRs

- [Link or ID of upstream/downstream ADRs]
