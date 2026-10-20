# 60 — Architecture Decision Records

Five categories (D-16): **Global** (`G-`), **Business Process** (`B-`), **Endpoint** per service (`E-<SVC>-`), **Per-Cloud** (`C-<CLOUD>-`), **Automation** (`A-`). Each ADR has a named owner and a shared mailbox; the platform team are the sole PR approvers.

## Folder layout

```
60-adr/
├── README.md              this file
├── global/                G-0001 …
├── business-process/      B-0001 …
├── endpoint/<service>/    E-SPAN-0001, E-GCS-0001 …
├── cloud/{gcp,aws,azure}/ C-GCP-0001 …
└── automation/            A-0001 …
```

## Template

Frontmatter: `id, title, category, status (proposed | accepted | superseded), owner, mailbox, applies_to {clouds, services}, depends_on, supersedes, decided_in`.
Sections: **Goal · Context · Decision · Requirements (table: ID | Requirement | Verify by) · Guardrails · Success criteria · Alternatives considered · Consequences · Open questions.**

Requirement IDs are `REQ-<ADR id>-<nn>`; every MUST row names a verification method (`tftest`, `rego:request`, `rego:plan`, `scenario`, `unit`, `manual`). The Spec Critic rejects rows without one. Endpoint ADR guardrails compile into the service's `ServiceSpec.guardrails`.

## Backlog and status

The ADR IDs, titles and current status (decided in the design session vs. open) are listed in `00-constitution/02-decisions-register.md` and in the handoff document *02-dark-factory-plan.md* ("First ADR backlog"). Writing the decided ones down is the first Spec Scribe work: see `90-tasks/T-0001-write-phase0-adrs.md`. Open ones (G-0006 labels, G-0007 security baseline, G-0008 blast radius, C-AWS-*, C-AZ-*, A-0004 concurrency, A-0006 drift, B-0001 RBAC, B-0005 break-glass, B-0006 decommission) need the owners named in the register before they can be accepted.
