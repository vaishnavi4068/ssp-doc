# ADR-AUT-002: Day-2 Operations, Drift Detection, and Deletion Governance

- **ADR ID:** ADR-AUT-002
- **Level:** automation
- **Status:** Proposed
- **Owner:** Norm (Shared Mailbox: `spp-automation@tbd`, Named Owner: `Norm`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Allen / Karen [Operations])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the Day-2 operations model (`update`, `delete`, `import`, and scheduled/on-demand drift detection), JSON-pointer drift comparison (`Expected` vs. `Observed` minus `drift_ignore_paths`), drift finding taxonomy (`out_of_band_change`, `config_divergence`, `missing_in_cloud`, `unmanaged_in_cloud`), **alert-only** drift policy (never auto-reapply), and the mandatory human-approval gate for any resource deletion, destroy, or replacement in **any** environment (`nonprod` or `prod`).

## Context

From the design session (`uploads/design-digest.md`), the sanitized four-gate design package (`workflows.md`, `lifecycle.md`, `gates.md`, `raw/idp_state_model.reconstructed.sql`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)), and user overrides:

1. **Every Day-2 Change Is a New Request Referring to `base_approval_id`:**
   - In the four-gate model (`ADR-GLB-003`, `ADR-GLB-004`), `idp.request` has `action IN ('create', 'update', 'delete', 'import')` and `base_approval_id` pointing to the prior active `idp.approval`.
   - Updating, resizing, or deleting a resource creates a new immutable `idp.request` row (`OBSERVED -> REQUESTED -> APPROVED -> EXPECTED -> OBSERVED`), never mutating a prior `request` or `approval` row.
2. **Scheduled Drift Scans & JSON-Pointer Drift Comparison:**
   - Temporal Schedule `drift-<project_id>` triggers `StateUnitReconcilerWorkflow` (`su-gcp-<project_id>`) with signal `drift_scan`, using the schedule window (e.g., `2026-10-23T06`) as `run_key` (`op:<state_unit_id>:r<rev>:refresh_plan:2026-10-23T06` → Kubernetes Job `tf-refresh-plan-<20hex>`).
   - The scan runs `terraform plan -refresh-only -detailed-exitcode` (writing the snapshot to `gs://microdrive-dev-spp-tfstate/projects/<project_id>/observed/scan-<window>/plan.json` without mutating `default.tfstate` serial) and/or Cloud Asset Inventory (`source = 'asset_inventory'` keyed by `idp_resource_id` / `cloud_resource_id`).
   - Drift is computed as a **JSON-pointer diff**: for each JSON path in the `Expected` tfvars entry, minus `idp.resource_kind.drift_ignore_paths` (e.g., `['/force_destroy']` on buckets/Spanner instances, `['/ddl', '/deletion_protection']` on Spanner databases, plus `processing_units` when Spanner `autoscaling_config` is set), the comparer checks the `Observed` projection (`idp.resource_observed.projection`). `labels` and `iam_bindings` are compared as whole maps so an out-of-band IAM member or removed label surfaces immediately as drift.
3. **User Overrides on Drift and Deletions:**
   - **Drift Is Strictly Alert-Only (Never Auto-Reapply):** Even for critical guardrail drift (`GCS-PAP-001`, `GCS-UBLA-001`, `GCS-ENC-001`, public IAM), SPP **never** auto-reapplies Terraform. `REMEDIATING` status and `'reapplied'` resolution from the source DDL are removed. Remediation always goes through a new human-approved `request`.
   - **No Deletion/Destroy/Replace Without Explicit Human Approval in ANY Environment:** Neither `action = 'delete'` nor any Terraform plan with `destroy > 0` or `replace > 0` may use `AUTO_APPROVED` in `nonprod` or `prod`.

## Decision

### 1. Day-2 Request Actions & Lifecycle Transitions

