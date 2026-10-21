# ADR-AUT-002: Day-2 Operations Scope (Update, Resize, Upgrade, Drift Detection, Rollback, Decommission, Cost)

- **ADR ID:** ADR-AUT-002
- **Level:** automation
- **Status:** Proposed
- **Owner:** Norm (Shared Mailbox: `spp-automation@tbd`, Named Owner: `Norm`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Allen / Karen [Operations])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the scope, state-transition mechanics, governance gates, and open questions for all seven **Day-2 operations** in SPP—**update**, **resize**, **upgrade**, **drift detection**, **rollback**, **decommission**, and **cost**—orchestrated via Temporal workflows in `ssp-workers` (`platform` namespace) and executed via deterministic Kubernetes Jobs (`tf-op-<operation_id>`) in `spp-platform`.

## Context

A self-service infrastructure control plane cannot stop at Day-1 creation (`POST /api/v1/requests`). Once a resource reaches `Observed` state, application teams and operations require complete lifecycle management:

1. **What the Design Session Covered Directly (`uploads/design-digest.md`):**
   - **Drift Detection & Reconciliation:** Drift is defined as `Expected != Observed`, matched by **immutable Cloud Service Provider (CSP) resource ID** rather than resource name (a key lesson from legacy "taxi"). Dwayne and Norm debated whether a plain `terraform plan` is sufficient (Norm: yes; Dwayne: no, because out-of-band state/cloud changes can occur outside `Expected` state). Both `expected/` and `observed/` folders are provisioned in the state bucket (`gs://microdrive-dev-spp-tfstate`) so `Observed` state is captured and compared against `Expected`.
   - **Operations Gate & Persona Permissions:** Operations cannot be bypassed (Allen/Norm). Certain fields and destructive actions (such as delete/decommission or production changes) are restricted by persona (`operations`) and require ServiceNow Change Requests (`CHG*`) and CMDB CI updates.
   - **Cost Visibility:** Discussed via the mandatory `cost_center` label and the $450K/month outlier project (`ANBC HCBW prod`).
2. **What Was Expanded Beyond the Transcript (Tracked in `## Open Questions`):**
   - As noted in `uploads/design-digest.md` (§11), the raw design discussion did not finalize detailed state machines for **update**, **resize**, **upgrade**, **rollback**, or **decommission** flows. This ADR establishes the uniform 4-state Day-2 contract across all seven capabilities and marks the unresolved operational policy details as explicit Open Questions (`OQ-1` .. `OQ-5`).

## Decision

Every Day-2 operation (except read-only `drift_check` and `cost` calculation) MUST flow through the same four-state model (`Requested -> Approved -> Expected -> Observed`), generating a new versioned `approved_specs` row (`ADR-GLB-004`) and a new deterministic `operation_id` (`tf-op-<operation_id>`):

| # | Day-2 Operation | Operation Type (`operation_type`) | Trigger & State Flow | Governance & Guardrails |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Update** | `update` | Modifies non-sizing configuration or metadata (e.g., labels, lifecycle rules, retention increase). Creates a new `Requested -> Approved` spec revision and runs `tf-op-<operation_id>` to update `Expected` and `Observed`. | Must pass OPA policy gate (`spp_gate.rego`). Retention (`retention_days >= 90`) may only increase, never decrease below 90 days; CMEK cannot be disabled. |
| **2** | **Resize** | `resize` | Modifies capacity, performance tier, or storage class (e.g., GCS storage class transition, Spanner processing units, DB instance tier, VM machine type). Flows through `Requested -> Approved -> Expected -> Observed`. | Validated against `apm_id` application tier rules (e.g., Tier 1 cannot downsize below HA / active-active requirements). Requires `CHG*` in `prod`. |
| **3** | **Upgrade** | `upgrade` | Advances a resource instance to a newer `ssp-module-<type>` catalog bundle version, provider version, or database/runtime engine version. Flows through `Requested -> Approved -> Expected -> Observed`. | Must run a pre-apply plan check verifying zero unintended resource replacement (`destroy-and-recreate` blocked on stateful resources without `operations` approval). |
| **4** | **Drift Detection** | `drift_check` | Scheduled or on-demand Temporal workflow in `ssp-workers` that refreshes/captures actual cloud state by **CSP resource ID** (`cloud_resource_id`) into `observed/<project_id>/terraform.tfstate` and diffs against `expected/<project_id>/terraform.tfstate`. | Security guardrail drift (CMEK removed, retention `< 90d`, public access enabled) immediately opens a high-severity ServiceNow incident linked to the CMDB CI. |
| **5** | **Rollback** | `rollback` | Reverts a resource to its prior known-good `Approved` specification version (`approved_specs.version - 1`) and re-applies `tf-op-<operation_id>` to restore `Expected` and `Observed` state. | Restricted to configurations where rollback does not cause destructive data loss on stateful storage/databases. Records mandatory operator `reason` in `audit_logs`. |
| **6** | **Decommission** | `decommission` | Controlled retirement and destruction (`terraform destroy` / removal from project desired set) of a managed resource. Transitions resource state to `decommissioned`. | Restricted to authorized personas (`operations` or resource owner in `sandbox`/`dev`; strictly `operations` + `CHG*` in `prod`). Verifies retention lock (`is_locked == false`), takes final snapshot/archive where applicable, and marks the CMDB CI as `Retired`. |
| **7** | **Cost** | `cost` | Computes estimated monthly cost at `Approved` time (SKU pricing model) and tracks actual/attributed spend per resource and per `apm_id` / `cost_center` label in `managed_resources.estimated_monthly_cost_usd`. | Surfaces cost deltas on `create`, `resize`, and `upgrade` operations and flags high-spend anomalies. |

