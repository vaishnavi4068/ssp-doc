# ADR-BP-001: Ownership Map and Stakeholder Governance

- **ADR ID:** ADR-BP-001
- **Level:** business-process
- **Status:** Proposed
- **Owner:** Norm (Shared Mailbox: `spp-governance@tbd`, Named Owner: `Norm`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Allen / Karen [Operations], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Codify the cross-functional stakeholder ownership map, ADR sign-off rules, CODEOWNERS hierarchy, and Operations governance boundaries for SPP so that accountability is explicit and operations cannot be bypassed.

## Context

In the design discussion (`uploads/design-digest.md`), Dwayne noted: "we have too many people who have a say… that's why nothing gets done," and the team agreed that every requirement must be documented in an ADR with a tracked owner (a shared team mailbox plus a named person), while Norm reiterated Allen's mandate: **"we cannot bypass operations."**

Across the enterprise, specific integration domains and platform approvals are owned by named leads who must be engaged for interface contracts, credentials, and ADR sign-offs. In the non-prod `microdrive-dev` environment, the **SPP team** directly owns and provides the `spp-platform` runner GCP service account (`<runner-sa>@microdrive-dev.iam.gserviceaccount.com`, `TODO: vaishnavi4068`) and exposes `ssp-cp` directly via GKE Ingress / LoadBalancer on `md-dev`. ServiceNow and CMDB integrations (owned by Ken O'Connor / Stephanie) are **out of scope for the `microdrive-dev` MVP** and retained only as a future integration interface placeholder.

## Decision

1. **Canonical Stakeholder & Integration Ownership Map:**

   | Domain / Integration Area | Accountable Owner(s) | Shared Mailbox (Placeholder) | Responsibility in SPP |
   | :--- | :--- | :--- | :--- |
   | **Architect (Global Architecture & Factory Autonomy)** | **Manoj** (`@vaishnavi4068` / `@manoj-todo`) | `spp-architecture@tbd` | Global architecture, GCP host/service project model, data model, Factory Console `architect` role, CODEOWNERS lead |
   | **Core Approvers & Architecture/Ops Co-Leads** | **Dwayne**, **Norm** (`@dwayne-todo`, `@norm-todo`) | `spp-architecture@tbd` | Core PR/ADR approvers (`CODEOWNERS`), Factory Console `approver` role, dark factory & UI direction (Dwayne), Taxi parity & operations gate (Norm) |
   | **Lead Engineers / Code Owners** | **Norm**, **Manoj** | `spp-engineering@tbd` | Code ownership across `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, and `ssp-module-<type>` |
   | **Service Accounts in `microdrive-dev` (Non-Prod)** | **SPP Team** (`@vaishnavi4068`) | `spp-engineering@tbd` | Provides and owns the `spp-platform` runner GCP Service Account (`<runner-sa>@microdrive-dev.iam.gserviceaccount.com`, `TODO: vaishnavi4068`) and Workload Identity bindings in `microdrive-dev` |
   | **Enterprise Clusters & Future Prod Service Accounts** | **Hurley** | `spp-cloud-iam@tbd` | Enterprise cluster issuance and future production environment/APM ID provisioning outside `microdrive-dev` |
   | **Operations & Database Governance** | **Allen** (Executive mandate), **Karen** (DBA/Ops requirements), **Norm** (Ops lead) | `spp-operations@tbd` | Non-bypassable Operations Gate (`ADR-GLB-007`), database operational rules, Jenkins DBA post-build criteria, persona permissions |
   | **Security & Compliance Baseline** | **Raju's team** (plus **Durant** on SA isolation) | `spp-security@tbd` | Security baseline rules injected in `Approved` state (`CMEK`, `>= 90`-day retention, public access prevention) so Raju's scanner never deletes SPP resources |
   | **ServiceNow & CMDB (Post-MVP / Future Integration)** | **Ken O'Connor** (with **Stephanie** as CMDB contact) | `spp-itsm-cmdb@tbd` | **Out of scope for `microdrive-dev` MVP** (interface placeholder only; live ServiceNow request/CR/incident and CMDB CI registration deferred post-MVP) |
   | **Networking, CIDR & Infoblox** | **John Simon** | `spp-network@tbd` | IP/CIDR range allocation and Infoblox integration for 2.0 GCP projects |
   | **Executive Sponsor / Database Strategy** | **Saul** | `spp-leadership@tbd` | Executive sponsorship and database hosting direction |

2. **ADR Ownership & Sign-Off Rule:**
   - Every ADR in `ssp-doc` (and per-service ADR in `ssp-cp`) MUST specify both a `Shared Mailbox:` and a `Named Owner:` in its `- **Owner:**` metadata field (`*@tbd` shared mailboxes and `@manoj-todo`, `@dwayne-todo`, `@norm-todo` GitHub handles are accepted placeholders for the `microdrive-dev` MVP and will be replaced before production, while `@vaishnavi4068` is listed on every `CODEOWNERS` path so reviews route cleanly).
   - All newly drafted ADRs start at `Status: Proposed` and `Signers: Unsigned`.
   - Moving an ADR from `Proposed` to `Accepted` is a **permanent human gate** (`ADR-AUT-003`) requiring sign-off from the Architect (`Manoj`), Core Approvers (`Dwayne`, `Norm`), and the relevant domain owner.
3. **Future Integration Note — ServiceNow & CMDB (Post-MVP Placeholder Only):**
   - ServiceNow (`REQ*`, `CHG*`, incidents) and CMDB CI registration are **out of scope for the `microdrive-dev` MVP** (no CMDB CI creation and no ServiceNow API/mock/adapter required for the GCS vertical slice).
   - `ssp-cp` and `ssp-workers` retain only a lightweight, no-op interface/schema placeholder (`servicenow_metadata` / `cmdb_metadata`) so live ITSM/CMDB integration with Ken O'Connor and Stephanie can be plugged in post-MVP without breaking schema compatibility.

## Requirements

- **REQ-1 (MUST):** Every ADR file in `ssp-doc/adr/` MUST declare a valid `- **Owner:**` line containing both `Shared Mailbox:` and `Named Owner:` (enforced by `lint_adrs.py`).
- **REQ-2 (MUST):** `CODEOWNERS` in `ssp-doc` MUST require review from the Architect (`Manoj`) and Approvers (`Dwayne`, `Norm`) on all ADR and template changes.
- **REQ-3 (MUST):** Operations rules from Allen, Karen, and Norm MUST be enforced automatically in the `Approved` state and OPA policy gate (`operations_gate.approved == true`, `operations_gate.bypass_allowed == false`).
- **REQ-4 (MUST):** For the `microdrive-dev` MVP, ServiceNow and CMDB MUST remain non-blocking interface placeholders only (no external ServiceNow/CMDB calls or mock adapters required on the critical path for the GCS vertical slice).
- **REQ-5 (SHOULD):** Persona-based permissions (`developer`, `operations`, `security`, `platform-admin`) SHOULD restrict destructive actions and privileged operational fields to the `operations` persona across `ssp-cp` and `ssp-ui`.

## Guardrails

- **GR-1:** Operations cannot be bypassed in either the software factory pipeline or runtime provisioning ("we cannot bypass operations").
- **GR-2:** No agent may self-approve an ADR (`Proposed -> Accepted`).
- **GR-3:** Never provision a cloud resource without `apm_id`, `owner`, and `operations_gate` approval in the `Approved` spec.

## Consequences

### Positive

- Eliminates ambiguity over who owns each domain and who signs off on ADRs, while removing ServiceNow/CMDB from the `microdrive-dev` MVP critical path so the GCS vertical slice has zero external ITSM blockers.
- Aligns `CODEOWNERS`, Factory Console RBAC (`manoj` as `architect`; `dwayne` and `norm` as `approver`), and ADR metadata.

### Negative / Trade-offs

- Live ServiceNow Change Request (`CHG*`) gating and CMDB CI registration will require a post-MVP integration task once SPP moves beyond `microdrive-dev`.

## Acceptance Criteria

- [ ] `CODEOWNERS` is committed at the root of `ssp-doc` with `manoj` (Architect) and `dwayne`, `norm` (Approvers) and explicit `TODO` markers for unknown GitHub handles.
- [ ] `adr/OWNERSHIP_MATRIX.md` maps every ADR in `ssp-doc` to its Shared Mailbox, Named Owner, and required signers.
- [ ] `ssp-cp` and `ssp-workers` enforce `operations_gate` on all `Approved` payloads while keeping ServiceNow/CMDB as a non-blocking interface placeholder for the `microdrive-dev` MVP.

## Success Criteria

- **SC-1:**
  - **Given** all ADR files under `ssp-doc/adr/`
  - **When** `python3 gates/scripts/lint_adrs.py adr` runs
  - **Then** 100% of ADRs pass `Status`, `Level`, and `Owner` (`Shared Mailbox:` + `Named Owner:`) validation.
- **SC-2:**
  - **Given** a developer persona attempting to modify an operations-restricted field (such as disabling retention lock or bypassing `operations_gate`)
  - **When** `ssp-cp` validates the request
  - **Then** the request is rejected with a `403 Forbidden` / policy denial citing `ADR-BP-001` and `ADR-GLB-007`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `CODEOWNERS`, `adr/OWNERSHIP_MATRIX.md`, and stakeholder governance |
| `ssp-cp` | Enforces RBAC personas and `operations_gate` (with a post-MVP interface placeholder for ServiceNow/CMDB) |
| `ssp-workers` | Executes provisioning and post-build activities without requiring ServiceNow/CMDB calls in the MVP |
| `ssp-ui` | Enforces persona-based field visibility and action controls |
| `spp-factory-foundation` | Enforces `architect` (`manoj`) and `approver` (`dwayne`, `norm`) roles in Factory Console |

## Open Questions

- [x] **OQ-1 (GitHub Handles & Shared Mailboxes — RESOLVED 2026-10-21):** *Resolved (Accepted placeholders for MVP; replace before production):* Placeholder GitHub handles (`@manoj-todo`, `@dwayne-todo`, `@norm-todo`) and `*@tbd` shared mailboxes are accepted for the `microdrive-dev` MVP and will be replaced before production; `@vaishnavi4068` is present on every `CODEOWNERS` path so GitHub review routing works immediately.
- [x] **OQ-2 (CMDB Non-VM CI Classes with Ken O'Connor & Stephanie — RESOLVED 2026-10-21):** *Resolved (Deferred post-MVP):* ServiceNow and CMDB are placeholders and out of scope for the `microdrive-dev` MVP (no CMDB CI creation required for the GCS slice).
- [x] **OQ-3 (ServiceNow Non-Prod vs. Prod Flow — RESOLVED 2026-10-21):** *Resolved (Deferred post-MVP):* No ServiceNow call, adapter, or mock is required for the `microdrive-dev` MVP; kept as an interface placeholder only.
- [x] **OQ-4 (Cloud-to-CMDB Active Reconciliation — RESOLVED 2026-10-21):** *Resolved (Deferred post-MVP):* Deferred post-MVP alongside CMDB integration.

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](../global/ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-007: Governance Gates and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](ADR-BP-002-build-order-and-phasing.md)