| Action / Operation | `idp.request.action` / `tf_operation.phase` | Four-Gate Flow | Governance & Guardrails |
| :--- | :--- | :--- | :--- |
| **Update / Resize / Upgrade** | `action = 'update'` (`base_approval_id` set) → `plan` + `apply` | `OBSERVED -> REQUESTED -> APPROVED -> EXPECTED -> OBSERVED` | Enforces `NAM-IMM-001` (cannot rename resource). Evaluates OPA at `requested`, `approved`, and `plan`. If `plan_summary.destroy > 0` or `replace > 0`, blocks with `destroy_without_delete_request` unless explicitly approved by human approvers. |
| **Delete / Decommission** | `action = 'delete'` (`base_approval_id` set) → `destroy_plan` + `apply` | `OBSERVED -> REQUESTED -> APPROVED -> EXPECTED -> OBSERVED` (`resource.lifecycle` `active -> deleting -> deleted`, sets `deleted_at`) | **Requires explicit human approval in BOTH `nonprod` and `prod` (never `AUTO_APPROVED`).** On `gcs_bucket`, `force_destroy` is always `false` (`GCS-DEL-001`, bucket must be emptied first). On `spanner_database`, requires human approval before `deletion_protection` can be cleared for removal. |
| **Brownfield Import** | `action = 'import'` → `import` + `plan` | `REQUESTED -> APPROVED -> EXPECTED -> OBSERVED` (`observation.source = 'import'`) | Enforces `NAM-LEG-001`: preserves existing cloud resource name and injects label `idp_naming = "legacy"`. |
| **Scheduled / On-Demand Drift Scan** | Temporal Schedule `drift-<project_id>` → `phase = 'refresh_plan'` (or `source = 'asset_inventory'`) | `OBSERVED -> OBSERVED` (`resource.sync_status` → `IN_SYNC` or `DRIFTED`) | Runs `terraform plan -refresh-only -detailed-exitcode` (`tf_exit_code = 2` means drift detected; does not advance `state_serial`). Writes snapshot to `gs://microdrive-dev-spp-tfstate/projects/<project_id>/observed/scan-<window>/plan.json`. **Alert-only.** |

### 2. Drift Finding Taxonomy & Lifecycle (`idp.drift_finding`)

- **`drift_kind` values:**
  1. `out_of_band_change`: Refreshed cloud value differs from last-applied state (e.g., Spanner `processing_units` changed from `100` to `300` in GCP Console, or bucket `public_access_prevention` changed to `inherited`).
  2. `config_divergence`: Current state already differs from the current `Expected` revision.
  3. `missing_in_cloud`: Resource exists in `Expected` state (`idp.resource.lifecycle = 'active'`), but `resource_observed.exists_in_cloud = false`.
  4. `unmanaged_in_cloud`: Cloud Asset Inventory (`source = 'asset_inventory'`) discovers a resource in a managed project lacking a matching `idp_resource_id` / active `Expected` member.
