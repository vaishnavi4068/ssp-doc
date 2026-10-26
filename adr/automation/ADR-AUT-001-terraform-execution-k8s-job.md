# ADR-AUT-001: Temporal Orchestration and Terraform Execution via Deterministic Kubernetes Jobs

- **ADR ID:** ADR-AUT-001
- **Level:** automation
- **Status:** Proposed
- **Owner:** Dwayne (Shared Mailbox: `spp-automation@tbd`, Named Owner: `Dwayne`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the Temporal workflow topology (`RequestWorkflow`, `ApprovalGateWorkflow`, `StateUnitReconcilerWorkflow`, and `drift-<project_id>` Schedule), signal contracts, `pre_apply`/`post_apply` lifecycle task execution, and deterministic **one-Kubernetes-Job-per-Terraform-run** execution architecture (`tf-<phase>-<first 20 hex of sha256(operation_id)>`) inside the `spp-platform` namespace on the SPP GKE cluster writing state to **`gs://microdrive-dev-spp-tfstate`**.

## Context

From the design session (`uploads/design-digest.md`), the sanitized four-gate design package (`workflows.md`, `lifecycle.md`, `data-model.md`, `raw/idp_state_model.reconstructed.sql`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)), and user overrides:

1. **Approval Does Not Go Straight to Terraform:** In the four-gate model (`ADR-GLB-003`), approval of a single resource request (`RequestWorkflow` + `ApprovalGateWorkflow`) persists the `idp.approval` row and signals the target project's `StateUnitReconcilerWorkflow` (`su-gcp-<project_id>`) using **signal-with-start** (`approval_ready {approval_id}`). The first approval for a project starts the reconciler; subsequent approvals queue on it, guaranteeing **one writer per state file (`INV-8`)**.
2. **Seven-Step Reconciler Loop (`StateUnitReconcilerWorkflow`):**
   1. Receives `approval_ready {approval_id}` via signal-with-start (and checks `state_unit.status != 'frozen'`, `INV-9`).
   2. Executes all `pre_apply` `idp.lifecycle_task` rows (`ad_group`, `vpc_sc_ingress`, `vpc_sc_project_membership`, `enable_service`) for added/modified members; if any fails, blocks with `blocked_reason = 'prerequisite_failed'`.
   3. Renders a complete `Expected` revision (`expected/rev-NNNNNN/{terraform.tfvars.json, manifest.json}`) in `gs://microdrive-dev-spp-tfstate` with `ifGenerationMatch=0` (create-only), recording all active resources in `idp.expected_revision_member` (`unchanged`, `added`, `modified`, `removed`) and advancing `state_unit.current_expected_rev` via optimistic concurrency (`WHERE current_expected_rev IS NOT DISTINCT FROM :prev_rev`).
   4. Verifies every member's `approved_spec_sha256` against `idp.approval.approved_spec_sha256` (`INV-6`) and launches the `plan` Kubernetes Job (`tf-plan-<20hex>`).
   5. Evaluates `plan.json` (`terraform show -json <planfile>`) against OPA (`stage = 'plan'`, `INV-4`); blocks if `destroy > 0` or `replace > 0` lacks an explicit human-approved delete request (`blocked_reason = 'destroy_without_delete_request'`).
   6. Launches the `apply` Kubernetes Job (`tf-apply-<20hex>`) against the exact saved `planfile` of that revision (`INV-5`).
   7. Captures `post_apply` `idp.observation`, upserts `<= 2 KB` `idp.resource_observed` projections (when `projection_sha256` changes), executes `post_apply` `idp.lifecycle_task` rows (`notify_owner`, `backup_enroll`, etc.), and appends `idp.gate_event` audit rows.
3. **One Kubernetes Job per Run in `spp-platform` (Overriding `idp-runners`):** While the source examples named the runner namespace `idp-runners`, SPP's locked runtime architecture (`ADR-CLD-GCP-001`) runs all Terraform runner Jobs in **`spp-platform`** on the tainted `spp-pool` node pool (`workload=spp` / `dedicated=spp:NoSchedule`) and stores all state in **`gs://microdrive-dev-spp-tfstate`**.

## Decision

### 1. Temporal Workflows, IDs, and Signals (`ssp-workers`)

| Workflow / Schedule | Deterministic ID | Gate Transition | Signals / Triggers | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **`RequestWorkflow`** | `req-<request_id>` | `REQUESTED` → `APPROVED` | Duplicate starts rejected by Temporal; `cancel` signal | Evaluates `requested` and `approved` OPA stages, invokes `ApprovalGateWorkflow`, persists `idp.approval` and `idp.lifecycle_task` rows, and signals `su-gcp-<project_id>` via signal-with-start. |
| **`ApprovalGateWorkflow`** | `apr-<request_id>` | Inside `APPROVED` | `approval_response {decision_id, status, responded_by, comment}` | Sequential human approvers per `idp.approval_gate_config` (`self_approval = 'deny'`, SLA timers, follow-up reminders, manager escalation, 13-day `max_wait_days`, `auto_close`, and 30-day `valid_until`; see `ADR-BP-003`). |
| **`StateUnitReconcilerWorkflow`** | `su-gcp-<project_id>` | `APPROVED` → `EXPECTED` → `OBSERVED` | `approval_ready {approval_id}` (signal-with-start), `drift_scan`, `freeze`, `unfreeze`; uses `continue-as-new` | Serializes all `plan`, `apply`, `refresh_plan`, `destroy_plan`, and `import` operations for one GCP project (`INV-8`). |
| **`DriftSchedule`** | `drift-<project_id>` | `OBSERVED` → `OBSERVED` | Temporal Schedule signaling `su-gcp-<project_id>` with `drift_scan` | Uses schedule window (e.g., `2026-10-23T06`) as `run_key` so retried scans reattach deterministically (`ADR-AUT-002`). |

