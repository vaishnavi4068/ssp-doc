# ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End (No UI)

- **ADR ID:** ADR-SVC-001
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-storage-gcp@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-gcs` (`templates/resource-repo`), `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the end-to-end scope, request/approved contracts, security guardrails, and execution path for SPP's **first vertical slice**: provisioning a **Google Cloud Storage (GCS) bucket (`google_storage_bucket`)** from the `ssp-cp` REST API through all four states (`Requested -> Approved -> Expected -> Observed`) via Temporal (`ssp-workers`) and a Kubernetes Job Terraform runner (`spp-platform`) into `gs://microdrive-dev-spp-tfstate`, with **no UI**.

## Context

In the design discussion (`uploads/design-digest.md`) and build order (`ADR-BP-002`), the team chose a GCP Cloud Storage bucket (`google_storage_bucket`) as the first resource to provision end-to-end because:

1. It exercises every architectural layer of the platform (API authentication, synchronous `Requested` write in PostgreSQL, `Approved` security/operations guardrail enrichment, OPA policy evaluation, Temporal workflow orchestration on the `platform` namespace, deterministic Kubernetes Job execution `tf-op-<operation_id>` in `spp-platform`, Workload Identity + SA impersonation, and `Expected`/`Observed` state persistence in `gs://microdrive-dev-spp-tfstate`).
2. It has zero external config-management dependencies (unlike VMs, which currently have a ~2-hour Ansible host-build playbook, or databases, which have Jenkins DBA jobs).
3. It directly validates Raju's core security requirements (Customer-Managed Encryption Keys `CMEK`, `>= 90`-day retention policy, uniform bucket-level access, public access prevention, object versioning, and mandatory governance labels).
4. **No UI (`ssp-ui`) is included in this slice:** requests are submitted and inspected strictly via the `ssp-cp` HTTP JSON API so backend reliability and state transitions are proven first.

## Decision

