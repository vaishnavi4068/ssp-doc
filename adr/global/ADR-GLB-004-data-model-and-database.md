# ADR-GLB-004: Data Model and Centralized PostgreSQL Database

- **ADR ID:** ADR-GLB-004
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Karen [DBA/Operations])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `spp-ui`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the core relational data model, JSON Schema contracts, and database hosting rules for the centralized PostgreSQL database in GCP that backs SPP's control plane (`ssp-cp`) and stores `Requested` and `Approved` states, operation history, authentication records, and immutable audit logs.

## Context

From the design digest (`uploads/design-digest.md`) and factory runtime (`spp-factory-foundation`):

1. **PostgreSQL in GCP for Control Plane Metadata:** The team decided that `Requested` and `Approved` states belong in a centralized PostgreSQL database in GCP because they are small, structured metadata documents that require ACID transactions, rich indexing (by `apm_id`, `project_id`, `lob`, `state`, `requester`), and auditability.
2. **Zero Secrets and Zero Terraform State Blobs in PostgreSQL:** To prevent TOAST/vacuum churn and eliminate the risk of a centralized database becoming a honey pot of cloud credentials, PostgreSQL stores **only** `Requested` and `Approved` metadata, lifecycle tracking, and audit logs—never `Expected` or `Observed` Terraform state files and never secrets.
3. **Database Hosting Constraint ("Don't Use Cloud SQL"):** During the design session, "don't use Cloud SQL" was mentioned while Saul noted "we can do whatever we want with databases" and Karen holds DBA/operations requirements. In the `microdrive-dev` GKE environment (`md-dev`), self-hosted PostgreSQL runs in-cluster for Temporal (`spp-temporal`) and platform/factory services, while the long-term production PostgreSQL hosting mechanism (e.g., in-cluster enterprise Postgres operator, AlloyDB, or approved configuration) requires Karen and Manoj's sign-off.
4. **DB Migrations Owned by `ssp-cp`:** Per `docs/repo-map.md`, `ssp-cp` owns the control plane database schema, Alembic migrations, and per-component DB migration ADRs.

## Decision

1. **Core Relational Tables in `ssp-cp` PostgreSQL (`spp_platform` database):**
   - `provisioning_requests` (`id` / `request_id`, `idempotency_key`, `cloud`, `layout_version`, `lob`, `project_id`, `resource_type`, `resource_name`, `region`, `apm_id`, `environment`, `requester_username`, `requester_persona`, `current_state` [`requested | approved | expected | observed | failed | decommissioned`], `requested_payload` JSONB, `created_at`, `updated_at`).
   - `approved_specs` (`id`, `request_id` FK, `version`, `operation_id`, `service_account_email`, `application_tier`, `state_backend` JSONB, `security_enrichment` JSONB, `servicenow_metadata` JSONB, `cmdb_metadata` JSONB, `operations_gate` JSONB, `approved_payload` JSONB, `policy_evaluation_report` JSONB, `approved_at`).
   - `provisioning_operations` (`operation_id` PK, `request_id` FK, `operation_type` [`create | update | resize | upgrade | drift_check | rollback | decommission`], `temporal_workflow_id`, `temporal_run_id`, `k8s_job_name` [`tf-op-<operation_id>`], `status` [`pending | running | succeeded | failed | cancelled`], `expected_state_uri`, `observed_state_uri`, `cloud_resource_id`, `error_summary`, `started_at`, `completed_at`).
   - `managed_resources` (`resource_id` PK, `cloud_resource_id` UNIQUE, `project_id`, `lob`, `cloud`, `resource_type`, `resource_name`, `apm_id`, `environment`, `current_state`, `latest_approved_spec_id` FK, `drift_status` [`in_sync | drifted | unknown`], `estimated_monthly_cost_usd`, `last_observed_at`, `created_at`, `updated_at`).
   - `audit_logs` (`id` PK, `actor_username`, `actor_role`, `source_ip`, `action_type`, `request_id`, `operation_id`, `reason`, `details` JSONB, `created_at` — append-only / immutable).
   - `users` and `user_sessions` (local authentication accounts with Argon2id `password_hash`, `role`, `must_change_password`, `failed_login_attempts`, `locked_until`, `is_active`, and session/CSRF tokens for Phase 1 local login before SSO).
2. **Canonical JSON Schema Alignment:**
   - The `requested_payload` and `approved_payload` JSONB columns MUST conform to `gates/schemas/resource-request.schema.json` (`schema_version = "2.0"`, `layout_version = "2.0"`).
3. **Database Separation in GKE `md-dev`:**
   - Temporal server (`spp-temporal`), Factory Console (`spp-factory`), and SPP Control Plane (`spp-platform`) use logically isolated PostgreSQL databases/schemas so factory metadata and runtime provisioning records never mix.

## Requirements

- **REQ-1 (MUST):** `ssp-cp` MUST manage all PostgreSQL schema changes through versioned, repeatable database migrations (Alembic) stored in `ssp-cp`.
- **REQ-2 (MUST):** Every write to `provisioning_requests.requested_payload` and `approved_specs.approved_payload` MUST be validated against the canonical SPP JSON Schema and scanned to guarantee zero secret keys or values prior to `COMMIT`.
- **REQ-3 (MUST):** `provisioning_requests` MUST enforce client-supplied `idempotency_key` uniqueness so retried API calls return the existing `request_id` rather than creating duplicate requests.
- **REQ-4 (MUST):** `approved_specs` and `audit_logs` rows MUST be immutable (append-only); Day-2 updates (`update`, `resize`, `upgrade`, `rollback`, `decommission`) MUST insert a new `approved_specs` version row and a new `provisioning_operations` row with a new deterministic `operation_id`.
- **REQ-5 (MUST):** `managed_resources` MUST index the immutable Cloud Service Provider identifier (`cloud_resource_id`) once provisioning reaches `Observed` state so drift detection and import key off `cloud_resource_id` rather than `resource_name`.
- **REQ-6 (SHOULD):** Every state transition (`Requested -> Approved -> Expected -> Observed` or `failed`) SHOULD emit an append-only row in `audit_logs` within the same database transaction.

