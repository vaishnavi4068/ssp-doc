# ADR-BP-002: Product Build Order and Delivery Phasing

- **ADR ID:** ADR-BP-002
- **Level:** business-process
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the strict, dependency-ordered delivery sequence for building the Self-Service Provisioning Platform (SPP) through the AI Software Factory (`spp-factory-foundation`), starting from prerequisite ADRs and a headless control-plane skeleton, proving the **GCS bucket vertical slice end-to-end with no UI**, adding **GCS Day-2 operations**, and only then building the **portal UI + chat** and expanding to additional resource types.

## Context

To avoid building an ungrounded UI or attempting to support dozens of cloud services before the core four-state control plane (`Requested -> Approved -> Expected -> Observed`), Temporal orchestration (`platform` namespace), and Kubernetes Job runner (`spp-platform`) are proven in `microdrive-dev` (`md-dev`), the team established a six-stage build order:

1. **Phase 1:** Global & Data-Model Prerequisite ADRs (`ssp-doc` + per-service/component ADRs in `ssp-cp`)
2. **Phase 2:** Control-Plane & Worker Skeleton (`ssp-cp` + `ssp-workers`)
3. **Phase 3:** First Vertical Slice — GCS Bucket End-to-End with **No UI** (`ADR-SVC-001`)
4. **Phase 4:** GCS Bucket Day-2 Operations (`ADR-AUT-002`)
5. **Phase 5:** Portal UI & Embedded Chat (`ssp-ui`)
6. **Phase 6:** Additional Resource Types (`ssp-module-spanner`, VM, Cloud SQL/Postgres, BigQuery dataset) and Multi-Cloud Targets (AWS, Azure)

## Decision

The AI Software Factory (`spp-factory-foundation`) and engineering team MUST execute the SPP build in the following six sequential phases, where each phase's exit criteria gate the start of the next phase:

| Phase | Name | Target Repos | Scope & Deliverables | Exit Gate |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | **Global, Architecture & Data-Model ADRs** | `ssp-doc`, `ssp-cp` | Draft and review prerequisite ADRs in `ssp-doc` (`adr/global/`, `adr/business-process/`, `adr/endpoint-service/`, `adr/per-cloud/`, `adr/automation/`) and component/service ADRs in `ssp-cp` (API, DB migrations, GCS, Spanner, VM). | ADRs pass `lint_adrs.py` and receive human owner sign-off (`Accepted`). |
| **Phase 2** | **Control-Plane & Worker Skeleton** | `ssp-cp`, `ssp-workers` | Build Python FastAPI skeleton + local Argon2id auth + Alembic PostgreSQL migrations (`Requested`/`Approved` tables) + OPA policy evaluator in `ssp-cp`; build Python Temporal worker (`platform` namespace on `temporal-frontend.spp-temporal.svc.cluster.local:7233`) + deterministic K8s Job launcher (`tf-op-<operation_id>` in `spp-platform`) in `ssp-workers`. | Health checks, DB migrations, auth flow,OPA evaluation, and dry-run K8s Job launch pass in `spp-platform` on `md-dev`. |
| **Phase 3** | **First Vertical Slice: GCS Bucket End-to-End (No UI)** | `ssp-module-gcs` (or `templates/resource-repo`), `ssp-cp`, `ssp-workers` | Headless API-driven provisioning of a compliant 2.0 GCS bucket (`google_storage_bucket`) through all 4 states (`Requested -> Approved -> Expected -> Observed`) with CMEK, `>= 90`-day retention, uniform bucket-level access, `public_access_prevention = "enforced"`, Raju baseline, and state stored in `gs://microdrive-dev-spp-tfstate`. **Zero UI work in this phase.** | Live GCS bucket provisioned via API on `microdrive-dev` with `Expected` and `Observed` state verified in `gs://microdrive-dev-spp-tfstate`. |
| **Phase 4** | **GCS Bucket Day-2 Operations** | `ssp-cp`, `ssp-workers`, `ssp-module-gcs` | Implement and verify Day-2 workflows for GCS buckets: **update** (labels/lifecycle), **resize/tier change** (storage class), **upgrade** (module version bump), **drift detection** (`Expected` vs. `Observed` by CSP resource ID), **rollback** (prior `Approved` spec), **decommission** (controlled delete with operations gate), and **cost** attribution. | All 7 Day-2 operations pass integration tests against the GCS vertical slice. |
| **Phase 5** | **Self-Service Portal UI & Chat** | `ssp-ui`, `ssp-cp` | Build the React storefront (`ssp-ui`) with top-center search, frequent catalog, bottom-right conversational chat, template-driven form rendering (no redeploy per service), equivalent Terraform/CLI code preview, and SSO integration. | User can request and track a GCS bucket and Day-2 actions from `ssp-ui` and chat. |
| **Phase 6** | **More Resource Types & Multi-Cloud** | `ssp-module-spanner`, `ssp-module-vm`, `ssp-module-postgres`, `ssp-cp`, `ssp-workers` | Onboard additional GCP services (Spanner in existing `ssp-module-spanner`, GCE VMs with post-build Temporal workflows, relational DBs, BigQuery datasets) and expand to AWS (`ADR-CLD-AWS-001`) and Azure (`ADR-CLD-AZR-001`) 2.0 targets. | Each new `ssp-module-<type>` passes the 7-stage factory gate and registers in the catalog without redeploying `ssp-ui`. |