- **`status` values (Alert-Only Override):**
  - `OPEN` → `ACKNOWLEDGED` → `RESOLVED` or `ACCEPTED` *(partial unique index `drift_finding_open_uq` on `(resource_id, attribute_path) WHERE status IN ('OPEN', 'ACKNOWLEDGED')` prevents duplicate open findings).*
  - *(Note: `REMEDIATING` is excluded by SPP's alert-only override.)*
- **`resolution` values (Alert-Only Override):**
  - `spec_updated` (resolved via a new approved `update` request that Either restores the cloud resource to match `Expected` or updates `Expected` to adopt a valid non-guardrail change)
  - `accepted_risk` (requires explicit governance sign-off)
  - `resource_deleted` (resolved via a new human-approved `delete` request)
  - *(Note: `'reapplied'` via automatic background overwrite is excluded by SPP's alert-only override.)*
- **Per-Kind `drift_ignore_paths` (`idp.resource_kind`):**
  - `gcs_bucket`: `['/force_destroy']`
  - `spanner_instance`: `['/force_destroy']` (plus `/processing_units` when `autoscaling_config` is non-null)
  - `spanner_database`: `['/ddl', '/deletion_protection']` (initial DDL is owned by the application's migration pipeline after creation; `deletion_protection` is a Terraform-side guard)

## Requirements

- **REQ-1 (MUST):** Every mutating Day-2 action (`update`, `delete`, `import`) MUST create a new `idp.request` row referencing `base_approval_id` (for `update`/`delete`) and pass through the `Approved` and `Expected` gates.
- **REQ-2 (MUST):** No deletion (`action = 'delete'`), `destroy_plan`, or Terraform plan with `plan_summary.destroy > 0` or `plan_summary.replace > 0` MAY be auto-approved (`AUTO_APPROVED`) in **any** environment (`nonprod` or `prod`); explicit human approval in `idp.approval_decision` is mandatory everywhere.
- **REQ-3 (MUST):** Any `plan` for a `create` or `update` revision that produces `plan_summary.destroy > 0` or `plan_summary.replace > 0` without an explicit human-approved destructive request MUST transition `idp.expected_revision.status` to `'BLOCKED'` with `blocked_reason = 'destroy_without_delete_request'`.
- **REQ-4 (MUST):** Scheduled drift scans (`drift-<project_id>`) MUST use the schedule window as `run_key` (e.g., `2026-10-23T06`), write `observed/scan-<window>/plan.json` to `gs://microdrive-dev-spp-tfstate`, and compare `Expected` vs. `Observed` by JSON pointer minus `resource_kind.drift_ignore_paths`.
- **REQ-5 (MUST):** When drift is detected, `ssp-workers` MUST record `idp.observation` (`drift_detected = true`), upsert `idp.resource_observed` (if `projection_sha256` changed), insert/update `idp.drift_finding` (`status = 'OPEN'`), set `idp.resource.sync_status = 'DRIFTED'`, and emit a `drift.detected` `idp.gate_event` (**alert-only**, never auto-running `terraform apply`).

## Guardrails

- **GR-1:** Never allow `AUTO_APPROVED` / `auto_approved` on any `delete` request or destructive plan in `nonprod` or `prod`.
- **GR-2:** Never auto-reapply Terraform on drift; `drift_finding` is strictly alert-only, and remediation requires a new approved request.
- **GR-3:** Never set `force_destroy = true` on `gcs_bucket` or `spanner_instance`.
- **GR-4:** Never report drift on paths listed in `resource_kind.drift_ignore_paths` (`/force_destroy`, `/ddl`, `/deletion_protection`, or autoscaled `/processing_units`).

## Consequences

### Positive

- Whole-map comparison of `labels` and `iam_bindings` catches out-of-band IAM grants and label tampering that legacy systems missed.
- Alert-only drift handling and mandatory human approval on all deletes/replaces in both `nonprod` and `prod` eliminate accidental data destruction.

### Negative / Trade-offs

- Remediating out-of-band drift requires submitting and approving a new `idp.request` rather than an automated background apply.

## Acceptance Criteria

- [ ] `ssp-workers` implements `drift-<project_id>` schedules, `refresh_plan` Job execution (`tf-refresh-plan-<20hex>`), and the JSON-pointer drift comparer honoring `resource_kind.drift_ignore_paths`.
- [ ] `ssp-cp` and `ssp-workers` block `destroy_without_delete_request` and reject `AUTO_APPROVED` for any `action = 'delete'` in both `nonprod` and `prod`.
- [ ] `specs/examples/spanner.gates.json` drift scenario (`processing_units` changed from `100` to `300` -> `drift_kind = 'out_of_band_change'`, `severity = 'medium'`, `status = 'OPEN'`) passes validation.

## Success Criteria

- **SC-1:**
  - **Given** a non-autoscaled `spanner_instance` in `OBSERVED` state with `processing_units = 100` that is scaled out-of-band to `300` in the GCP Console
  - **When** the `drift-<project_id>` scan runs `tf-refresh-plan-<20hex>` for window `2026-10-23T06`
  - **Then** `tf_exit_code` is `2`, `state_serial` remains unchanged (`6 -> 6`), `idp.drift_finding` records `drift_kind = 'out_of_band_change'`, `attribute_path = '/processing_units'`, `expected_value = 100`, `observed_value = 300`, `severity = 'medium'`, `status = 'OPEN'`, and **no** auto-reapply Job is launched.
- **SC-2:**
  - **Given** a `delete` request or a Terraform plan with `destroy > 0` in `nonprod` or `prod`
  - **When** evaluated by `ApprovalGateWorkflow` and the `plan` OPA gate
  - **Then** `AUTO_APPROVED` is forbidden and execution is blocked until explicit human approval is recorded in `idp.approval_decision`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines Day-2 request actions, JSON-pointer drift comparison, alert-only policy, and universal human-approval delete guardrail |
| `ssp-cp` | Exposes `update`, `delete`, `import`, and drift finding APIs; blocks `AUTO_APPROVED` deletes |
| `ssp-workers` | Runs `drift-<project_id>`, `tf-refresh-plan-<20hex>`, JSON-pointer drift comparer, and `destroy_without_delete_request` check |
| `ssp-ui` | Displays open drift findings (`idp.v_resource_status.open_drift_count`) and human delete approval workflows |
| `ssp-module-gcs-bucket`, `ssp-module-spanner` | Enforces `force_destroy = false` and `deletion_protection = true` |
| `spp-factory-foundation` | Verifies drift comparer against `specs/examples/spanner.gates.json` |

## Open Questions

- [x] **OQ-1 (Drift Response: Alert-Only vs. Auto-Reapply — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Drift is **alert-only**; never auto-reapply. Remediation goes through a new approved request.
- [x] **OQ-2 (Destructive Plan Approval in Nonprod and Prod — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Explicit human approval is required for **any** deletion, destroy, or replace of any resource in **any** environment (`nonprod` and `prod`); no `AUTO_APPROVED` for deletes.

## Related ADRs

- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-009: Resource Kind Registry](../global/ADR-GLB-009-resource-kind-registry.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-AUT-001: Temporal Orchestration and Terraform Execution via Deterministic Kubernetes Jobs](ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-SVC-001: GCS Bucket End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](../endpoint-service/ADR-SVC-002-spanner-instance-and-database.md)
