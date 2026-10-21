# ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)

- **ADR ID:** ADR-GLB-007
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-policy@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security], Allen / Karen [Operations])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Establish a clean-slate Open Policy Agent (`OPA` / `Rego`) governance framework, guardrail trace architecture (`GCS-*`, `SPN-*`, `LBL-*`, `PRQ-*`), reconciliation invariants (`INV-1..INV-9`), and drift severity classification that enforce security defaults (CMEK in `us-east1`, retention floors, Raju baseline, zero secrets), single-region `us-east1` scope, non-bypassable Operations Gate, and the hard guardrail prohibiting any deletion, destroy, or replacement of any resource in **any** environment (`nonprod` or `prod`) without explicit human approval.

## Context

From the design session (`uploads/design-digest.md`), the sanitized four-gate design package (`gates.md`, `other.md`, `raw/idp_state_model.reconstructed.sql`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)), and user overrides:

1. **Three Policy Evaluation Stages Recorded in `idp.policy_evaluation`:**
   - `stage = 'requested'`: Evaluates raw/canonical `requested_spec` against closed JSON Schemas and OPA advisory/denial rules (rejecting secret-bearing fields, forbidden IAM principal types like `user:`, `allUsers`, `allAuthenticatedUsers`, roles outside the kind's allowlist, or user attempts to set guardrail-owned fields).
   - `stage = 'approved'`: Evaluates and applies guardrail mutations (`decision IN ('allow', 'deny', 'allow_with_mutations')`), recording every rule mutation in `policy_evaluation.mutations` (`[{rule_id, op, path, value, reason}]`) and `approval.guardrail_trace` (`[{rule_id, path, from, to, reason}]`) along with `opa_package`, `bundle_revision`, and `input_sha256`.
   - `stage = 'plan'`: Evaluates `terraform show -json <planfile>` (`plan.json`) for an `expected_revision` before `terraform apply` is allowed to run.
2. **User Decisions Overriding Source Open Decisions:**
   - **Region `us-east1` Only (No Multi-Region):** Approved GCP region is **`us-east1` only** (including `prod` and Tier 1). Multi-region buckets (`US`) and multi-region Spanner configs (`nam3`) from the source examples are overridden everywhere by `us-east1` / `regional-us-east1`.
   - **No Deletion/Destroy/Replace Without Explicit Human Approval in ANY Environment:** The source had an open decision leaning toward "Owner plus platform team for prod" and allowed `AUTO_APPROVED` statuses. **User decision overrides this:** no deletion, destroy, or destructive replacement of any resource is permitted without explicit human approval in **any** environment (`nonprod` or `prod`), and `AUTO_APPROVED` / `auto_approved` is strictly forbidden for `action = 'delete'` or any Terraform plan with `destroy > 0` or `replace > 0`. Any revision whose plan contains a destroy without an approved delete request is blocked (`blocked_reason = 'destroy_without_delete_request'`).
   - **Alert-Only Drift (No Auto-Reapply):** The source leaned toward auto-reapplying critical guardrail drift (`PAP`, `UBLA`, `CMEK`, public IAM). **User decision overrides this:** drift is **alert-only** in all cases; never auto-reapply. Remediation always goes through a new approved request.

## Decision

### 1. Three-Stage Policy & Schema Enforcement (`requested`, `approved`, `plan`)

1. **Stage 1 — `requested` Gate (Closed JSON Schema + OPA):**
   - Rejects any field not defined in `<kind>.schema.json#/$defs/requested` (preventing secret-bearing fields and disallowing users from requesting guardrail-owned fields such as `uniform_bucket_level_access`, `public_access_prevention`, `force_destroy`, `deletion_protection`, or `default_kms_key_name`).
   - Rejects IAM members other than `group:` and `serviceAccount:` (never `user:`, `allUsers`, or `allAuthenticatedUsers`).
   - Rejects IAM roles outside the kind's explicit allowlist (e.g., no `roles/storage.admin` or legacy owner roles).
   - Rejects any location/region other than `us-east1`.
2. **Stage 2 — `approved` Gate (Guardrail Injection + `guardrail_trace` + Human Approval Gate):**
   - Evaluates the kind's OPA package (`idp.gcp.gcs_bucket`, `idp.gcp.spanner_instance`, `idp.gcp.spanner_database`) and injects guardrail-owned fields (`GCS-*`, `SPN-*`, `LBL-*`) and `pre_apply`/`post_apply` lifecycle tasks (`PRQ-*`).
   - Writes every mutation to `approval.guardrail_trace` (`[{rule_id, path, from, to, reason}]`) and links `approval.policy_evaluation_id`.
   - Enforces the kind's human approval gate (`ADR-BP-003`) and the non-bypassable Operations Gate.
3. **Stage 3 — `plan` Gate (Pre-Apply Plan Inspection on `expected_revision`):**
   - Evaluates `plan.json` (`terraform show -json <planfile>`) against OPA and records `plan_summary = {add, change, destroy, replace}` on `idp.expected_revision`.
   - If `plan_summary.destroy > 0` or `plan_summary.replace > 0` without an explicit human-approved `delete` / destructive plan approval in **any** environment (`nonprod` or `prod`), the revision transitions to `BLOCKED` with `blocked_reason = 'destroy_without_delete_request'`.

### 2. Master Guardrail Rule Catalog (`GCS-*`, `SPN-*`, `LBL-*`, `PRQ-*`, `NAM-*`)

Detailed per-kind specifications live in `ADR-SVC-001` (`gcs_bucket`), `ADR-SVC-002` (`spanner_instance` / `spanner_database`), `ADR-GLB-006` (naming), and `ADR-GLB-008` (labels). Summary of guardrail rule families:

| Rule ID | Target Kind(s) | Gate | Path / Target | Enforced Value / Behavior |
| :--- | :--- | :--- | :--- | :--- |
| **`GCS-UBLA-001`** | `gcs_bucket` | `approved` | `/spec/uniform_bucket_level_access` | Constant `true` (not requestable; legacy form defaulted to `false`). |
| **`GCS-PAP-001`** | `gcs_bucket` | `approved` | `/spec/public_access_prevention` | Constant `"enforced"`. |
| **`GCS-ENC-001` / `002`** | `gcs_bucket` | `approved` | `/spec/kms_key_name` (`default_kms_key_name`) | Looked up by `(LOB, environment_type, location="us-east1")`; must match bucket region `us-east1`. |
| **`GCS-RET-001`** | `gcs_bucket` | `approved` | `/spec/retention_days` (`retention_policy.retention_period`) | `>= 90` days (`7776000` seconds) lookup by data sensitivity (when object versioning is `false`; mutually exclusive with versioning in GCS). |
| **`GCS-RET-003`** | `gcs_bucket` | `approved` | `/spec/retention_locked` (`retention_policy.is_locked`) | Constant `false` ("Locks are irreversible and only applied on an explicit records-management request."). |
| **`GCS-SDP-001`** | `gcs_bucket` | `approved` | `/spec/soft_delete_retention_days` (`soft_delete_policy.retention_duration_seconds`) | Constant `7` days (`604800` seconds). |
| **`GCS-DEL-001`** | `gcs_bucket` | `approved` | `/spec/force_destroy` | Constant `false`. |
| **`SPN-CFG-001`** | `spanner_instance` | `approved` | `/spec/config` | `"regional-us-east1"` in **all** environments (`nonprod` and `prod`) and tiers (`Tier 1..4`) per SPP `us-east1`-only override *(source had `nam3` for Tier 1/prod and `regional-us-east4` for nonprod)*. |
| **`SPN-EDT-001` / `002`** | `spanner_instance` | `approved` | `/spec/edition` | `ENTERPRISE_PLUS` for Tier 1 or `prod`; `STANDARD` for Tier 2–4 `nonprod` (`ENTERPRISE` if autoscaled). |
| **`SPN-BKP-001` / `002`** | `spanner_instance`, `spanner_database` | `approved` | `/spec/default_backup_schedule_type`, `/spec/backup_schedule` | Instance `default_backup_schedule_type = "AUTOMATIC"`; database `backup_schedule`: explicit daily schedule for Tier 1 or `prod`, `null` (instance `AUTOMATIC` default) for Tier 2–4 `nonprod`. |
| **`SPN-DEL-001`** | `spanner_instance` | `approved` | `/spec/force_destroy` | Constant `false`. |
| **`SPN-DEL-002`** | `spanner_database` | `approved` | `/spec/deletion_protection`, `/spec/enable_drop_protection` | Constant `true` for both `deletion_protection` and `enable_drop_protection`. |
| **`SPN-ENC-001`** | `spanner_database` | `approved` | `/spec/kms_key_names` (`encryption_config.kms_key_names`) | `[ "projects/<lob>-kms-<env>/locations/us-east1/keyRings/<lob>-<env>-use1/cryptoKeys/spanner-default" ]` matching `regional-us-east1`. |
| **`SPN-IAM-001`** | `spanner_instance` | `requested` / `approved` | `/spec/access` | Denies granting `roles/spanner.databaseReader` (or database-level data roles) at the Spanner instance level on `shared` tenancy instances (allowed only on `dedicated` instances). |
| **`LBL-001`** | All labelable kinds | `approved` | `/metadata/labels` | Merges the 8 mandatory labels (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`) with user labels (`ADR-GLB-008`). |
| **`LBL-002`** | All labelable kinds | `approved` | `/metadata/labels/*` | Normalizes label values (lowercase, replace `[^a-z0-9_-]` with `_`, max 63 chars, drop empty) and records changes in `guardrail_trace` (`ADR-GLB-008`). |
| **`PRQ-001`** | `gcs_bucket`, `spanner_*` | `approved` | `/prerequisites` (`idp.lifecycle_task`) | Materializes `pre_apply` task `ad_group` via directory service for any requested `group:gcp-<lob>-<env>-<app>-*` IAM member. |
| **`PRQ-002`** | `gcs_bucket` | `approved` | `/prerequisites` (`idp.lifecycle_task`) | Materializes `pre_apply` task `vpc_sc_ingress` into `<lob>_<env>_restricted_perimeter` when `data_sensitivity = "restricted"`. |
| **`PRQ-003`** | `spanner_instance` | `approved` | `/prerequisites` (`idp.lifecycle_task`) | Materializes `pre_apply` task `enable_service` for `spanner.googleapis.com` on the target project. |
| **`PRQ-004`** | `spanner_instance` | `approved` | `/prerequisites` (`idp.lifecycle_task`) | Materializes `pre_apply` task `vpc_sc_project_membership` placing `<project_id>` inside `<lob>_<env>_restricted_perimeter` for restricted data. |

### 3. Platform Reconciliation Invariants (`INV-1..INV-9`)

These nine invariants are the reconciliation gates designed by humans and enforced mechanically across PostgreSQL, OPA, and Temporal:

| ID | Invariant Statement | Mechanical Enforcement Point |
| :--- | :--- | :--- |
| **`INV-1`** | **`Requested` and `Approved` documents contain no secret values** | Closed JSON Schemas (`additionalProperties: false`) + AlloyDB `CHECK` constraints (`submission_no_secret_values`, `request_no_secret_values`) + OPA secret-key scan. |
| **`INV-2`** | **[Unverified (source gap): `[NOT CAPTURED]` in source photos]** | **Unverified (source gap):** Source table rows for `INV-2..INV-4` were cut off in the photo; see `OQ-4` below. |
| **`INV-3`** | **[Unverified (source gap): `[NOT CAPTURED]` in source photos]** | **Unverified (source gap):** See `OQ-4` below. |
| **`INV-4`** | **[Unverified (source gap): partial capture ending with `...'plan'"); otherwise the revision becomes BLOCKED`]** | Enforced at `stage = 'plan'` in `idp.policy_evaluation` (`stage = 'plan' AND decision = 'allow'`), prerequisite `lifecycle_task` completion (`status = 'SUCCEEDED'`), and zero unapproved destroys; otherwise `idp.expected_revision` becomes `BLOCKED` (`blocked_reason` in `{'destroy_without_delete_request', 'approved_hash_mismatch', 'prerequisite_failed'}`). |
| **`INV-5`** | **What was policy-checked is what gets applied** | `apply` runs the exact saved `planfile` of the same `expected_revision`; revision artifacts in GCS are written with `ifGenerationMatch=0` (create-only), with GCS `artifact_generation` and `artifact_sha256` recorded in AlloyDB (`idp.expected_revision`). |
| **`INV-6`** | **Postgres and object storage agree on what was approved** | Before `terraform plan`, the reconciler verifies that each member's `approved_spec_sha256` in `manifest.json` equals `idp.approval.approved_spec_sha256` in AlloyDB; any mismatch blocks the revision (`blocked_reason = 'approved_hash_mismatch'`). |
| **`INV-7`** | **A run is finished only when its Kubernetes Job is** | `idp.tf_operation.status` is set strictly from the Kubernetes Job's terminal condition (`status.succeeded` / `status.failed`) and Terraform's exit code (`tf_exit_code` `0`, `1`, `2`), never from a submission/dispatch response. |
| **`INV-8`** | **One writer per state file** | Serialized by the per-project `StateUnitReconcilerWorkflow` (`su-gcp-<project_id>` via signal-with-start) **plus** the GCS backend's native lock (`projects/<project_id>/default.tflock`). |
| **`INV-9`** | **A kill switch exists at two levels** | 1) Setting `idp.state_unit.status = 'frozen'` in AlloyDB immediately blocks `plan` and `apply` for that project; 2) revoking service-account impersonation on the central platform runner SA (`<runner-sa>@microdrive-dev.iam.gserviceaccount.com`) stops every executor across all projects. |

### 4. Drift Severity Classification (Alert-Only)

When `Expected` vs. `Observed` comparison detects an attribute difference (after excluding `resource_kind.drift_ignore_paths`), `idp.drift_finding` classifies severity by attribute family:

| Severity | Attribute Family | Concrete Example | Platform Response (Override) |
| :--- | :--- | :--- | :--- |
| **`critical`** | Security guardrails: `public_access_prevention`, `uniform_bucket_level_access`, `default_kms_key_name` / `encryption_config.kms_key_names`, public IAM principal (`allUsers` / `allAuthenticatedUsers`) | `public_access_prevention` switched from `"enforced"` to `"inherited"` in GCP Console (`guardrail_rule_id = "GCS-PAP-001"`) | **Alert-only** (`drift_finding.status = 'OPEN'`, `severity = 'critical'`, sets `resource.sync_status = 'DRIFTED'`). Never auto-reapplies. |
| **`high`** | Data-protection / retention policies: `retention_policy`, `soft_delete_policy`, `version_retention_period`, `backup_schedule` | Bucket `retention_policy.retention_period` shortened in Console | **Alert-only** (`severity = 'high'`). Remediation requires a new approved request. |
| **`medium`** | Capacity, lifecycle, and non-public IAM: `storage_class`, `lifecycle_rules`, `processing_units` (when not autoscaled), `edition`, `iam_bindings` (extra group/SA granted out of band) | Spanner instance scaled from `100` to `300` processing units in Console (`attribute_path = "/processing_units"`, `expected_value = 100`, `observed_value = 300`) | **Alert-only** (`severity = 'medium'`). Remediation requires a new approved request. |
| **`low`** | Metadata & labels: `labels`, `display_name` | `owner` label modified or removed out of band | **Alert-only** (`severity = 'low'`). Remediation requires a new approved request. |

*(Note: Any drift that undoes an enforced guardrail populates `drift_finding.guardrail_rule_id`, which defaults to `critical` severity.)*

## Requirements

- **REQ-1 (MUST):** All OPA/Rego policies MUST be authored from scratch (`import rego.v1`), evaluated at `requested`, `approved`, and `plan` stages, and recorded in `idp.policy_evaluation` with `opa_package`, `bundle_revision`, `input_sha256`, `decision`, `violations`, and `mutations`.
- **REQ-2 (MUST):** Every guardrail mutation applied at the `Approved` gate (`GCS-*`, `SPN-*`, `LBL-*`, `PRQ-*`) MUST be recorded in `idp.approval.guardrail_trace` with `rule_id`, `path`, `from`, `to`, and `reason`.
- **REQ-3 (MUST):** Only region **`us-east1`** (`location = "us-east1"`, Spanner `config = "regional-us-east1"`) MAY be allowed by schema and Rego in `nonprod` and `prod`; multi-region configurations (`US`, `nam3`) MUST be rejected.
- **REQ-4 (MUST):** No deletion, destroy, or replacement of any resource may execute without explicit human approval in **any** environment (`nonprod` or `prod`). `idp.approval.status = 'AUTO_APPROVED'` and `idp.approval_decision.status = 'auto_approved'` MUST be rejected for `action = 'delete'` or plans with `destroy > 0` or `replace > 0`, and any revision with an unapproved destroy MUST be blocked with `blocked_reason = 'destroy_without_delete_request'`.
- **REQ-5 (MUST):** All nine platform invariants (`INV-1..INV-9`) MUST be enforced by `ssp-cp` and `ssp-workers`.
- **REQ-6 (MUST):** Drift findings in `idp.drift_finding` MUST assign severity (`critical`, `high`, `medium`, `low`) per Section 4 and MUST remain **alert-only** (never triggering an automated `terraform apply` overwrite).

## Guardrails

- **GR-1:** Never import or reuse legacy "taxi" OPA policies.
- **GR-2:** Never allow user requests to supply or override guardrail-owned fields (`uniform_bucket_level_access`, `public_access_prevention`, `force_destroy`, `deletion_protection`, `default_kms_key_name`).
- **GR-3:** Never allow `user:`, `allUsers`, or `allAuthenticatedUsers` in IAM bindings at any gate.
- **GR-4:** Never auto-approve (`AUTO_APPROVED`) a resource deletion, `destroy_plan`, or Terraform plan containing `delete`/`replace` actions in **any** environment (`nonprod` or `prod`).
- **GR-5:** Never auto-remediate drift; all drift remediation must go through a new human-approved request.

## Consequences

### Positive

- Every policy decision and guardrail injection is auditable via `idp.policy_evaluation` and `idp.approval.guardrail_trace`.
- Authoritative per-role IAM bindings (`iam_bindings`) ensure any out-of-band IAM grant in GCP Console surfaces immediately as a `medium` or `critical` drift finding.
- Blocking `destroy_without_delete_request` at the `plan` gate prevents accidental resource destruction across both `nonprod` and `prod`.

### Negative / Trade-offs

- Because drift is strictly alert-only, resolving even a critical guardrail drift (e.g., `public_access_prevention` changed out of band) requires submitting and approving a remediation request rather than silent background overwrite.

## Acceptance Criteria

- [ ] `ssp-cp` implements `idp.policy_evaluation` persistence across `requested`, `approved`, and `plan` stages and populates `approval.guardrail_trace`.
- [ ] Rego packages (`idp.gcp.gcs_bucket`, `idp.gcp.spanner_instance`, `idp.gcp.spanner_database`) enforce `GCS-*`, `SPN-*`, `LBL-*`, `PRQ-*`, `us-east1`-only location, and human-approved deletion rules.
- [ ] `ssp-workers` enforces `INV-4..INV-9` before and during `tf_operation` execution.

## Success Criteria

- **SC-1:**
  - **Given** a `gcs_bucket` or `spanner_instance` request submitted at the `Requested` gate
  - **When** `RequestWorkflow` evaluates OPA at the `Approved` gate
  - **Then** `idp.approval.guardrail_trace` records each applied rule (`GCS-UBLA-001`, `GCS-PAP-001`, `GCS-ENC-001`, `GCS-RET-001`, `GCS-SDP-001`, `GCS-DEL-001`, `LBL-001`, `PRQ-001/002` or `SPN-*`) with its `path`, `from`, `to`, and `reason`.
- **SC-2:**
  - **Given** an `Expected` revision whose `terraform plan` produces `plan_summary.destroy > 0` or `plan_summary.replace > 0` without an explicit human-approved `delete` request in `nonprod` or `prod`
  - **When** evaluated at `stage = 'plan'`
  - **Then** `idp.policy_evaluation.decision` is `'deny'`, `idp.expected_revision.status` is set to `'BLOCKED'` with `blocked_reason = 'destroy_without_delete_request'`, and `terraform apply` is never executed.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-GLB-007`, guardrail catalog, invariants `INV-1..INV-9`, and drift severity table |
| `ssp-cp` | Evaluates `requested` and `approved` policies, populates `guardrail_trace`, and blocks `AUTO_APPROVED` deletes |
| `ssp-workers` | Evaluates `plan` stage policies, enforces `INV-4..INV-9`, and classifies drift findings (`critical`/`high`/`medium`/`low`) |
| `ssp-module-gcs-bucket`, `ssp-module-spanner` | Implements Rego packages (`idp.gcp.gcs_bucket`, `idp.gcp.spanner_instance`, `idp.gcp.spanner_database`) and unit tests |
| `spp-factory-foundation` | Runs schema, Rego, and invariant checks in `gates/` |

## Open Questions

- [x] **OQ-1 (Approved GCP Region — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Region is **`us-east1` only** (no multi-region `US` buckets, no `nam3` Spanner, no `us-east4`), including `prod`.
- [x] **OQ-2 (Destructive Plan Approval in Nonprod vs. Prod — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Explicit human approval is required for **any** deletion, destroy, or replace in **any** environment (`nonprod` and `prod`); no `AUTO_APPROVED` for deletes.
- [x] **OQ-3 (Drift Response Auto-Reapply vs. Alert-Only — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Drift is **alert-only**; never auto-reapply. Remediation goes through a new approved request.
- [ ] **OQ-4 (Unverified Source Gap for `INV-2..INV-4` Text — SOURCE GAP [Owner: Manoj]):** **Unverified (source gap):** In `gates.md` §9 (`README_2.md` §9), the table rows for `INV-2`, `INV-3`, and the beginning of `INV-4` (up to `...'plan'"); otherwise the revision becomes BLOCKED`) were `[NOT CAPTURED]` in the source photographs. From the surrounding DDL (`idp.policy_evaluation`, `idp.approval`, `idp.lifecycle_task`, `idp.expected_revision`), `INV-2..INV-4` govern `Requested -> Approved -> Expected` gate transitions (approval decision completeness, pre-apply prerequisite completion, and `stage = 'plan'` OPA allow). Exact wording of `INV-2` and `INV-3` remains unverified from the photo set.

## Related ADRs

- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-008: Label and Tag Standard](ADR-GLB-008-label-and-tag-standard.md)
- [ADR-GLB-009: Resource Kind Registry](ADR-GLB-009-resource-kind-registry.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-SVC-001: GCS Bucket End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](../endpoint-service/ADR-SVC-002-spanner-instance-and-database.md)
- [ADR-AUT-001: Terraform Execution via Deterministic Kubernetes Jobs](../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-AUT-002: Day-2 Operations Scope](../automation/ADR-AUT-002-day-2-operations-scope.md)