## Requirements

- **REQ-1 (MUST):** All mutating Day-2 operations (`update`, `resize`, `upgrade`, `rollback`, `decommission`) MUST pass through `Approved` state policy validation in `ssp-cp`, record an immutable `audit_logs` entry, and execute via a deterministic Kubernetes Job (`tf-op-<operation_id>`) in `spp-platform` orchestrated by `ssp-workers`.
- **REQ-2 (MUST):** Drift detection (`drift_check`) MUST correlate resources between `Expected` and `Observed` state using the immutable Cloud Service Provider resource ID (`cloud_resource_id`), never resource name alone.
- **REQ-3 (MUST):** Any `update`, `resize`, or `upgrade` plan that would trigger a destructive resource replacement (`# forces replacement` / `delete` action in Terraform plan JSON) on a stateful resource (`google_storage_bucket`, Spanner, Cloud SQL/Postgres) MUST be blocked unless explicitly approved by the `operations` persona with a valid ServiceNow Change Request (`CHG*`).
- **REQ-4 (MUST):** `decommission` operations in `prod` MUST require `operations` persona authorization, a valid `servicenow.change_request_id` (`^CHG[0-9]{7,10}$`), and a post-destroy activity that updates the CMDB CI lifecycle status to `Retired`.
- **REQ-5 (MUST):** When `drift_check` detects a violation of `Approved` security guardrails (CMEK, `>= 90`-day retention, public access prevention), `ssp-workers` MUST automatically generate a ServiceNow incident linked to the originating ServiceNow record and CMDB CI.
- **REQ-6 (SHOULD):** In Phase 4 of the build order (`ADR-BP-002`), all seven Day-2 operations SHOULD be implemented and verified end-to-end on the GCS bucket vertical slice before `ssp-ui` or additional resource types are built.

## Guardrails

- **GR-1:** Never automatically destroy or replace stateful production storage or databases during an automated drift reconciliation, `resize`, `upgrade`, or `rollback` run without explicit Operations sign-off and a `CHG*` record.
- **GR-2:** Never allow a Day-2 `update` to weaken `Approved`-state security defaults (`cmek_enabled == true`, `retention_days >= 90`, `public_access_prevention == "enforced"`).
- **GR-3:** Never match resources by name alone during drift detection or import; always key off `cloud_resource_id`.

## Consequences

### Positive

- Unifies Day-1 creation and Day-2 lifecycle management under one state model, one Temporal `platform` namespace, and one deterministic K8s Job runner (`tf-op-<operation_id>`).
- Protects stateful cloud resources against accidental Terraform force-replacement during `update`, `resize`, or `upgrade`.

### Negative / Trade-offs

- Stateful cloud resources (such as GCS buckets with `is_locked = true` retention policies or non-empty object contents) have provider-enforced constraints on `decommission` and `rollback` that must be handled explicitly per service ADR.

