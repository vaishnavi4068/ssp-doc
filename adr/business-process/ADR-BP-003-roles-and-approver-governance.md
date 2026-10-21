# ADR-BP-003: Roles, Personas, and Approval Gate Governance

- **ADR ID:** ADR-BP-003
- **Level:** business-process
- **Status:** Proposed
- **Owner:** Norm (Shared Mailbox: `spp-governance@tbd`, Named Owner: `Norm`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Allen / Karen [Operations], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `spp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the roles, personas, owning teams, IAM principal restrictions, and human approval gate engine (`idp.approval_gate_config`, `idp.approval`, `idp.approval_decision`, `ApprovalGateWorkflow` `apr-<request_id>`)—including sequential approver chains, self-approval denial, SLA follow-ups, manager escalation, auto-close, 30-day approval validity, and the mandatory human-approval requirement for any resource deletion or destructive plan in **any** environment (`nonprod` or `prod`).

## Context

From the sanitized four-gate design package (`roles.md`, `workflows.md`, `environments.md`, `raw/idp_state_model.reconstructed.sql`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)) and user overrides:

1. **Versioned Approval Gate Configuration (`idp.approval_gate_config`):**
   - In the legacy system, modifying an approval gate configuration in place could orphan in-flight Temporal approval workflows. In SPP, `idp.approval` pins both `gate_key` and `gate_version` (`idp.approval_gate_config`), and `ApprovalGateWorkflow` (`apr-<request_id>`) receives signals keyed by `decision_id` (`approval_response {decision_id, status, responded_by, comment}`).
2. **Self-Approval Denial & Sequential Approver Chains with SLA Escalation:**
   - Every approval gate sets `"self_approval": "deny"`: the requester (`requested_by` / `submitted_by` / `on_behalf_of`) may never approve their own request.
   - Approvers run in `"order": "sequential"`, with configurable `sla_days`, `max_follow_ups`, `follow_up_interval_days`, manager escalation (`"type": "manager"`, `manager_sla_days: 2`, `max_follow_ups: 1`), `max_wait_days: 13`, and `auto_close` (`enabled: true`, `warning_lead_days: 2`, `final_reminder_after_days: 1`). Decided approvals carry a 30-day validity window (`valid_until = decided_at + 30 days`).
3. **User Overrides on Environments and Deletions:**
   - **Two Environments Everywhere (`nonprod` and `prod`):** In `spanner_data_owner`, the source `skip_condition` for `dbaas_reviewer` originally listed three pre-production codes (`pdev`, `pqa`, `preprod`) alongside `prod`. **User decision overrides this:** `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, and `preprod` all map to **`nonprod`** everywhere, including the Spanner `dbaas_reviewer` skip rule (`"metadata.environment not in ('prod') and metadata.resolved.app_tier != '1'"`).
   - **No Deletion/Destroy/Replace Without Explicit Human Approval in ANY Environment:** No resource deletion (`action = 'delete'`) or destructive plan (`destroy > 0` or `replace > 0`) may ever use `AUTO_APPROVED` / `auto_approved` in `nonprod` or `prod`.

## Decision

### 1. Platform Personas, Approver Roles, Owning Teams, and System Actors

| Role / Persona / Actor | Identifier / Field | Responsibilities & Constraints |
| :--- | :--- | :--- |
| **Requester** | `requested_by`, `submitted_by`, `on_behalf_of` | Submits requests via `ui`, `api`, `chat`, `import` (or deferred `legacy_shim`). **May never approve their own request (`self_approval: "deny"`).** |
| **Bucket / Resource Owner** | `metadata.owner` (`approver_key = "bucket_owner"`) | Mandatory approver (`phase = 0`) for `gcs_bucket` (`gate_key = "gcs_bucket_owner"`). |
| **Data Owner** | `metadata.owner` (`approver_key = "data_owner"`) | Mandatory first approver (`phase = 0`) for `spanner_instance` and `spanner_database` (`gate_key = "spanner_data_owner"`). |
| **DBaaS Reviewer** | Role `dbaas_reviewer` (`approver_key = "dbaas_reviewer"`) | Mandatory second approver (`run_after_approver_keys = ["data_owner"]`) for Spanner when `metadata.environment == 'prod'` **or** `metadata.resolved.app_tier == '1'`. Skipped for Tier 2–4 `nonprod` (including former `pdev`/`pqa`/`preprod`). |
| **Manager** | Resolved from directory hierarchy (`escalated_to`) | Escalation target when `bucket_owner` or `data_owner` misses SLA (`manager_sla_days = 2`, `max_follow_ups = 1`). |
| **Platform Team / Operations** | `platform-team` (`updated_by` of `approval_gate_config`; `operations` persona) | Owns `idp.approval_gate_config`, `state_unit.status` (`freeze`/`unfreeze` kill switch), and co-approves destructive operations. |
| **Shared Mailbox** | `metadata.shared_mailbox` (`sharedemailaddress` label) | Team contact and notification recipient (`notify_owner` post-apply task). |
| **Enterprise Domain Owning Teams** | — | **Network Security:** owns VPC-SC perimeters (`<lob>_<env>_restricted_perimeter`). **Security Key Vault Team:** owns CMEK keys. **Identity Team:** owns directory (`ad_group`) groups (`gcp-<lob>-<env>-<app>-(read\|write\|admin\|dba)`). **Project Owners:** own app service accounts (`orders-api@...`). **Project Vending:** owns GCP projects (`{lob}-{env}-{purpose}`). **DBaaS Team:** owns shared Spanner instances. |
| **System Actors** | `system:<temporal_workflow_id>`, `idp-tf@<project>.iam.gserviceaccount.com`, `<runner-sa>@microdrive-dev.iam.gserviceaccount.com` | Recorded in `idp.gate_event.actor`; per-project executor SA reached via impersonation from central platform runner SA. |

### 2. Allowed IAM Principals in Resource Requests

- Resource `spec.access` / `iam_bindings` MAY only specify **`group:`** and **`serviceAccount:`** members.
- Individual **`user:`**, **`allUsers`**, and **`allAuthenticatedUsers`** principals are strictly rejected at the `Requested`, `Approved`, and `plan` gates.
- Standard directory group naming convention (`ad_group`): `gcp-<lob>-<env>-<app>-(read|write|admin|dba)@example.com` (with `<env>` in `{"nonprod", "prod"}`).

### 3. Canonical Approval Gate Configurations (`idp.approval_gate_config` Seed Rows)

#### Gate 1: `gcs_bucket_owner` (Version 1)
```json
{
  "order": "sequential",
  "self_approval": "deny",
  "approvers": [
    {
      "key": "bucket_owner",
      "ticket_field": "/metadata/owner",
      "mandatory": true,
      "sla_days": 5,
      "max_follow_ups": 4,
      "follow_up_interval_days": 1,
      "escalation": {
        "type": "manager",
        "manager_sla_days": 2,
        "max_follow_ups": 1
      }
    }
  ],
  "max_wait_days": 13,
  "auto_close": {
    "enabled": true,
    "warning_lead_days": 2,
    "final_reminder_after_days": 1
  },
  "email_attribute_list": ["/spec/name", "/metadata/project_id", "/metadata/owner"]
}
```

#### Gate 2: `spanner_data_owner` (Version 1)
```json
{
  "order": "sequential",
  "self_approval": "deny",
  "approvers": [
    {
      "key": "data_owner",
      "ticket_field": "/metadata/owner",
      "mandatory": true,
      "sla_days": 5,
      "max_follow_ups": 4,
      "follow_up_interval_days": 1,
      "escalation": {
        "type": "manager",
        "manager_sla_days": 2,
        "max_follow_ups": 1
      }
    },
    {
      "key": "dbaas_reviewer",
      "role": "dbaas_reviewer",
      "mandatory": true,
      "run_after_approver_keys": ["data_owner"],
      "skip_condition": "metadata.environment not in ('prod') and metadata.resolved.app_tier != '1'",
      "sla_days": 3,
      "max_follow_ups": 2,
      "follow_up_interval_days": 1
    }
  ],
  "max_wait_days": 13,
  "auto_close": {
    "enabled": true,
    "warning_lead_days": 2,
    "final_reminder_after_days": 1
  }
}
```

### 4. Approval Lifecycle, Signal Contract, Expiry, and Deletion Rule

1. **Signal Contract (`apr-<request_id>`):** `approval_response {decision_id, status, responded_by, comment}` updates the corresponding row in `idp.approval_decision` (`status` in `pending | approved | denied | escalated | auto_approved | expired`).
2. **Per-Resource Approval Granularity:** Approvals are tracked per `idp.resource` / `idp.request` (`1:1` `request_id` → `approval_id`), while outbound user notifications may be grouped by `submission_id`.
3. **Approval Expiry (`valid_until`):** Once decided as `APPROVED`, `idp.approval.valid_until` is set to `decided_at + interval '30 days'`. Pending approvals that exceed `max_wait_days` (`13` days) after follow-ups and manager escalation transition to `EXPIRED` (`auto_close`).
4. **Universal Human-Approval Rule for Deletions & Destructive Plans:**
   - For any request with `action = 'delete'` or any revision where `plan_summary.destroy > 0` or `plan_summary.replace > 0` in **`nonprod` or `prod`**, explicit human approval (`status = 'approved'` with a verified human `responded_by` who is not the requester) is mandatory; `AUTO_APPROVED` / `auto_approved` is prohibited.

## Requirements

- **REQ-1 (MUST):** Every `idp.approval` row MUST pin `gate_key` and `gate_version` from `idp.approval_gate_config` at creation time so subsequent edits to `idp.approval_gate_config` never break in-flight `ApprovalGateWorkflow` executions.
- **REQ-2 (MUST):** `ApprovalGateWorkflow` (`apr-<request_id>`) and `ssp-cp` MUST enforce `self_approval = "deny"`, rejecting any `approval_response` where `responded_by` matches `request.requested_by`, `submission.submitted_by`, or `submission.on_behalf_of`.
- **REQ-3 (MUST):** `ApprovalGateWorkflow` MUST enforce sequential approver ordering (`run_after_approver_keys`), SLA deadlines (`sla_days`), follow-up reminders (`follow_up_interval_days`, `max_follow_ups`), manager escalation (`manager_sla_days = 2`), `max_wait_days = 13` auto-close (`EXPIRED`), and `valid_until = decided_at + 30 days`.
- **REQ-4 (MUST):** For `spanner_data_owner`, `dbaas_reviewer` MUST be skipped when `metadata.environment == 'nonprod'` (which includes mapped `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`) **and** `metadata.resolved.app_tier != '1'`, and MUST be required when `metadata.environment == 'prod'` **or** `metadata.resolved.app_tier == '1'`.
- **REQ-5 (MUST):** No deletion (`action = 'delete'`), destroy, or replacement of any resource in **any** environment (`nonprod` or `prod`) MAY be auto-approved (`AUTO_APPROVED` / `auto_approved`); explicit human approval is required everywhere.

## Guardrails

- **GR-1:** Never allow a requester to approve their own request (`self_approval = "deny"`).
- **GR-2:** Never allow `AUTO_APPROVED` on `idp.approval` or `auto_approved` on `idp.approval_decision` for `action = 'delete'` or plans with `destroy > 0` or `replace > 0` in any environment.
- **GR-3:** Never allow `user:`, `allUsers`, or `allAuthenticatedUsers` principals in resource IAM bindings.

## Consequences

### Positive

- Pinning `gate_key + gate_version` and keying signals by `decision_id` eliminates legacy signal-routing bugs when approval rules evolve.
- Mapping `pdev`, `pqa`, and `preprod` to `nonprod` makes the `dbaas_reviewer` skip condition deterministic (`metadata.environment not in ('prod') and metadata.resolved.app_tier != '1'`).

### Negative / Trade-offs

- Because `self_approval` is denied even when `requested_by == metadata.owner`, a resource owner submitting a request for their own bucket or Spanner instance must have a peer/delegate or manager approve the request.

## Acceptance Criteria

- [ ] `idp.approval_gate_config`, `idp.approval`, and `idp.approval_decision` tables and seed rows (`gcs_bucket_owner`, `spanner_data_owner`) are defined in `specs/data-model/spp_state_model.sql`.
- [ ] `ApprovalGateWorkflow` (`apr-<request_id>`) in `ssp-workers` implements sequential phases, `skip_condition`, SLA timers, manager escalation, and `self_approval = "deny"`.
- [ ] `ssp-cp` rejects self-approval and rejects `AUTO_APPROVED` on any `delete` request in both `nonprod` and `prod`.

## Success Criteria

- **SC-1:**
  - **Given** a `spanner_instance` request in `environment = "nonprod"` (including requests mapped from `pdev`/`pqa`/`preprod`) with `app_tier = "2"`
  - **When** `data_owner` approves `decision_id` via `approval_response`
  - **Then** `dbaas_reviewer` is skipped per `skip_condition`, `idp.approval.status` transitions to `'APPROVED'`, and `valid_until` is set to 30 days after `decided_at`.
- **SC-2:**
  - **Given** a requester (`requester@example.com`) who is also listed as `/metadata/owner` attempting to send `approval_response` with `responded_by = "requester@example.com"`, or a `delete` request attempting `AUTO_APPROVED` in `nonprod`
  - **When** processed by `ssp-cp` / `ApprovalGateWorkflow`
  - **Then** the approval is rejected due to `self_approval = "deny"` or the human-approval deletion rule.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-BP-003` and the `idp.approval_gate_config` seed rows in `specs/data-model/spp_state_model.sql` |
| `ssp-cp` | Exposes approval decision endpoints, enforces `self_approval = "deny"`, and blocks `AUTO_APPROVED` deletes |
| `ssp-workers` | Implements `ApprovalGateWorkflow` (`apr-<request_id>`), SLA timers, follow-ups, and manager escalation |
| `ssp-ui` | Renders pending approval queues, SLA countdowns, and approval/denial actions |
| `spp-factory-foundation` | Validates approval gate seed configs and `spanner.gates.json` trace |

## Open Questions

- [x] **OQ-1 (Pre-Prod Environment Mapping for `dbaas_reviewer` Skip Condition — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod` all map to `nonprod` everywhere, including the Spanner `dbaas_reviewer` skip rule (`metadata.environment not in ('prod') and metadata.resolved.app_tier != '1'`).
- [x] **OQ-2 (Destructive Plan / Delete Approval in Nonprod and Prod — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Explicit human approval is required for **any** deletion, destroy, or replace in **any** environment (`nonprod` and `prod`); no `AUTO_APPROVED` for deletes.

## Related ADRs

- [ADR-BP-001: Ownership Map and Stakeholder Governance](ADR-BP-001-ownership-map-and-governance.md)
- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-009: Resource Kind Registry](../global/ADR-GLB-009-resource-kind-registry.md)
- [ADR-AUT-001: Temporal Orchestration and Terraform Execution via Deterministic Kubernetes Jobs](../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-AUT-002: Day-2 Operations, Drift Detection, and Deletion Governance](../automation/ADR-AUT-002-day-2-operations-scope.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](../endpoint-service/ADR-SVC-002-spanner-instance-and-database.md)
