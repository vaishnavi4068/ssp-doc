# ADR-GLB-001: Global Architecture Overview

- **ADR ID:** ADR-GLB-001
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the end-to-end global architecture for the **Self-Service Provisioning Platform (SPP)**—a clean-slate, self-service infrastructure provisioning control plane (internal developer portal) on GCP that replaces the legacy "taxi" system and is built, verified, and governed by the **AI Software Factory** (`spp-factory-foundation`) using Architecture Decision Records (ADRs) as its sole input.

## Context

In the design discussion between Dwayne, Norm, and Manoj (`uploads/design-digest.md`), the team aligned on building a greenfield provisioning control plane from the ground up with zero code or OPA rule reuse from legacy "taxi":

1. **Hyperscaler Self-Service Experience:** "The only goal is self-service. We should be thinking of ourselves as Google, Amazon, or Microsoft." Developers request cloud infrastructure through a single contract (API first, followed by a template-driven portal + embedded chat), while mandatory security and operational guardrails are injected automatically in the `Approved` state so external compliance scanners ("Raju") never delete provisioned resources.
2. **Control Plane and Target Scope in GCP:** The SPP control plane, centralized AlloyDB for PostgreSQL database (`spp_platform`), self-hosted Temporal cluster, and Kubernetes Job Terraform runners live in GCP in the **non-prod** environment `microdrive-dev` (GKE cluster `md-dev`), and target workloads are provisioned in GCP using Google Cloud Storage (GCS) for `Expected` and `Observed` Terraform state storage and per-project service account execution. **Scope is GCP only for now; other clouds are out of scope and deferred to a future ADR.**
3. **Strictly Scoped to the 2.0 Cloud Layout:** SPP is built for the greenfield **2.0** GCP folder/host-project/service-project hierarchy where projects are small and scoped per application (`apm_id`). Legacy 1.0 shared projects (and extreme outliers such as CAP with ~8,000 items or ANBC HCBW prod with ~20,000 items) remain on "taxi" until imported later via CSP resource IDs and a translation shim.
4. **Built by the AI Software Factory ("Dark Factory"):** Humans author and sign off ADRs in `ssp-doc` (and per-service ADRs in `ssp-cp`) and design verification gates and reconciliation loops. A single unified coding agent in `github.com/vaishnavi4068/spp-factory-foundation` dynamically loads the 10 role skills under `agents/skills/*/SKILL.md` and translates ADRs into schemas, Rego policies, Terraform modules, control plane services, and tests.

## Decision

1. **GCP-Only Scope:** Scope is GCP only for now; other clouds are out of scope (future ADR), while keeping the `adr/per-cloud/gcp/` directory structure extensible.
2. **Control Plane Hosting:** Host the SPP control plane in GCP on GKE cluster `md-dev` in the **non-prod** project `microdrive-dev` (`environment = "dev"` / `nonprod`), isolated across dedicated namespaces (`spp-temporal`, `spp-factory`, `spp-platform`) on the tainted `spp-pool` node pool (`ADR-CLD-GCP-001`), with `ssp-cp` FastAPI endpoints exposed directly via GKE Ingress / LoadBalancer.
3. **Four-State Provisioning Model:** Represent every resource lifecycle through four states—`Requested` and `Approved` in centralized PostgreSQL (dedicated AlloyDB for PostgreSQL in GCP, zero secrets), and `Expected` and `Observed` in Google Cloud Storage (`ADR-GLB-003`, `ADR-GLB-004`).
4. **Identity & Blast-Radius Isolation:** Use GKE Workload Identity with zero static keys, and enforce **one dedicated service account per target GCP project** impersonated by a central platform service account ("kill button") (`ADR-GLB-005`).
5. **Execution Architecture:** Orchestrate post-approval execution, post-build bootstrap, and Day-2 operations in self-hosted Temporal (`platform` namespace), where workers (`ssp-workers`) launch **one deterministic Kubernetes Job per Terraform run** (`tf-op-<operation_id>`) in `spp-platform` (`ADR-AUT-001`, `ADR-AUT-002`).
6. **Governance & Non-Bypassable Operations:** Enforce clean-slate OPA/Rego policies against SPP's canonical JSON Schema (`ADR-GLB-007`) and Allen/Norm's directive that **operations cannot be bypassed** (`ADR-BP-001`; ServiceNow and CMDB integrations are out of scope for the `microdrive-dev` MVP and kept as a post-MVP interface placeholder only).
7. **Repository Topology:** Split the product across `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, and `ssp-module-<type>` (e.g., `ssp-module-spanner`, `ssp-module-gcs`), orchestrated by `spp-factory-foundation` (`docs/repo-map.md`).

## Requirements

- **REQ-1 (MUST):** The SPP control plane and all target resource provisioning MUST run on GCP targeting 2.0 GCP service projects, storing `Expected` and `Observed` Terraform state in GCS; other clouds are out of scope until a future ADR is accepted.
- **REQ-2 (MUST):** Every capability exposed by SPP MUST be driven by ADRs organized across the five factory levels (`global`, `business-process`, `endpoint-service`, `per-cloud`, `automation`) and verified by deterministic CI gates before merge.
- **REQ-3 (MUST):** Initial `Requested` state writes MUST be persisted synchronously by `ssp-cp` into centralized PostgreSQL without invoking Temporal; Temporal workflows (`ssp-workers` on namespace `platform`) MUST orchestrate execution only after `Approved` state enrichment and policy validation.
- **REQ-4 (MUST):** Neither human engineers nor factory agents may reuse legacy "taxi" OPA policies, shared `prod`/`nonprod`/`sandbox` service accounts, or per-category Terraform state splits.
- **REQ-5 (MUST):** Individual BigQuery tables MUST NOT be managed in project Terraform state; only BigQuery datasets are in scope for SPP Terraform modules.
- **REQ-6 (SHOULD):** The platform SHOULD operate as a business control plane where supplying an application's `apm_id` automatically resolves criticality tier (e.g., Tier 1 active-active database requirement), cost center, and security defaults in the `Approved` state.

## Guardrails

- **GR-1:** Never store secrets in `Requested` or `Approved` records in centralized PostgreSQL.
- **GR-2:** Never bypass operations gates (`operations_gate.approved == true`, `operations_gate.bypass_allowed == false`).
- **GR-3:** Never execute Terraform directly inside the long-lived Temporal worker process; always spawn an isolated Kubernetes Job per run.
- **GR-4:** Never onboard oversized 1.0 legacy projects (e.g., CAP ~8,000 resources) into standard 2.0 single-state-file workflows without an explicit decomposition/shim ADR.

## Consequences

### Positive

- Clear separation between the AI Software Factory (`spp-factory-foundation` in `spp-factory`) and the SPP runtime control plane (`ssp-cp`, `ssp-workers`, `ssp-ui` in `spp-platform`).
- Security and compliance defaults (CMEK, `>= 90`-day retention, Raju baseline) are guaranteed by construction in `Approved` state, eliminating surprise resource deletions.
- Per-project service accounts and per-project state files strictly bound blast radius under the assumption of breach ("we will be hacked").

### Negative / Trade-offs

- Managing thousands of per-project service accounts and hundreds of `ssp-module-<type>` repositories requires strict automation in the factory and onboarding pipelines.
- Post-build steps (VM Ansible playbooks, DBA Jenkins jobs) currently rely on scattered tribal knowledge across teams and must be wrapped into Temporal activities for the POC before long-term domain team handoff.

## Acceptance Criteria

- [ ] All five ADR level directories (`global/`, `business-process/`, `endpoint-service/`, `per-cloud/gcp/`, `automation/`) are established in `ssp-doc/adr/` and aligned with `spp-factory-foundation`.
- [ ] `docs/repo-map.md` documents the responsibilities and boundaries of `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, and `ssp-module-<type>`.
- [ ] `python3 gates/scripts/lint_adrs.py` from `spp-factory-foundation` passes on all ADRs in `ssp-doc/adr/`.

