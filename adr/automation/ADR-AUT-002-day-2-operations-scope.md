# ADR-AUT-002: Day-2 Operations Scope (Update, Resize, Upgrade, Drift Detection, Rollback, Decommission, Cost)

- **ADR ID:** ADR-AUT-002
- **Level:** automation
- **Status:** Proposed
- **Owner:** Norm (Shared Mailbox: `spp-automation@tbd`, Named Owner: `Norm`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Allen / Karen [Operations])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the scope, state-transition mechanics, governance gates, and open questions for all seven **Day-2 operations** in SPP—**update**, **resize**, **upgrade**, **drift detection**, **rollback**, **decommission**, and **cost**—orchestrated via Temporal workflows in `ssp-workers` (`platform` namespace) and executed via deterministic Kubernetes Jobs (`tf-op-<operation_id>`) and scheduled observation jobs in `spp-platform`.

## Context

A self-service infrastructure control plane cannot stop at Day-1 creation (`POST /api/v1/requests`). Once a resource reaches `Observed` state, application teams and operations require complete lifecycle management:

1. **Drift Detection & Response (Dwayne's Approach + Alert-Only in MVP):**
   - In the design session (`uploads/design-digest.md`), Dwayne and Norm debated whether a plain `terraform plan` was sufficient for drift detection (Dwayne argued no, because out-of-band state or cloud mutations occur outside `Expected` state).
   - **Resolved Decision (`OQ-1` & `OQ-2`):** SPP adopts **Dwayne's approach**: an **independent scheduled capture job** reads actual resource configuration directly from **GCP APIs (keyed by immutable CSP resource ID, `cloud_resource_id`)**, writes the `Observed` state to GCS (`gs://microdrive-dev-spp-tfstate/observed/<project_id>/terraform.tfstate`), and compares `Observed` vs. `Expected` (`gs://microdrive-dev-spp-tfstate/expected/<project_id>/terraform.tfstate`)—explicitly **not** `terraform plan -refresh-only`. When drift is detected (`Observed != Expected`), the MVP behavior is **ALERT ONLY (no auto-remediation in MVP)**.
2. **Operations Gate & Persona Permissions:**
   - Operations cannot be bypassed (Allen/Norm). Certain fields and destructive actions (such as delete/decommission or production changes) are restricted by persona (`operations`). *(Note: ServiceNow CRs/incidents and CMDB CI updates are out of scope for the `microdrive-dev` MVP and retained only as future post-MVP integration hooks per `ADR-BP-001`.)*
3. **Day-2 Decommission, Rollback, and Cost (Open Questions with Proposed Defaults):**
   - As noted in `uploads/design-digest.md` (§11), the raw design discussion did not finalize detailed rules for **decommission**, **rollback**, or **cost** calculation. Those three remain tracked as open questions (`OQ-3` .. `OQ-5`) with explicit proposed defaults for the MVP (decommission refuses non-empty buckets with `force_destroy = false`; rollback re-applies the last approved spec with irreversible attributes flagged; cost calculation is out of scope for the MVP beyond the `cost_center` label).

## Decision

Every mutating Day-2 operation (`update`, `resize`, `upgrade`, `rollback`, `decommission`) flows through the four-state model (`Requested -> Approved -> Expected -> Observed`), generating a new versioned `approved_specs` row (`ADR-GLB-004`) and a new deterministic `operation_id` (`tf-op-<operation_id>`), while `drift_check` runs as an independent GCP API capture-and-compare workflow:

| # | Day-2 Operation | Operation Type (`operation_type`) | Trigger & State Flow | Governance & Guardrails |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Update** | `update` | Modifies non-sizing configuration or metadata (e.g., labels, lifecycle rules, retention increase). Creates a new `Requested -> Approved` spec revision and runs `tf-op-<operation_id>` to update `Expected` and `Observed`. | Must pass OPA policy gate (`spp_gate.rego`). Retention (`retention_days >= 90`) may only increase, never decrease below 90 days; CMEK cannot be disabled. |
| **2** | **Resize** | `resize` | Modifies capacity, performance tier, or storage class (e.g., GCS storage class transition, Spanner processing units, DB instance tier, VM machine type). Flows through `Requested -> Approved -> Expected -> Observed`. | Validated against `apm_id` application tier rules (e.g., Tier 1 cannot downsize below HA / active-active requirements) and `operations_gate`. |
| **3** | **Upgrade** | `upgrade` | Advances a resource instance to a newer `ssp-module-<type>` catalog bundle version, provider version, or database/runtime engine version. Flows through `Requested -> Approved -> Expected -> Observed`. | Must run a pre-apply plan check verifying zero unintended resource replacement (`destroy-and-recreate` blocked on stateful resources without `operations` approval). |
| **4** | **Drift Detection** | `drift_check` | **Independent scheduled (or on-demand) capture job** in `ssp-workers` that reads actual resource configuration directly from **GCP APIs keyed by immutable CSP resource ID (`cloud_resource_id`)**, writes `observed/<project_id>/terraform.tfstate` in `gs://microdrive-dev-spp-tfstate`, and compares `Observed` vs. `Expected` (`expected/<project_id>/terraform.tfstate`)—**NOT** `terraform plan -refresh-only`. | **ALERT ONLY in MVP (no auto-remediation):** sets `managed_resources.drift_status = 'drifted'`, records the attribute diff in `audit_logs`, and emits an alert without running an automated `terraform apply` overwrite. |
| **5** | **Rollback** | `rollback` | *Proposed default (see `OQ-4`):* Re-applies the prior known-good `Approved` specification version (`approved_specs.version - 1`) via `tf-op-<operation_id>`, while flagging irreversible cloud attributes so destructive replacements are blocked. | Restricted to configurations where rollback does not cause destructive data loss on stateful storage/databases. Records mandatory operator `reason` in `audit_logs`. |
| **6** | **Decommission** | `decommission` | *Proposed default (see `OQ-3`):* Controlled retirement and destruction (`terraform destroy` / removal from project desired set) of a managed resource; refuses non-empty GCS buckets (`force_destroy = false`). Transitions resource state to `decommissioned`. | Restricted to authorized personas (`operations` or resource owner in `sandbox`/`dev`; strictly `operations` in `prod`). Verifies retention lock (`is_locked == false`) and empty bucket state. |
| **7** | **Cost** | `cost` | *Proposed default (see `OQ-5`):* Active cost calculation/billing export integration is **out of scope for the MVP**; MVP enforces the mandatory `cost_center` label (`ADR-GLB-006`) and reserves `managed_resources.estimated_monthly_cost_usd` as a schema field for post-MVP. | Mandatory `cost_center` label enforced at `Requested` and `Approved` time. |

## Requirements

- **REQ-1 (MUST):** All mutating Day-2 operations (`update`, `resize`, `upgrade`, `rollback`, `decommission`) MUST pass through `Approved` state policy validation in `ssp-cp`, record an immutable `audit_logs` entry, and execute via a deterministic Kubernetes Job (`tf-op-<operation_id>`) in `spp-platform` orchestrated by `ssp-workers`.
- **REQ-2 (MUST):** Drift detection (`drift_check`) MUST use an **independent scheduled capture job** that reads actual resource configuration directly from **GCP APIs keyed by immutable CSP resource ID (`cloud_resource_id`)**, writes `observed/<project_id>/terraform.tfstate` to GCS, and compares `Observed` vs. `Expected`—it MUST NOT rely on `terraform plan -refresh-only`.
- **REQ-3 (MUST):** When `drift_check` detects `Observed != Expected`, the MVP behavior MUST be **alert-only** (`managed_resources.drift_status = 'drifted'`, diff recorded in `audit_logs`, alert emitted) with **no automated remediation (`terraform apply`)** in the MVP.
- **REQ-4 (MUST):** Any `update`, `resize`, or `upgrade` plan that would trigger a destructive resource replacement (`# forces replacement` / `delete` action in Terraform plan JSON) on a stateful resource (`google_storage_bucket`, Spanner, AlloyDB/Postgres) MUST be blocked unless explicitly approved by the `operations` persona.
- **REQ-5 (MUST):** `decommission` operations MUST enforce persona authorization (`operations`), keep `force_destroy = false` on GCS buckets (refusing non-empty buckets by default), verify `retention_policy.is_locked == false`, and update `managed_resources.current_state = 'decommissioned'` in AlloyDB (`spp_platform`).
- **REQ-6 (SHOULD):** In Phase 4 of the build order (`ADR-BP-002`), Day-2 workflows SHOULD be verified end-to-end on the GCS bucket vertical slice before `ssp-ui` or additional resource types are built.

## Guardrails

- **GR-1:** Never run automated drift remediation (`terraform apply` on drift) in the MVP; drift detection is strictly **alert-only**, and never automatically destroy or replace stateful storage or databases.
- **GR-2:** Never use `terraform plan -refresh-only` as the sole drift detection mechanism; always populate `observed/<project_id>/terraform.tfstate` from an independent GCP API capture job keyed by `cloud_resource_id`.
- **GR-3:** Never allow a Day-2 `update` to weaken `Approved`-state security defaults (`cmek_enabled == true`, `retention_days >= 90`, `public_access_prevention == "enforced"`), and never set `force_destroy = true` on GCS buckets.

## Consequences

### Positive

- Independent GCP API capture into `observed/<project_id>/terraform.tfstate` detects out-of-band cloud and state mutations without mutating or trusting the `Expected` Terraform state file.
- Alert-only drift handling in the MVP guarantees zero risk of an automated reconciliation loop accidentally overwriting or destroying live resources.

### Negative / Trade-offs

- Requires a GCP API reader / state-observation activity in `ssp-workers` per supported resource type (starting with `google_storage_bucket` in Phase 4) to serialize actual GCP resource attributes into `observed/<project_id>/terraform.tfstate`.

## Acceptance Criteria

- [ ] `ssp-cp` exposes API endpoints for Day-2 operations (`PATCH /api/v1/resources/{id}` for update/resize/upgrade, `POST /api/v1/resources/{id}/drift-check`, `POST /api/v1/resources/{id}/rollback`, `POST /api/v1/resources/{id}/decommission`).
- [ ] `ssp-workers` implements the independent GCP API capture job writing `observed/<project_id>/terraform.tfstate` in `gs://microdrive-dev-spp-tfstate`, compares `Observed` vs. `Expected` by `cloud_resource_id`, and emits an alert-only drift record without auto-remediation.
- [ ] Automated tests verify that force-replacement plans on stateful resources are blocked and that out-of-band GCP bucket changes are flagged as `drifted` (alert-only).

## Success Criteria

- **SC-1:**
  - **Given** a provisioned GCS bucket in `Observed` state and an out-of-band change made in GCP (e.g., modifying a bucket label or storage class outside SPP)
  - **When** the independent scheduled capture job reads the bucket from the GCP Storage API by `cloud_resource_id` and updates `observed/<project_id>/terraform.tfstate` in `gs://microdrive-dev-spp-tfstate`
  - **Then** the comparator detects `Observed != Expected`, sets `managed_resources.drift_status = 'drifted'`, logs an alert in `audit_logs`, and performs **no** automated `terraform apply`.
- **SC-2:**
  - **Given** a Day-2 `update` request on a GCS bucket that increases `retention_days` from `90` to `180`
  - **When** processed by `ssp-cp` and `ssp-workers`
  - **Then** a new `approved_specs` version is persisted, `tf-op-<operation_id>` applies the change in-place without replacing the bucket, and `Expected`/`Observed` states update to `180` days.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the Day-2 operations scope, independent GCP API drift capture, and alert-only MVP rule |
| `ssp-cp` | Exposes Day-2 REST endpoints, versioned `approved_specs`, and drift alert status |
| `ssp-workers` | Implements Temporal workflows for update, resize, upgrade, independent GCP API drift capture + alert, rollback, and decommission |
| `ssp-ui` | Renders Day-2 action controls and drift alert badges in Phase 5 |
| `ssp-module-<type>` | Exposes `cloud_resource_id` and enforces `force_destroy = false` |
| `spp-factory-foundation` | Validates Day-2 drift rules via `agents/skills/drift-and-reconciliation/SKILL.md` |

## Open Questions

- [x] **OQ-1 (Plan-vs-Observed Drift Debate — RESOLVED 2026-10-21):** *Resolved:* Drift detection uses **Dwayne's approach**: an independent scheduled capture job reads actual resource config from GCP APIs (keyed by CSP resource ID, `cloud_resource_id`), writes `Observed` state to `gs://microdrive-dev-spp-tfstate/observed/<project_id>/terraform.tfstate`, and compares `Observed` vs. `Expected` (NOT `terraform plan -refresh-only`).
- [x] **OQ-2 (Auto-Remediation vs. Alert-Only on Drift — RESOLVED 2026-10-21):** *Resolved:* On drift (`Observed != Expected`), the platform is **ALERT ONLY** with **no auto-remediation in the MVP**.
- [ ] **OQ-3 (Decommissioning Non-Empty or Soft-Delete GCS Buckets):** Since `force_destroy = false` is enforced on GCS buckets (`ADR-SVC-001`), what is the final operational procedure for decommissioning a bucket that contains objects? *(Proposed default: `decommission` refuses non-empty buckets and keeps `force_destroy = false`.)*
- [ ] **OQ-4 (Rollback Semantics for Irreversible Cloud Changes):** How should `ssp-cp` handle rollback requests when an attribute change is irreversible in-place? *(Proposed default: `rollback` re-applies the last `Approved` spec version, with irreversible attributes flagged and blocked from destructive replacement.)*
- [ ] **OQ-5 (Cost Scope & Data Source):** Should Day-2 cost calculation integrate with BigQuery Cloud Billing export or static SKU rate cards? *(Proposed default: active cost calculation is **out of MVP**; MVP enforces the `cost_center` label only.)*

## Related ADRs

- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Database](../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-AUT-001: Terraform Execution via Kubernetes Jobs](ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End (No UI)](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
