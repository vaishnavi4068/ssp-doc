# ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)

- **ADR ID:** ADR-GLB-004
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Karen [DBA/Operations])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the core relational data model, JSON Schema contracts, and **AlloyDB for PostgreSQL** hosting architecture in GCP (`microdrive-dev`) that backs SPP's control plane (`ssp-cp`) and stores `Requested` and `Approved` states, operation history, authentication records, and immutable audit logs.

## Context

From the design digest (`uploads/design-digest.md`), stakeholder resolution of `OQ-1` / `OQ-2`, and factory runtime (`spp-factory-foundation`):

1. **PostgreSQL in GCP for Control Plane Metadata:** The team decided that `Requested` and `Approved` states belong in a centralized PostgreSQL database in GCP because they are small, structured metadata documents that require ACID transactions, rich indexing (by `apm_id`, `project_id`, `lob`, `state`, `requester`), and auditability.
2. **Zero Secrets and Zero Terraform State Blobs in PostgreSQL:** To prevent TOAST/vacuum churn and eliminate the risk of a centralized database becoming a honey pot of cloud credentials, PostgreSQL stores **only** `Requested` and `Approved` metadata, lifecycle tracking, and audit logs—never `Expected` or `Observed` Terraform state files and never secrets.
3. **Dedicated AlloyDB for PostgreSQL in `microdrive-dev` (Resolving "Don't Use Cloud SQL"):** During the design session, "don't use Cloud SQL" was raised while Saul noted "we can do whatever we want with databases." Architecture resolved (`OQ-1` and `OQ-2`) that the SPP product database (`spp_platform`) runs on a **dedicated Google Cloud AlloyDB for PostgreSQL cluster/instance in project `microdrive-dev`**—explicitly **not** Cloud SQL, **not** the in-cluster PostgreSQL instances on `md-dev`, and **not** a GKE StatefulSet. Meanwhile, the software factory's own lightweight PostgreSQL in `spp-factory` and Temporal's backing PostgreSQL in `spp-temporal` remain as-is.
4. **DB Migrations Owned by `ssp-cp`:** Per `docs/repo-map.md`, `ssp-cp` owns the `spp_platform` database schema, Alembic migrations, and per-component DB migration ADRs.

## Decision

1. **Dedicated AlloyDB for PostgreSQL Hosting (`microdrive-dev` in `us-east1`):**
   - **Service:** Dedicated **Google Cloud AlloyDB for PostgreSQL** cluster and primary instance in GCP project `microdrive-dev` in region **`us-east1`** hosting logical database `spp_platform`.
   - **What Is Excluded:** Do **not** use Cloud SQL, do **not** share the in-cluster PostgreSQL instances in `spp-temporal` or `spp-factory` on GKE `md-dev`, and do **not** deploy a PostgreSQL StatefulSet inside `spp-platform`. (The factory's own PostgreSQL in `spp-factory` and Temporal's PostgreSQL in `spp-temporal` remain unchanged.)
   - **Network Connectivity:** Private IP connectivity only (no public IP) from GKE cluster `md-dev` (`spp-platform` namespace) via Private Services Access (PSA) / Direct VPC egress or AlloyDB Auth Proxy.
   - **Database Authentication:** Authenticate `ssp-cp` pods in `spp-platform` to AlloyDB using **IAM database authentication (`alloydb.databaseUser` + `alloydb.client`) bound via GKE Workload Identity (`microdrive-dev.svc.id.goog`)** wherever supported (with Secret Manager CSI-mounted credentials only if required for specific migration/bootstrap tooling—never static credentials in git or ConfigMaps).
   - **Schema Migrations:** Owned and executed by `ssp-cp` via versioned **Alembic** migrations targeting database `spp_platform`.
2. **Core Relational Tables in AlloyDB (`spp_platform` database):**
   - `provisioning_requests` (`id` / `request_id`, `idempotency_key`, `cloud`, `layout_version`, `lob`, `project_id`, `resource_type`, `resource_name`, `region`, `apm_id`, `environment`, `requester_username`, `requester_persona`, `current_state` [`requested | approved | expected | observed | failed | decommissioned`], `requested_payload` JSONB, `created_at`, `updated_at`).
   - `approved_specs` (`id`, `request_id` FK, `version`, `operation_id`, `service_account_email`, `application_tier`, `state_backend` JSONB, `security_enrichment` JSONB, `servicenow_metadata` JSONB, `cmdb_metadata` JSONB, `operations_gate` JSONB, `approved_payload` JSONB, `policy_evaluation_report` JSONB, `approved_at`).
   - `provisioning_operations` (`operation_id` PK, `request_id` FK, `operation_type` [`create | update | resize | upgrade | drift_check | rollback | decommission`], `temporal_workflow_id`, `temporal_run_id`, `k8s_job_name` [`tf-op-<operation_id>`], `status` [`pending | running | succeeded | failed | cancelled`], `expected_state_uri`, `observed_state_uri`, `cloud_resource_id`, `error_summary`, `started_at`, `completed_at`).
   - `managed_resources` (`resource_id` PK, `cloud_resource_id` UNIQUE, `project_id`, `lob`, `cloud`, `resource_type`, `resource_name`, `apm_id`, `environment`, `current_state`, `latest_approved_spec_id` FK, `drift_status` [`in_sync | drifted | unknown`], `estimated_monthly_cost_usd`, `last_observed_at`, `created_at`, `updated_at`).
   - `audit_logs` (`id` PK, `actor_username`, `actor_role`, `source_ip`, `action_type`, `request_id`, `operation_id`, `reason`, `details` JSONB, `created_at` — append-only / immutable).
   - `users` and `user_sessions` (local authentication accounts with Argon2id `password_hash`, `role`, `must_change_password`, `failed_login_attempts`, `locked_until`, `is_active`, and session/CSRF tokens for Phase 1 local login before SSO).