### 2. Deterministic `operation_id` and Kubernetes Job Naming (`idp.k8s_job_name`)

- **`operation_id` Format:** `op:<state_unit_id>:r<revision_no>:<phase>:<run_key>`
  - Example: `op:af42f828-3378-5ee2-8e9b-2378d2314f97:r1:plan:1`
  - Allowed `phase` values: `plan`, `apply`, `refresh_plan`, `destroy_plan`, `import`
  - `run_key`: `'1'` by default (only incremented on a deliberate human/operator re-run; scheduled drift scans use the schedule window string such as `'2026-10-23T06'`).
- **Kubernetes Job Name Formula (Python & SQL Twin):**
  ```python
  import hashlib

  def k8s_job_name(operation_id: str, phase: str) -> str:
      return f"tf-{phase.replace('_', '-')}-{hashlib.sha256(operation_id.encode('utf-8')).hexdigest()[:20]}"
  ```
  ```sql
  CREATE OR REPLACE FUNCTION idp.k8s_job_name(p_operation_id text, p_phase text)
  RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT 'tf-' || replace(p_phase, '_', '-') || '-'
        || substr(encode(sha256(convert_to(p_operation_id, 'UTF8')), 'hex'), 1, 20)
  $$;
  ```
  - Example: `tf-plan-eba5f9ebf4fafecad8e9` (at most `36` characters, well under Kubernetes' `63`-character DNS label limit).
  - Enforced by AlloyDB constraint `CONSTRAINT tf_operation_job_name_derived CHECK (k8s_job_name = idp.k8s_job_name(operation_id, phase))`.
- **Idempotent Reattachment on Retry:**
  - When a Temporal activity retries after a worker restart, it reuses the same `operation_id`, derives the identical `k8s_job_name`, receives `409 AlreadyExists` (or finds the Job via `read_namespaced_job` in `spp-platform`), attaches to the running Job, and polls every ~30 seconds until completion (`INV-7`).
- **Terraform Exit Codes (`tf_exit_code`):**
  - `0`: Succeeded with no diff (`apply` succeeded, or `plan` / `refresh_plan` had zero changes).
  - `1`: Terraform error (`status = 'FAILED'`).
  - `2`: Succeeded with non-empty diff (`plan -detailed-exitcode` or `plan -refresh-only -detailed-exitcode` detected changes; `status = 'SUCCEEDED'`).

### 3. Pre-Apply and Post-Apply Lifecycle Tasks (`idp.lifecycle_task`)

Materialized from `approved_spec` into `idp.lifecycle_task` with deterministic `task_key = "<task_type>:<target>"` (`UNIQUE (approval_id, task_key)`):
- **`pre_apply` tasks** (must reach `SUCCEEDED` before `expected_revision` can apply):
  - `ad_group`: Provisions/verifies directory-service group (`PRQ-001`).
  - `vpc_sc_ingress`: Configures VPC Service Controls ingress rule (`PRQ-002`).
  - `vpc_sc_project_membership`: Verifies/adds target project into `<lob>_<env>_restricted_perimeter` (`PRQ-004`).
  - `enable_service`: Enables required GCP API such as `spanner.googleapis.com` (`PRQ-003`).
- **`post_apply` tasks** (executed after `apply` succeeds and `Observed` state is captured):
  - `notify_owner`: Notifies `metadata.owner` / `shared_mailbox`.
  - `backup_enroll`: Registers backup schedule verification where applicable.
  - `cmdb_register` / `dataportal_register`: Retained in the `task_type` `CHECK` constraint as deferred post-MVP placeholders (`status = 'SKIPPED'` in MVP; ServiceNow/CMDB out of scope).

## Requirements

- **REQ-1 (MUST):** `ssp-workers` MUST execute every Terraform phase (`plan`, `apply`, `refresh_plan`, `destroy_plan`, `import`) as an isolated Kubernetes Job in namespace `spp-platform` on node pool `spp-pool` (`workload=spp` / `dedicated=spp:NoSchedule`).
- **REQ-2 (MUST):** Every `idp.tf_operation` row and Kubernetes Job MUST use `operation_id = "op:<state_unit_id>:r<revision_no>:<phase>:<run_key>"` and `k8s_job_name = idp.k8s_job_name(operation_id, phase)` (`tf-<phase>-<20hex>`), reattaching on `AlreadyExists` during activity retry.
- **REQ-3 (MUST):** `StateUnitReconcilerWorkflow` (`su-gcp-<project_id>`) MUST be started/signaled via `signal-with-start` (`approval_ready {approval_id}`), MUST check `state_unit.status != 'frozen'` (`INV-9`) before `plan` and `apply`, and MUST serialize all state-file operations for that project (`INV-8`).
- **REQ-4 (MUST):** `apply` (`tf-apply-<20hex>`) MUST execute the exact saved `planfile` produced by `plan` (`tf-plan-<20hex>`) for the same `revision_id` after verifying `INV-4`, `INV-5`, and `INV-6`.
- **REQ-5 (MUST):** `idp.tf_operation.status` MUST be updated only from the Kubernetes Job's terminal status and `tf_exit_code` (`0`, `1`, `2`), never from a dispatch/submission call (`INV-7`).

## Guardrails

- **GR-1:** Never run `terraform` inside the long-lived `ssp-workers` pod.
- **GR-2 (`INV-7`):** Never mark a request or operation `OBSERVED` / `SUCCEEDED` before the Kubernetes Job finishes and `tf_exit_code` is recorded.
- **GR-3 (`INV-8`):** Never allow two Terraform Jobs to write concurrently to the same project state unit (`su-gcp-<project_id>` + GCS `default.tflock`).
- **GR-4 (`INV-9`):** Never run `plan` or `apply` when `idp.state_unit.status = 'frozen'`.

## Consequences

### Positive

- Deterministic `tf-<phase>-<20hex>` Job names (<= 36 chars) fit comfortably inside Kubernetes' 63-character label limit and are enforced by both Python and PostgreSQL (`idp.k8s_job_name`).
- Signal-with-start on `su-gcp-<project_id>` batches/serializes concurrent resource approvals in the same GCP project without race conditions.

### Negative / Trade-offs

- Long-running `StateUnitReconcilerWorkflow` instances must call Temporal `continue-as-new` periodically while preserving queued `approval_ready` and `drift_scan` signals.

## Acceptance Criteria

- [ ] `ssp-workers` implements `RequestWorkflow` (`req-<request_id>`), `ApprovalGateWorkflow` (`apr-<request_id>`), `StateUnitReconcilerWorkflow` (`su-gcp-<project_id>`), and `DriftSchedule` (`drift-<project_id>`).
- [ ] `k8s_job_name(operation_id, phase)` in Python produces byte-for-byte identical output to `idp.k8s_job_name(operation_id, phase)` in AlloyDB (e.g., `k8s_job_name("op:af42f828-3378-5ee2-8e9b-2378d2314f97:r1:plan:1", "plan") == "tf-plan-eba5f9ebf4fafecad8e9"`).
- [ ] Activity retry tests confirm `AlreadyExists` reattachment in `spp-platform`.

## Success Criteria

- **SC-1:**
  - **Given** `operation_id = "op:af42f828-3378-5ee2-8e9b-2378d2314f97:r1:plan:1"` and `phase = "plan"`
  - **When** `ssp-workers` launches the Kubernetes Job in namespace `spp-platform` and records the row in `idp.tf_operation`
  - **Then** `k8s_job_name` is `"tf-plan-eba5f9ebf4fafecad8e9"`, `tf_operation_job_name_derived` passes, and logs are written to `gs://microdrive-dev-spp-tfstate/projects/<project_id>/logs/tf-plan-eba5f9ebf4fafecad8e9.log`.
- **SC-2:**
  - **Given** `idp.state_unit.status = 'frozen'` on a project
  - **When** `su-gcp-<project_id>` receives `approval_ready`
  - **Then** the reconciler refuses to launch `tf-plan-*` or `tf-apply-*` until `unfreeze` is signaled (`INV-9`).

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the workflow IDs, signals, `operation_id` format, and `idp.k8s_job_name` contract |
| `ssp-cp` | Starts `req-<request_id>`, sends `cancel` and `approval_response` signals, and manages `state_unit.status` (`freeze`/`unfreeze`) |
| `ssp-workers` | Implements `RequestWorkflow`, `ApprovalGateWorkflow`, `StateUnitReconcilerWorkflow`, lifecycle tasks, and K8s Job launcher |
| `ssp-module-<type>` | Executed by `tf-<phase>-<20hex>` Jobs in `spp-platform` |
| `spp-factory-foundation` | Verifies `k8s_job_name` derivation in `gates/` |

## Open Questions

- [x] **OQ-1 (Runner Kubernetes Namespace `spp-platform` vs. `idp-runners` — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Runner Kubernetes Jobs execute in namespace **`spp-platform`** on the SPP GKE cluster (`ADR-CLD-GCP-001`).
- [x] **OQ-2 (State Bucket `gs://microdrive-dev-spp-tfstate` — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* All state units use the single bucket **`gs://microdrive-dev-spp-tfstate`** in `us-east1`.

## Related ADRs

- [ADR-CLD-GCP-001: Runtime Platform (SPP GKE Cluster and Self-Hosted Temporal)](../per-cloud/gcp/ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md)
- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-AUT-002: Day-2 Operations Scope](ADR-AUT-002-day-2-operations-scope.md)