## Acceptance Criteria

- [ ] `ssp-cp` exposes API endpoints for Day-2 operations (`PATCH /api/v1/resources/{id}` for update/resize/upgrade, `POST /api/v1/resources/{id}/drift-check`, `POST /api/v1/resources/{id}/rollback`, `POST /api/v1/resources/{id}/decommission`, `GET /api/v1/resources/{id}/cost`).
- [ ] `ssp-workers` implements the Temporal workflows and K8s Job runner invocations for all 7 Day-2 operations on GCS buckets in Phase 4.
- [ ] Automated tests verify that force-replacement plans on stateful resources are blocked and that drift detection identifies out-of-band changes between `expected/` and `observed/` in `gs://microdrive-dev-spp-tfstate`.

## Success Criteria

- **SC-1:**
  - **Given** a provisioned GCS bucket in `Observed` state and an out-of-band change made in GCP (e.g., modifying a bucket label or storage class outside SPP)
  - **When** the `drift_check` Temporal workflow executes `tf-op-<operation_id>` in `spp-platform`
  - **Then** `observed/<project_id>/terraform.tfstate` is updated in `gs://microdrive-dev-spp-tfstate`, the delta against `expected/<project_id>/terraform.tfstate` is recorded by `cloud_resource_id`, and `managed_resources.drift_status` transitions to `drifted`.
- **SC-2:**
  - **Given** a Day-2 `update` request on a GCS bucket that increases `retention_days` from `90` to `180`
  - **When** processed by `ssp-cp` and `ssp-workers`
  - **Then** a new `approved_specs` version is persisted, `tf-op-<operation_id>` applies the change in-place without replacing the bucket, and `Expected`/`Observed` states update to `180` days.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the 7-part Day-2 operations scope and guardrails |
| `ssp-cp` | Exposes Day-2 REST endpoints, versioned `approved_specs`, and cost estimation |
| `ssp-workers` | Implements Temporal workflows for update, resize, upgrade, drift, rollback, decommission, and cost |
| `ssp-ui` | Renders Day-2 action controls, drift badges, and cost breakdowns in Phase 5 |
| `ssp-module-<type>` | Exposes `cloud_resource_id` and supports in-place variable updates |
| `spp-factory-foundation` | Validates Day-2 drift rules via `agents/skills/drift-and-reconciliation/SKILL.md` |

## Open Questions

- [ ] **OQ-1 (Plan-vs-Observed Drift Debate — Dwayne vs. Norm):** In the design discussion (`uploads/design-digest.md` §2 & §9), Dwayne argued that a plain `terraform plan` is insufficient for drift detection because out-of-band state or cloud mutations can happen outside `Expected` state, while Norm argued `terraform plan -refresh-only` against the cloud API is sufficient. Confirm the exact mechanism by which the runner Job populates `observed/<project_id>/terraform.tfstate` (e.g., copying `expected` to a scratch workspace and running `terraform refresh` / CSP API import into `observed/<project_id>/terraform.tfstate` vs. `terraform plan -refresh-only -json`).
- [ ] **OQ-2 (Auto-Remediation vs. Alert-Only on Drift):** When non-destructive drift is detected (`Expected != Observed`), should `ssp-workers` automatically run `terraform apply` to reconcile back to `Expected`, or pause and require an operator/owner signal first?
- [ ] **OQ-3 (Decommissioning Non-Empty or Soft-Delete GCS Buckets):** Since `force_destroy = false` is enforced on GCS buckets (`ADR-SVC-001`), what is the approved operational procedure for decommissioning a bucket that still contains objects with active `>= 90`-day retention policies?
- [ ] **OQ-4 (Rollback Semantics for Irreversible Cloud Changes):** Certain cloud mutations (such as locking a GCS retention policy or upgrading a database major version) are irreversible in-place. How should `ssp-cp` classify irreversible fields so `rollback` is disabled or routed to snapshot restore?
- [ ] **OQ-5 (Cost Data Source):** Should Day-2 cost reporting in `ssp-cp` pull actual billing export rows from GCP BigQuery Cloud Billing export (keyed by `labels.apm_id` and `labels.cost_center`), or rely on static SKU rate cards in Phase 4?

## Related ADRs

- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Database](../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-AUT-001: Terraform Execution via Kubernetes Jobs](ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End (No UI)](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