3. **Canonical JSON Schema Alignment:**
   - The `requested_payload` and `approved_payload` JSONB columns MUST conform to `gates/schemas/resource-request.schema.json` (`schema_version = "2.0"`, `layout_version = "2.0"`).

## Requirements

- **REQ-1 (MUST):** The SPP control plane (`ssp-cp`) MUST persist all runtime `Requested` and `Approved` state data in a dedicated **AlloyDB for PostgreSQL** cluster/instance (database `spp_platform`, region `us-east1`) in GCP project `microdrive-dev`, connected via private IP / Private Services Access (PSA) from GKE cluster `md-dev`.
- **REQ-2 (MUST):** `ssp-cp` MUST manage all `spp_platform` schema changes through versioned, repeatable **Alembic** database migrations stored in `ssp-cp`, and SHOULD authenticate to AlloyDB using GKE Workload Identity + AlloyDB IAM authentication where possible.
- **REQ-3 (MUST):** Every write to `provisioning_requests.requested_payload` and `approved_specs.approved_payload` MUST be validated against the canonical SPP JSON Schema and scanned to guarantee zero secret keys or values prior to `COMMIT`.
- **REQ-4 (MUST):** `provisioning_requests` MUST enforce client-supplied `idempotency_key` uniqueness so retried API calls return the existing `request_id` rather than creating duplicate requests.
- **REQ-5 (MUST):** `approved_specs` and `audit_logs` rows MUST be immutable (append-only); Day-2 updates (`update`, `resize`, `upgrade`, `rollback`, `decommission`) MUST insert a new `approved_specs` version row and a new `provisioning_operations` row with a new deterministic `operation_id`.
- **REQ-6 (MUST):** `managed_resources` MUST index the immutable Cloud Service Provider identifier (`cloud_resource_id`) once provisioning reaches `Observed` state so drift detection and import key off `cloud_resource_id` rather than `resource_name`.
- **REQ-7 (SHOULD):** Every state transition (`Requested -> Approved -> Expected -> Observed` or `failed`) SHOULD emit an append-only row in `audit_logs` within the same database transaction.

## Guardrails

- **GR-1:** Do not use Cloud SQL, do not share the in-cluster PostgreSQL in `spp-temporal` or `spp-factory`, and do not deploy a PostgreSQL StatefulSet in `spp-platform` for the SPP product database; use dedicated AlloyDB for PostgreSQL.
- **GR-2:** Never store raw Terraform `.tfstate` contents (`Expected` or `Observed`) in any AlloyDB PostgreSQL table or JSONB column; store only the GCS URI (`gs://microdrive-dev-spp-tfstate/expected/<project-id>/terraform.tfstate`).
- **GR-3:** Never store plaintext passwords, private keys, API keys, or cloud credentials in AlloyDB; `users.password_hash` must use Argon2id (`ADR-GLB-005`).
- **GR-4:** Never enable public IP connectivity on the AlloyDB instance, and never execute destructive `DROP TABLE` or unreviewed schema migrations in production without an accepted DB migration ADR in `ssp-cp` and Operations sign-off.

## Consequences

### Positive

- Satisfies the "don't use Cloud SQL" constraint with a managed, enterprise-grade, high-performance GCP PostgreSQL service (AlloyDB) while keeping `spp-platform` stateless inside GKE `md-dev`.
- Complete blast-radius and fault isolation between the SPP product database (dedicated AlloyDB `spp_platform`) and the in-cluster PostgreSQL instances used by `spp-factory` and `spp-temporal`.
- Supports GKE Workload Identity + AlloyDB IAM authentication and private VPC/PSA connectivity with zero static database passwords in code.

### Negative / Trade-offs

- Requires VPC Private Services Access (PSA) / Direct VPC peering between the `md-dev` GKE VPC and AlloyDB in `microdrive-dev`, plus Terraform bootstrap provisioning of the AlloyDB cluster and primary instance before `ssp-cp` deploys to `spp-platform`.

## Acceptance Criteria