## Guardrails

- **GR-1:** Never store raw Terraform `.tfstate` contents (`Expected` or `Observed`) in any PostgreSQL table or JSONB column; store only the GCS URI (`gs://microdrive-dev-spp-tfstate/expected/<project-id>/terraform.tfstate`).
- **GR-2:** Never store plaintext passwords, private keys, API keys, or cloud credentials in PostgreSQL; `users.password_hash` must use Argon2id (`ADR-GLB-005`).
- **GR-3:** Never execute destructive `DROP TABLE` or unreviewed schema migrations in production without an accepted DB migration ADR in `ssp-cp` and Operations sign-off.

## Consequences

### Positive

- Full relational queryability across all requests, approved guardrails, active operations, and managed resources by `apm_id`, `project_id`, `lob`, and `environment`.
- Versioned `approved_specs` and `provisioning_operations` provide a built-in history for Day-2 `rollback` and audit compliance.
- Strict separation between small control-plane JSONB payloads in PostgreSQL and potentially large Terraform states in GCS.

### Negative / Trade-offs

- State transitions across PostgreSQL (`ssp-cp`) and GCS/Temporal (`ssp-workers`) require idempotent activity updates so PostgreSQL metadata (`current_state = 'observed'`, `cloud_resource_id`) stays synchronized with GCS state files after a K8s Job completes.

## Acceptance Criteria

- [ ] `ssp-cp` includes a dedicated DB migrations ADR and initial Alembic migration creating the core tables (`provisioning_requests`, `approved_specs`, `provisioning_operations`, `managed_resources`, `audit_logs`, `users`, `user_sessions`).
- [ ] `requested_payload` and `approved_payload` validate cleanly against `gates/schemas/resource-request.schema.json`.
- [ ] Automated tests in `ssp-cp` verify idempotency key deduplication, secret rejection, and append-only immutability of `approved_specs` and `audit_logs`.

## Success Criteria

- **SC-1:**
  - **Given** two identical `POST /api/v1/requests` calls carrying the same `Idempotency-Key` header
  - **When** `ssp-cp` processes both requests against PostgreSQL
  - **Then** only one row is created in `provisioning_requests` and both calls return the same `request_id`.
- **SC-2:**
  - **Given** a completed GCS bucket creation Job (`tf-op-<operation_id>`)
  - **When** the `ssp-workers` completion activity updates `ssp-cp`
  - **Then** `provisioning_operations.status` is set to `succeeded`, `managed_resources.cloud_resource_id` records the GCS bucket self-link/ID, `current_state` transitions to `observed`, and `expected_state_uri` / `observed_state_uri` point to `gs://microdrive-dev-spp-tfstate/...` without storing the state blob in PostgreSQL.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the global data model and PostgreSQL boundaries |
| `ssp-cp` | Owns SQLAlchemy models, Alembic migrations, and DB migration ADRs |
| `ssp-workers` | Reads `approved_specs` and updates `provisioning_operations` and `managed_resources` |
| `ssp-ui` | Consumes request, resource inventory, and audit endpoints backed by these tables |
| `spp-factory-foundation` | Validates `requested` and `approved` JSONB schemas via `gates/schemas/resource-request.schema.json` |

## Open Questions

- [ ] **OQ-1 (PostgreSQL Hosting Offering in GCP):** In the design session, "don't use Cloud SQL" was raised while Saul noted "we can do whatever we want with databases." In `md-dev` (`microdrive-dev`), PostgreSQL runs in-cluster on GKE (`spp-pool`). Confirm with Manoj, Saul, and Karen whether production SPP will use an in-cluster enterprise PostgreSQL operator (e.g., CloudNativePG), AlloyDB, or an approved managed PostgreSQL service.
- [ ] **OQ-2 (Shared vs. Separate PostgreSQL Instance on `md-dev`):** In GKE cluster `md-dev`, should `ssp-cp` in `spp-platform` use a separate logical database (`spp_platform`) on the existing PostgreSQL instance in `spp-temporal` / `spp-factory`, or deploy its own dedicated PostgreSQL StatefulSet inside `spp-platform`?
- [ ] **OQ-3 (Retention & Archival of Audit Logs):** What is the required retention period in PostgreSQL vs. archival to GCS/BigQuery for `audit_logs` and historical `provisioning_operations` (e.g., 90 days hot in Postgres, 7 years in cold storage)?

## Related ADRs

- [ADR-GLB-002: Languages and Technology Stack](ADR-GLB-002-languages-and-technology-stack.md)
- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](ADR-GLB-003-four-state-model.md)
- [ADR-GLB-005: Identity and Authentication](ADR-GLB-005-identity-and-authentication.md)
- [ADR-CLD-GCP-001: Runtime Platform (GKE `md-dev` and Self-Hosted Temporal)](../per-cloud/gcp/ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md)