1. **Headless API-to-Cloud Flow for the First Vertical Slice:**
   - **Step 1 (`Requested`):** Authenticated caller invokes `POST /api/v1/requests` on `ssp-cp` with a minimal GCS bucket payload (`cloud = "gcp"`, `layout_version = "2.0"`, `lob`, `project_id`, `resource_type = "google_storage_bucket"`, `resource_name`, `region = "us-east1"`, `apm_id`, `environment`, `labels`, and optional `parameters` such as `storage_class`). `ssp-cp` validates the JSON Schema, checks zero secrets, and synchronously writes the `Requested` row to PostgreSQL without calling Temporal.
   - **Step 2 (`Approved`):** `ssp-cp` enriches the request into an `Approved` specification by injecting:
     - `operation_id` (`op-<ulid>`)
     - `service_account_email` (the target project's dedicated provisioning SA)
     - `state_backend` (`bucket = "microdrive-dev-spp-tfstate"`, `expected_key = "expected/<project_id>/terraform.tfstate"`, `observed_key = "observed/<project_id>/terraform.tfstate"`)
     - `application_tier` (resolved from `apm_id`)
     - `security` (`cmek_enabled = true`, `cmek_key_id = "projects/microdrive-dev/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>"` [owner: `vaishnavi4068`], `retention_days >= 90` [`retention_period >= 7776000` seconds], `public_access_prevention = "enforced"`, `raju_baseline_applied = true`, `uniform_bucket_level_access = true`, `versioning_enabled = true`)
     - `operations_gate` (`approved = true`, `bypass_allowed = false`; ServiceNow and CMDB fields are populated only as static schema placeholders for `gates/schemas/resource-request.schema.json` compatibility—no external ServiceNow/CMDB calls or mock adapters are invoked in the `microdrive-dev` MVP)
     `ssp-cp` evaluates the OPA policy suite (`spp_gate.rego` + `gcs_bucket.rego`) and persists the immutable `Approved` record in PostgreSQL.
   - **Step 3 (`Expected`):** `ssp-cp` starts the provisioning workflow on the `platform` Temporal namespace (`temporal-frontend.spp-temporal.svc.cluster.local:7233`). `ssp-workers` launches deterministic Kubernetes Job `tf-op-<operation_id>` in namespace `spp-platform` (on node pool `spp-pool`), which runs `terraform init` and `terraform apply` against the GCS bucket module and writes `Expected` state to `gs://microdrive-dev-spp-tfstate/expected/<project_id>/terraform.tfstate`.
   - **Step 4 (`Observed`):** Following apply (and on scheduled drift scans), an independent capture job reads actual bucket configuration from the GCP Storage API keyed by immutable GCS bucket resource ID (`outputs.cloud_resource_id`), writes `Observed` state to `gs://microdrive-dev-spp-tfstate/observed/<project_id>/terraform.tfstate`, compares `Observed` vs. `Expected` (alert-only on drift, per `ADR-AUT-002`), and `ssp-workers` updates the request status in `ssp-cp` to `observed`.

## Requirements

- **REQ-1 (MUST):** The first vertical slice MUST operate end-to-end via the `ssp-cp` REST API (`POST /api/v1/requests`, `GET /api/v1/requests/{request_id}`) with **no UI dependency**.
- **REQ-2 (MUST):** The GCS bucket Terraform module MUST enforce:
  1. `encryption.default_kms_key_name = var.cmek_key_id` (non-empty CMEK key reference in `us-east1`, placeholder `projects/microdrive-dev/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>`, owner: `vaishnavi4068`)
  2. `retention_policy.retention_period >= 7776000` (`>= 90` days in seconds, with `retention_policy.is_locked = false` by default in `dev`/`sandbox` so non-prod buckets can be decommissioned cleanly when empty)
  3. `versioning.enabled = true`
  4. `uniform_bucket_level_access = true`
  5. `public_access_prevention = "enforced"`
  6. `force_destroy = false`
  7. Effective labels containing `apm_id`, `cost_center`, `environment`, `owner`, `data_classification`, and `managed_by = "spp"`
  8. Audit logging via **GCP Cloud Audit Logs** (no separate `logging.log_bucket` required in MVP)
- **REQ-3 (MUST):** The GCS bucket module MUST output `cloud_resource_id` (`google_storage_bucket.this.id` / `self_link`) and `bucket_name` so `Observed` state and drift detection match by immutable CSP resource ID (`ADR-AUT-002`).
- **REQ-4 (MUST):** Both `Requested` and `Approved` payloads MUST contain zero secrets (`ADR-GLB-003`, `ADR-GLB-005`).
- **REQ-5 (MUST):** All 7 stages of the factory verification gate (`gates/scripts/run_gate.sh`), including `terraform test` with `mock_provider "google"` and `tfsec`, MUST pass on the GCS bucket module.

## Guardrails

- **GR-1:** Never allow a GCS bucket to be created with `public_access_prevention != "enforced"` or `uniform_bucket_level_access != true`.
- **GR-2:** Never allow a GCS bucket to be created without CMEK encryption or with `retention_days < 90`.
- **GR-3:** Do not couple Phase 3 completion to any `ssp-ui` frontend component.

## Consequences

### Positive

- Proves the entire SPP control-plane and execution architecture end-to-end with a real GCP resource and real GCS state files in `gs://microdrive-dev-spp-tfstate`.
- Reuses and aligns directly with the reference GCS bucket implementation in `spp-factory-foundation/templates/resource-repo/`.

### Negative / Trade-offs

- Requires a valid Cloud KMS CryptoKey (`cmek_key_id`) in `microdrive-dev` (with `roles/cloudkms.cryptoKeyEncrypterDecrypter` granted to the project's GCS service agent) before live `terraform apply` can succeed in `microdrive-dev`.

## Acceptance Criteria

- [ ] Per-service GCS ADR and API/DB ADRs are present in `ssp-cp`, and the GCS Terraform module + Rego policy passes `run_gate.sh`.
- [ ] Submitting a `POST /api/v1/requests` payload for `google_storage_bucket` transitions through `Requested -> Approved -> Expected -> Observed`.
- [ ] `gs://microdrive-dev-spp-tfstate/expected/<project_id>/terraform.tfstate` and `gs://microdrive-dev-spp-tfstate/observed/<project_id>/terraform.tfstate` are populated and `cloud_resource_id` is recorded in PostgreSQL.

## Success Criteria

- **SC-1:**
  - **Given** a minimal `Requested` JSON payload for a GCS bucket (`storage_class = "STANDARD"`, `region = "us-east1"`) submitted to `POST /api/v1/requests`
  - **When** `ssp-cp` and `ssp-workers` process the request
  - **Then** `ssp-cp` writes `Requested` and enriched `Approved` records in PostgreSQL, `ssp-workers` runs K8s Job `tf-op-<operation_id>` in `spp-platform`, the GCS bucket is created with CMEK and `>= 90`-day retention, and state files exist under `expected/` and `observed/` in `gs://microdrive-dev-spp-tfstate`.
- **SC-2:**
  - **Given** a GCS bucket request attempting to set `retention_days = 30` or `public_access_prevention = "inherited"`
  - **When** evaluated by the OPA policy gate in CI or `ssp-cp`
  - **Then** the request is rejected before any Temporal workflow or Kubernetes Job is started.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the first vertical slice scope and contract (`ADR-SVC-001`) |
| `ssp-cp` | Hosts the detailed per-service GCS ADR, `Requested`/`Approved` enrichment, and API endpoints |
| `ssp-workers` | Executes the Temporal workflow and launches `tf-op-<operation_id>` for GCS bucket creation |
| `ssp-module-gcs` | Houses the GCS bucket Terraform module, `gcs_bucket.rego` policies, examples, and `tftest.hcl` |
| `spp-factory-foundation` | Validates the GCS module via `templates/resource-repo` and `gates/scripts/run_gate.sh` |

## Open Questions

- [x] **OQ-1 (CMEK Key URI in `microdrive-dev` — RESOLVED / USER-SUPPLIED `TODO: vaishnavi4068`):** *Resolved:* The user (`vaishnavi4068`) will create and provide the Cloud KMS key in `microdrive-dev` (`us-east1`). Placeholder (owner: `vaishnavi4068`): `projects/microdrive-dev/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>`.
- [x] **OQ-2 (Access Logging Bucket Requirement — RESOLVED 2026-10-21):** *Resolved:* Use **GCP Cloud Audit Logs only** (no separate access-log bucket required for MVP).
- [x] **OQ-3 (Retention Policy Lock — RESOLVED 2026-10-21):** *Resolved:* `retention_policy.is_locked` defaults to **`false` in `dev`/`sandbox`**; setting `is_locked = true` is restricted to the `operations` persona.

## Related ADRs

- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-007: Governance Gates and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-AUT-001: Terraform Execution via Kubernetes Jobs](../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-AUT-002: Day-2 Operations Scope](../automation/ADR-AUT-002-day-2-operations-scope.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