## Requirements

- **REQ-1 (MUST):** No runtime feature implementation in `ssp-cp` or `ssp-workers` MAY merge before the governing prerequisite ADRs in `ssp-doc` and component ADRs in `ssp-cp` are drafted and validated by the factory ADR linter.
- **REQ-2 (MUST):** Phase 3 (First Vertical Slice) MUST be limited strictly to **GCS bucket (`google_storage_bucket`) end-to-end provisioning via API with no UI** (`ADR-SVC-001`).
- **REQ-3 (MUST):** Phase 4 (GCS Day-2 Operations) MUST be completed and verified on the GCS vertical slice before Phase 5 (`ssp-ui` portal + chat) or Phase 6 (additional resource types such as Spanner and VMs) begins.
- **REQ-4 (MUST):** Every work item executed by the software factory across Phases 2–6 MUST pass the 7-stage verification gate (`gates/scripts/run_gate.sh`) within the bounded 3-retry rework budget (`ADR-AUT-003`).
- **REQ-5 (SHOULD):** Daily performance and reliability benchmarks (target 10–20 automated provisioning runs per day) SHOULD be introduced once Phase 3 (GCS end-to-end) is operational in `spp-platform`.

## Guardrails

- **GR-1:** Do not build `ssp-ui` frontend screens or chat flows during Phases 1–3; prove the headless control plane and GCS vertical slice via API first.
- **GR-2:** Do not onboard complex stateful services (VMs with 2-hour Ansible playbooks, multi-region databases) before the GCS bucket create (Phase 3) and Day-2 (Phase 4) loops are green.
- **GR-3:** Never skip a phase exit gate to accelerate downstream phases.

## Consequences

### Positive

- De-risks the platform architecture (`ssp-cp` -> PostgreSQL -> Temporal `platform` namespace -> K8s Job `tf-op-<operation_id>` -> `gs://microdrive-dev-spp-tfstate`) using the simplest cloud resource (`google_storage_bucket`) before adding UI or complex post-build workflows.
- Gives the AI Software Factory a clean, sequential backlog of work items with unambiguous dependencies.

### Negative / Trade-offs

- Stakeholders wanting interactive portal/chat demos for SPP must wait until Phase 5 (though the Factory Console in `spp-factory` is already live for observing factory runs).

## Acceptance Criteria

- [ ] Factory work items and PRs are sequenced according to Phases 1–6 in `ssp-doc` and `spp-factory-foundation`.
- [ ] Phase 1 (`ssp-doc` prerequisite ADRs) is delivered as a draft PR for Architect (`Manoj`) and Approver (`Dwayne`, `Norm`) review.
- [ ] `ssp-cp` component ADRs (GCS, Spanner, VM, API, DB migrations) are queued as the immediate follow-on before Phase 2 skeleton code.

## Success Criteria

- **SC-1:**
  - **Given** the Phase 1 prerequisite ADRs in `ssp-doc`
  - **When** reviewed and accepted by `Manoj`, `Dwayne`, and `Norm`
  - **Then** the software factory can execute Phase 2 (`ssp-cp` and `ssp-workers` skeleton) and Phase 3 (GCS bucket end-to-end without UI) using only ADR inputs.
- **SC-2:**
  - **Given** a work item attempting to scaffold `ssp-ui` or VM Ansible post-build workflows prior to Phase 3 GCS vertical slice completion
  - **When** evaluated against the build order in `ADR-BP-002`
  - **Then** the Change Plan Agent sequences the work item after Phase 3 and Phase 4 completion.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Phase 1 deliverable (all prerequisite & architecture ADRs) |
| `ssp-cp` | Phase 1 (per-service/API/DB ADRs), Phase 2 (API & DB skeleton), Phase 3–4 (GCS create & Day-2) |
| `ssp-workers` | Phase 2 (Temporal worker & K8s Job launcher), Phase 3–4 (GCS create & Day-2 workflows) |
| `ssp-module-<type>` | Phase 3–4 (`ssp-module-gcs`), Phase 6 (`ssp-module-spanner`, `ssp-module-vm`, etc.) |
| `ssp-ui` | Phase 5 (React portal + chat storefront) |
| `spp-factory-foundation` | Orchestrates work items across Phases 1–6 in the `factory` Temporal namespace |

## Open Questions

- [ ] **OQ-1 (Location of Per-Service ADRs in Phase 1/2):** Per `docs/repo-map.md`, `ssp-cp` holds per-service ADRs for GCS, Spanner, VM, API, and DB migrations. Should those 5 `ssp-cp` ADRs be drafted immediately after this `ssp-doc` PR merges, before writing the Phase 2 `ssp-cp` Python skeleton?
- [ ] **OQ-2 (Phase 5 UI Baseline):** Before Phase 5 (`ssp-ui`) starts, confirm which 5 UI variants from Dwayne's prototype gallery are selected by Dwayne, Norm, and Manoj.

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](../global/ADR-GLB-001-global-architecture-overview.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End (No UI)](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-AUT-002: Day-2 Operations Scope](../automation/ADR-AUT-002-day-2-operations-scope.md)
- [ADR-AUT-003: Software Factory ADR Flow and Role Skills](../automation/ADR-AUT-003-software-factory-adr-flow.md)