## Success Criteria

- **SC-1:**
  - **Given** a prerequisite or service ADR authored in `ssp-doc` or `ssp-cp`
  - **When** the `spp-factory-foundation` coding agent executes a work item across the 8 assembly-line stations (`impact -> plan -> build -> gate -> review -> approval -> merge -> reconcile`)
  - **Then** the agent loads the corresponding `agents/skills/<role>/SKILL.md` skills, validates all 7 gate stages, and produces compliant code/policy PRs without human-written boilerplate.
- **SC-2:**
  - **Given** a 2.0 GCP resource request submitted to `ssp-cp`
  - **When** the request progresses through `Requested -> Approved -> Expected -> Observed`
  - **Then** `Requested` and `Approved` are recorded in PostgreSQL with zero secrets, guardrails are injected in `Approved`, and a deterministic Kubernetes Job applies the change to the target GCP project.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the canonical 5-level ADR hierarchy and global architecture invariants |
| `ssp-cp` | Implements the GCP-hosted control plane API, `Approved` enrichment, and DB schema |
| `ssp-workers` | Implements Temporal workflows (`platform` namespace) and K8s Job runner launcher |
| `ssp-ui` | Implements the template-driven portal and chat storefront (Phase 5) |
| `ssp-module-<type>` | Implements per-resource Terraform modules and Rego policies for 2.0 GCP projects |
| `spp-factory-foundation` | Consumes these ADRs via its 10 role skills to build and verify all product repos |

## Open Questions

- [x] **OQ-1 (Terminology Alignment — DEFERRED TO PHASE 5 [Owner: Dwayne]):** *Deferred to Phase 5 (`ssp-ui`):* External branding ("SPP Internal Developer Portal" vs. "Provisioning Control Plane") will be finalized with Dwayne when `ssp-ui` is built in Phase 5.
- [x] **OQ-2 (Console Feature Parity — DEFERRED TO PHASE 6 [Owner: Norm]):** *Deferred to Phase 6 (More GCP Resource Types):* Parity for legacy "console" features (firewall-rule visibility, Kafka topics, F5 vs. cloud-native load balancers) is deferred to Phase 6 under Norm.
- [x] **OQ-3 (Post-Build Long-Term Ownership — DEFERRED TO PHASE 6 [Owner: Norm / Karen]):** *Deferred to Phase 6 (VM & DB Modules):* Domain-team SLA and handoff for post-build Temporal activities (VM Ansible playbooks, DBA Jenkins jobs) are deferred to Phase 6 under Norm and Karen (not needed for the Phase 3–4 GCS slice).
- [x] **OQ-4 (Legacy Import Shim — DEFERRED POST-MVP [Owner: Manoj / Dwayne]):** *Deferred post-MVP:* Legacy 1.0 project import via CSP resource IDs and translation shim is deferred post-MVP under Manoj and Dwayne.

## Related ADRs

- [ADR-CLD-GCP-001: Runtime Platform (GKE `md-dev` and Self-Hosted Temporal)](../per-cloud/gcp/ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md)
- [ADR-GLB-002: Languages and Technology Stack](ADR-GLB-002-languages-and-technology-stack.md)
- [ADR-GLB-003: Four-State Provisioning Model](ADR-GLB-003-four-state-model.md)
- [ADR-BP-001: Ownership Map and Stakeholder Governance](../business-process/ADR-BP-001-ownership-map-and-governance.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
