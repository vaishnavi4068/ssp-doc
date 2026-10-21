# ADR-BP-001: Ownership Map, Stakeholder Governance, and ITSM/CMDB Integration

- **ADR ID:** ADR-BP-001
- **Level:** business-process
- **Status:** Proposed
- **Owner:** Norm (Shared Mailbox: `spp-governance@tbd`, Named Owner: `Norm`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Allen / Karen [Operations], Ken O'Connor [ServiceNow/CMDB], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Codify the cross-functional stakeholder ownership map, ADR sign-off rules, CODEOWNERS hierarchy, and mandatory ServiceNow / CMDB / Operations integration boundaries for SPP so that accountability is explicit and operations cannot be bypassed.

## Context

In the design discussion (`uploads/design-digest.md`), Dwayne noted: "we have too many people who have a say… that's why nothing gets done," and the team agreed that every requirement must be documented in an ADR with a tracked owner (a shared team mailbox plus a named person), while Norm reiterated Allen's mandate: **"we cannot bypass operations."**

Across the enterprise, specific integration domains and platform approvals are owned by named leads who must be engaged for interface contracts, credentials, and ADR sign-offs. In the non-prod `microdrive-dev` environment, the **SPP team** directly owns and provides the `spp-platform` runner GCP service account (`<runner-sa>@microdrive-dev.iam.gserviceaccount.com`, `TODO: vaishnavi4068`) and exposes `ssp-cp` directly via GKE Ingress / LoadBalancer on `md-dev`.

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
   | **ServiceNow & CMDB** | **Ken O'Connor** (with **Stephanie** as CMDB contact) | `spp-itsm-cmdb@tbd` | ServiceNow request records (`REQ*`), production Change Requests (`CHG*`), incident linkage, and CMDB CI registration / non-VM CI class creation |
   | **Networking, CIDR & Infoblox** | **John Simon** | `spp-network@tbd` | IP/CIDR range allocation and Infoblox integration for 2.0 GCP projects |
   | **Executive Sponsor / Database Strategy** | **Saul** | `spp-leadership@tbd` | Executive sponsorship and database hosting direction |

2. **ADR Ownership & Sign-Off Rule:**
   - Every ADR in `ssp-doc` (and per-service ADR in `ssp-cp`) MUST specify both a `Shared Mailbox:` and a `Named Owner:` in its `- **Owner:**` metadata field.
   - All newly drafted ADRs start at `Status: Proposed` and `Signers: Unsigned`.
   - Moving an ADR from `Proposed` to `Accepted` is a **permanent human gate** (`ADR-AUT-003`) requiring sign-off from the Architect (`Manoj`), Core Approvers (`Dwayne`, `Norm`), and the relevant domain owner.
3. **ServiceNow & CMDB Mandatory Integration:**
   - Every request transitioning to `Approved` state MUST record a ServiceNow request ID (`servicenow.record_id`, `^REQ[0-9]{7,10}$`).
   - Every production operation (`environment == "prod"`) MUST carry an approved ServiceNow Change Request (`servicenow.change_request_id`, `^CHG[0-9]{7,10}$`).
   - Every provisioned resource MUST register a Configuration Item (CI) in CMDB (`cmdb.registration_required == true`, non-empty `cmdb.ci_class`) and link provisioning failures or security drift events to ServiceNow incidents.

## Requirements

- **REQ-1 (MUST):** Every ADR file in `ssp-doc/adr/` MUST declare a valid `- **Owner:**` line containing both `Shared Mailbox:` and `Named Owner:` (enforced by `lint_adrs.py`).
- **REQ-2 (MUST):** `CODEOWNERS` in `ssp-doc` MUST require review from the Architect (`Manoj`) and Approvers (`Dwayne`, `Norm`) on all ADR and template changes.
- **REQ-3 (MUST):** `ssp-cp` and `ssp-workers` MUST integrate with ServiceNow (owned by Ken O'Connor) to record `REQ*` tracking on every order, enforce `CHG*` validation before any `prod` execution, and open linked incidents on execution failure or security guardrail drift.
- **REQ-4 (MUST):** `ssp-cp` and `ssp-workers` MUST enforce CMDB CI registration (owned by Ken O'Connor / Stephanie) for every provisioned resource.
- **REQ-5 (MUST):** Operations rules from Allen, Karen, and Norm MUST be enforced automatically in the `Approved` state and OPA policy gate (`operations_gate.approved == true`, `operations_gate.bypass_allowed == false`).
- **REQ-6 (SHOULD):** Persona-based permissions (`developer`, `operations`, `security`, `platform-admin`) SHOULD restrict destructive actions and privileged operational fields to the `operations` persona across `ssp-cp` and `ssp-ui`.

## Guardrails

- **GR-1:** Operations cannot be bypassed in either the software factory pipeline or runtime provisioning ("we cannot bypass operations").
- **GR-2:** No agent may self-approve an ADR (`Proposed -> Accepted`) or self-approve a production Change Request (`CHG*`).
- **GR-3:** Never provision a cloud resource without `apm_id`, `owner`, ServiceNow tracking metadata, and CMDB CI class metadata in the `Approved` spec.

## Consequences

### Positive

- Eliminates ambiguity over who owns external dependencies (ServiceNow/CMDB, SAs/clusters, security rules, operations/DBA rules) and who signs off on ADRs.
- Aligns `CODEOWNERS`, Factory Console RBAC (`manoj` as `architect`; `dwayne` and `norm` as `approver`), and ADR metadata, with the SPP team directly owning `microdrive-dev` service accounts.

### Negative / Trade-offs

- External integrations (ServiceNow API credentials from Ken O'Connor, CMDB non-VM CI classes, Raju's full rule export) require coordination with external teams; mock/adapter interfaces in `ssp-cp` and `ssp-workers` are needed during early development in `microdrive-dev`.

## Acceptance Criteria

- [ ] `CODEOWNERS` is committed at the root of `ssp-doc` with `manoj` (Architect) and `dwayne`, `norm` (Approvers) and explicit `TODO` markers for unknown GitHub handles.
- [ ] `adr/OWNERSHIP_MATRIX.md` maps every ADR in `ssp-doc` to its Shared Mailbox, Named Owner, and required signers.
- [ ] `ssp-cp` and `ssp-workers` enforce `servicenow`, `cmdb`, and `operations_gate` blocks on all `Approved` payloads.

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
| `ssp-cp` | Enforces RBAC personas, `operations_gate`, and ServiceNow/CMDB schema contracts |
| `ssp-workers` | Executes ServiceNow request/CR/incident and CMDB CI registration activities |
| `ssp-ui` | Enforces persona-based field visibility and action controls |
| `spp-factory-foundation` | Enforces `architect` (`manoj`) and `approver` (`dwayne`, `norm`) roles in Factory Console |

## Open Questions

- [ ] **OQ-1 (GitHub Handles & Shared Mailboxes):** What are the exact GitHub handles for Manoj (`@manoj-todo`), Dwayne (`@dwayne-todo`), Norm (`@norm-todo`), and domain owners, and what are the active corporate distribution list addresses to replace `*@tbd`?
- [ ] **OQ-2 (CMDB Non-VM CI Classes with Ken O'Connor & Stephanie):** Today's CMDB holds primarily VMs. What is the process and timeline with Ken O'Connor (and Stephanie) to define or onboard CMDB CI classes for PaaS/cloud resources such as GCS buckets (`cmdb_ci_cloud_storage_bucket`) and Cloud Spanner?
- [ ] **OQ-3 (ServiceNow Non-Prod vs. Prod Flow):** In `dev` / `sandbox` environments (such as the first vertical slice in non-prod `microdrive-dev`), should `ssp-cp`/`ssp-workers` call a ServiceNow dev instance or a deterministic local ServiceNow/CMDB adapter while Ken O'Connor provisions API credentials?
- [ ] **OQ-4 (Cloud-to-CMDB Active Reconciliation):** Beyond the standard read-only CMDB polling agent, should `ssp-workers` actively push reconciliation updates from `Observed` state to CMDB?

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](../global/ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-007: Governance Gates and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](ADR-BP-002-build-order-and-phasing.md)