- [ ] `ssp-cp` configures SQLAlchemy + Alembic to connect to the dedicated AlloyDB `spp_platform` database in `microdrive-dev` over private IP (with IAM/Workload Identity auth where supported).
- [ ] `ssp-cp` includes a dedicated DB migrations ADR and initial Alembic migration creating the core tables (`provisioning_requests`, `approved_specs`, `provisioning_operations`, `managed_resources`, `audit_logs`, `users`, `user_sessions`).
- [ ] `requested_payload` and `approved_payload` validate cleanly against `gates/schemas/resource-request.schema.json`.
- [ ] Automated tests in `ssp-cp` verify idempotency key deduplication, secret rejection, and append-only immutability of `approved_specs` and `audit_logs`.

## Success Criteria

- **SC-1:**
  - **Given** two identical `POST /api/v1/requests` calls carrying the same `Idempotency-Key` header
  - **When** `ssp-cp` processes both requests against the AlloyDB `spp_platform` database
  - **Then** only one row is created in `provisioning_requests` and both calls return the same `request_id`.
- **SC-2:**
  - **Given** a completed GCS bucket creation Job (`tf-op-<operation_id>`)
  - **When** the `ssp-workers` completion activity updates `ssp-cp`
  - **Then** `provisioning_operations.status` is set to `succeeded`, `managed_resources.cloud_resource_id` records the GCS bucket self-link/ID, `current_state` transitions to `observed`, and `expected_state_uri` / `observed_state_uri` point to `gs://microdrive-dev-spp-tfstate/...` without storing the state blob in AlloyDB.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the global data model and dedicated AlloyDB for PostgreSQL architecture |
| `ssp-cp` | Owns SQLAlchemy models, Alembic migrations, AlloyDB connection/IAM auth, and DB migration ADRs |
| `ssp-workers` | Reads `approved_specs` and updates `provisioning_operations` and `managed_resources` via `ssp-cp` / AlloyDB |
| `ssp-ui` | Consumes request, resource inventory, and audit endpoints backed by AlloyDB |
| `spp-factory-foundation` | Validates `requested` and `approved` JSONB schemas via `gates/schemas/resource-request.schema.json` (while keeping its own `spp-factory` Postgres unchanged) |

## Open Questions

- [x] **OQ-1 (PostgreSQL Hosting Offering in GCP — RESOLVED 2026-10-21):** *Resolved:* The SPP product database is **AlloyDB for PostgreSQL** in GCP (project `microdrive-dev`), not Cloud SQL.
- [x] **OQ-2 (Shared vs. Separate PostgreSQL Instance on `md-dev` — RESOLVED 2026-10-21):** *Resolved:* SPP uses a **dedicated AlloyDB cluster/instance** (database `spp_platform`) for the product—not the in-cluster Postgres on `md-dev` and not a GKE StatefulSet. The factory's own Postgres in `spp-factory` stays as-is.
- [ ] **OQ-3 (Retention & Archival of Audit Logs):** What is the required retention period in AlloyDB (`spp_platform`) vs. archival to GCS/BigQuery for `audit_logs` and historical `provisioning_operations` (e.g., 90 days hot in AlloyDB, 7 years in cold storage)?
- [ ] **OQ-4 (AlloyDB Cluster Sizing & HA Topology in `microdrive-dev` / `us-east1`):** In region `us-east1` (the sole approved GCP region, co-located with GKE cluster `md-dev`), should the `microdrive-dev` AlloyDB cluster use a single `BASIC` primary instance for non-prod/POC (`2 vCPU` / `16 GB`) or a `REGIONAL` high-availability primary + read pool?
- [ ] **OQ-5 (AlloyDB Automated Backups, PITR & CMEK Key):** To satisfy Karen's DBA requirements and `ADR-GLB-007` (`>= 90`-day retention + CMEK), what is the exact Cloud KMS CryptoKey URI (`cmek_key_id`) and continuous backup / Point-in-Time Recovery (PITR) window to configure on the AlloyDB cluster and backup plan?
- [ ] **OQ-6 (Who Provisions the AlloyDB Cluster & PSA Peering):** Will the SPP team provision the dedicated AlloyDB cluster, Private Services Access (PSA) IP range (coordinated with John Simon), and `roles/alloydb.client` + `roles/alloydb.databaseUser` IAM bindings for the `ssp-cp` Workload Identity GSA in `microdrive-dev` via a dedicated foundation Terraform step before Phase 2 (`ssp-cp` skeleton deployment)?

## Related ADRs

- [ADR-GLB-002: Languages and Technology Stack](ADR-GLB-002-languages-and-technology-stack.md)
- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](ADR-GLB-003-four-state-model.md)
- [ADR-GLB-005: Identity and Authentication](ADR-GLB-005-identity-and-authentication.md)
- [ADR-CLD-GCP-001: Runtime Platform (GKE `md-dev` and Self-Hosted Temporal)](../per-cloud/gcp/ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md)
