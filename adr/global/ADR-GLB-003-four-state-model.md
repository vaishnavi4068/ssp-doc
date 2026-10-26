# ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout

- **ADR ID:** ADR-GLB-003
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define a uniform **four-gate provisioning state model** (`Requested` → `Approved` → `Expected` → `Observed`) and storage layout across centralized **AlloyDB for PostgreSQL** (`spp_platform`) and **Google Cloud Storage (`gs://microdrive-dev-spp-tfstate`)** so that user requests remain simple and secret-free, mandatory guardrails and approvals are deterministically recorded in `Approved` state with a verifiable hash chain, and deployed infrastructure state is isolated per GCP project (one state unit = one project = one state file) with short (`<= 2 KB`) non-sensitive projections in PostgreSQL for fast UI and drift queries.

## Context

From the architecture design session (`uploads/design-digest.md`) and the sanitized four-gate design package (`IDP four-gate data model: GCS bucket and Spanner`, see [`docs/source-provenance.md`](../../docs/source-provenance.md)):

1. **Why Four Gates (`Requested -> Approved -> Expected -> Observed`):**
   - Developers want a fast, low-friction request experience without answering dozens of security and compliance questions.
   - Security ("Raju") runs automated compliance scanners that delete non-compliant cloud resources. By separating `Requested` (raw user intent) from `Approved` (where mandatory guardrails are enforced and recorded in `guardrail_trace`: CMEK in `us-east1`, retention floors, uniform bucket-level access, public access prevention, deletion protection, mandatory labels, prerequisites, and post-apply tasks), SPP guarantees every resource is compliant before Terraform runs.
   - Separating `Expected` (composed project-level Terraform inputs from every active approval) from `Observed` (Terraform state after apply or refresh scan plus a `<= 2 KB` projection and drift findings) enables deterministic drift detection (`Expected != Observed`).
2. **Storage Placement Across AlloyDB for PostgreSQL and GCS:**
   - **AlloyDB for PostgreSQL (`spp_platform` in `<spp-factory-host-project-id>`, `us-east1`):** Stores `Requested` (`submission`, `request`, `policy_evaluation`) and `Approved` (`approval`, `approval_decision`) documents **in full**, with **zero secret values, ever**. For `Expected` and `Observed`, PostgreSQL stores **only** pointers (`artifact_uri`, `plan_uri`, `state_uri`, `snapshot_uri`), object generations, state serials/lineages, canonical JSON SHA-256 hashes, a **small per-resource Observed projection (`<= 2 KB` / `< 2000` bytes)**, and `drift_finding` rows.
   - **Why `<= 2 KB` Projections in Postgres Are Allowed (and Full `.tfstate` Is Rejected):** Storing full Terraform `.tfstate`, `plan.json`, or `terraform.tfvars.json` blobs in PostgreSQL was rejected due to write amplification, TOAST/vacuum churn, and trust-boundary risks (`terraform show -json` contains clear-text sensitive values flagged under `sensitive_values`). Keeping `resource_observed.projection` under `2 KB` (`CHECK (octet_length(projection::text) < 2000)` with `fillfactor = 80`) keeps rows below PostgreSQL's TOAST threshold, strips all attributes flagged under `sensitive_values`, and upserts **only when `projection_sha256` changes** (`WHERE ro.projection_sha256 IS DISTINCT FROM EXCLUDED.projection_sha256`), so ~5,000 daily project scans write only one narrow `observation` row per project scan without dead-tuple churn.
3. **Single State Bucket (`gs://microdrive-dev-spp-tfstate`) and Per-Project State Unit Layout:**
   - Rather than creating per-LOB buckets or 5,000+ per-project buckets now, SPP uses the **single state bucket `gs://microdrive-dev-spp-tfstate`** in `us-east1` (CMEK-encrypted, object versioning enabled; no per-LOB buckets for now).
   - Within `gs://microdrive-dev-spp-tfstate`, **one state unit = one GCP project = one Terraform state file** under `projects/<project_id>/` (alongside the legacy/flat `expected/<project_id>/` and `observed/<project_id>/` paths during transition).

## Decision

### 1. The Four Gates Matrix

| Gate | What It Holds | System of Record | Written By | Mutability |
| :--- | :--- | :--- | :--- | :--- |
| **Gate 1: `Requested`** (`REQUESTED`) | Business payload verbatim (`submission.raw_payload`), plus one canonical `requested_spec` JSON document per resource (`{api_version: "idp.spp/v1", kind, action, metadata, spec}`) | AlloyDB PostgreSQL: `idp.submission`, `idp.request`, `idp.policy_evaluation` (`stage = 'requested'`) | Intake API (`ui`, `api`, `chat`, `import`, or deferred `legacy_shim`) | **Immutable** (`request_guard` trigger); any change requires a new `request` row |
| **Gate 2: `Approved`** (`APPROVED`) | Canonical requested document **plus** enforced guardrails (`approved_spec`), `guardrail_trace` (`[{rule_id, path, from, to, reason}]`), human approval decisions, and materialized `pre_apply`/`post_apply` `lifecycle_task` rows | AlloyDB PostgreSQL: `idp.approval`, `idp.approval_decision`, `idp.policy_evaluation` (`stage = 'approved'`), `idp.lifecycle_task` | `RequestWorkflow` (`req-<request_id>`), `ApprovalGateWorkflow` (`apr-<request_id>`), OPA | **Immutable once decided** (`approval_guard` trigger); decided approvals may only transition `APPROVED`/`AUTO_APPROVED` → `REVOKED`/`EXPIRED` |
| **Gate 3: `Expected`** (`EXPECTED`) | Complete project-level Terraform inputs (`terraform.tfvars.json`), `manifest.json` (Terraform/provider/module pins, members with `approved_spec_sha256`, secret references only), and `plan.json` (`terraform show -json <planfile>`) composed from every active approval in the state unit | **GCS (`gs://microdrive-dev-spp-tfstate`):** `projects/<project_id>/expected/rev-NNNNNN/{terraform.tfvars.json, manifest.json, plan.json}`; **AlloyDB pointers:** `idp.expected_revision`, `idp.expected_revision_member`, `idp.tf_operation`, `idp.policy_evaluation` (`stage = 'plan'`) | Project reconciler (`StateUnitReconcilerWorkflow` `su-gcp-<project_id>`) | **Immutable per revision** (`ifGenerationMatch=0` create-only GCS write + `expected_revision_guard` trigger) |
| **Gate 4: `Observed`** (`OBSERVED`) | Terraform state after apply (`default.tfstate`) or refresh-only drift scan (`observed/scan-<window>/plan.json`), plus small non-sensitive per-resource projection (`<= 2 KB`) and per-attribute drift findings | **GCS (`gs://microdrive-dev-spp-tfstate`):** `projects/<project_id>/default.tfstate` and `projects/<project_id>/observed/scan-<window>/plan.json`; **AlloyDB pointers & projections:** `idp.observation`, `idp.resource_observed` (`< 2000` bytes), `idp.drift_finding` | Terraform runner K8s Jobs (`spp-platform`), scheduled drift scans (`drift-<project_id>`) | State versioned in GCS; `resource_observed` upserted **only when `projection_sha256` changes** |

### 2. GCS State Bucket Layout (`gs://microdrive-dev-spp-tfstate`)

All state units use the single state bucket **`gs://microdrive-dev-spp-tfstate`** in `us-east1` (no per-LOB state buckets):

```text
gs://microdrive-dev-spp-tfstate/                       # Single SPP state bucket in us-east1 (CMEK, versioning on)
  projects/<project_id>/                               # One state unit = one GCP project = one state file
    default.tfstate                                    # OBSERVED: Terraform GCS backend state
    default.tflock                                     # Native GCS lock, present only while a run holds it
    expected/
      rev-000002/
        terraform.tfvars.json                          # EXPECTED inputs (secret references only, never values)
        manifest.json                                  # Terraform/provider/module pins, members, approval hashes
        plan.json                                      # terraform show -json <planfile>
    observed/
      scan-2026-10-23T06/
        plan.json                                      # Refresh-only plan output from a scheduled drift scan
    logs/
      tf-plan-<20hex>.log                              # Runner Job execution logs
```

```hcl
terraform {
  backend "gcs" {
    bucket = "microdrive-dev-spp-tfstate"
    prefix = "projects/<project_id>"
  }
}

provider "google" {
  impersonate_service_account = var.state_unit.executor_identity # Per-project SA, reached from central platform SA
}
```

### 3. Secret Handling Across the Four Gates

Secrets enter **only at the `Expected` gate** and never appear in PostgreSQL:
1. An `approved_spec` document may name a **secret slot** (never a secret value).
2. The `Expected` revision `manifest.json` binds the slot to a **GCP Secret Manager reference**.
3. The Kubernetes Job runner resolves the Secret Manager reference into `TF_VAR_*` in memory at execution time. (`gcs_bucket`, `spanner_instance`, and `spanner_database` authenticate via IAM and leave secret slots empty.)
4. Workers inspect state via `terraform show -json` rather than parsing raw `.tfstate`; any value flagged under `sensitive_values` stays in `gs://microdrive-dev-spp-tfstate` (same trust boundary) and is stripped before computing `resource_observed.projection`.

### 4. Canonical JSON Hashing & Hash Chain (`Requested -> Approved -> Expected -> Observed`)

Every gate document and projection is hashed using **SHA-256 over canonical JSON** (sorted keys, compact separators `(",", ":")`, UTF-8, no floats):

```python
import hashlib
import json

def canonical_sha256(doc: dict) -> str:
    return hashlib.sha256(
        json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()
```

- `submission.raw_payload_sha256` → `request.requested_spec_sha256` → `approval.approved_spec_sha256` → `expected_revision.artifact_sha256` (with each member's `approved_spec_sha256` verified against `idp.approval.approved_spec_sha256` before `plan`, per `INV-6`) → `resource_observed.projection_sha256`.

## Requirements

- **REQ-1 (MUST):** Every resource managed by SPP MUST progress through the four gates (`REQUESTED -> APPROVED -> EXPECTED -> OBSERVED`), tracked on `idp.resource.gate` (`REQUESTED | APPROVED | EXPECTED | OBSERVED`) and `idp.resource.sync_status` (`PENDING | IN_SYNC | DRIFTED | FAILED | UNKNOWN`).
- **REQ-2 (MUST):** `Requested` (`idp.submission`, `idp.request`) and `Approved` (`idp.approval`, `idp.approval_decision`) documents MUST be stored in full in centralized **AlloyDB for PostgreSQL** (`spp_platform`) and MUST NOT contain any secret values (`INV-1`).
- **REQ-3 (MUST):** `Expected` (`terraform.tfvars.json`, `manifest.json`, `plan.json`) and `Observed` (`default.tfstate`, refresh scan `plan.json`) artifacts MUST be stored in the single GCS bucket **`gs://microdrive-dev-spp-tfstate`** in `us-east1` under `projects/<project_id>/` (one state unit = one GCP project = one state file); full `.tfstate`, `plan.json`, or `terraform.tfvars.json` blobs MUST NOT be stored in AlloyDB.
- **REQ-4 (MUST):** Every `Expected` revision artifact (`projects/<project_id>/expected/rev-NNNNNN/terraform.tfvars.json`) MUST be written to GCS with `ifGenerationMatch=0` (create-only) and recorded in `idp.expected_revision` with its GCS `artifact_generation` and canonical `artifact_sha256` (`INV-5`).
- **REQ-5 (MUST):** Before running `terraform plan`, the reconciler MUST verify that every member's `approved_spec_sha256` in `manifest.json` equals `idp.approval.approved_spec_sha256` in AlloyDB (`INV-6`); on mismatch, the revision MUST be marked blocked (`blocked_reason = 'approved_hash_mismatch'`).
- **REQ-6 (MUST):** `idp.resource_observed.projection` in AlloyDB MUST strip all attributes flagged under `sensitive_values`, MUST be `< 2000` bytes (`CHECK (octet_length(projection::text) < 2000)`), and MUST be upserted only when `projection_sha256` changes.
- **REQ-7 (MUST):** Every guardrail mutation applied at the `Approved` gate MUST be explicitly written into `approved_spec` and recorded in `approval.guardrail_trace` (`[{rule_id, path, from, to, reason}]`).

## Guardrails

- **GR-1 (`INV-1`):** Zero secrets in `Requested` or `Approved` AlloyDB records, and zero sensitive values in `resource_observed.projection`.
- **GR-2 (`INV-5` & `INV-6`):** Never apply an unverified plan or allow in-place edits of rendered `Expected` revision artifacts in GCS (`ifGenerationMatch=0` create-only + SHA-256 hash verification).
- **GR-3 (`INV-8`):** Never split a single 2.0 GCP project across multiple state files, and never create per-LOB state buckets; use `gs://microdrive-dev-spp-tfstate` with one state unit per project.
- **GR-4:** Never store `Expected` or `Observed` `.tfstate` or `plan.json` blobs in AlloyDB; only pointers, hashes, `plan_summary` counts (`{add, change, destroy, replace}`), `<= 2 KB` projections, and `drift_finding` rows are permitted in AlloyDB.

## Consequences

### Positive

- AlloyDB remains fast, queryable, and free of cloud secrets and TOAST churn: UI views (`idp.v_resource_status`) and drift dashboards can query resource status and `<= 2 KB` projections across 5,000+ projects without reading GCS `.tfstate` files.
- `guardrail_trace` makes every injected policy decision transparent and auditable ("why is retention 90 days on my bucket?").
- Create-only GCS artifact writes (`ifGenerationMatch=0`) and the canonical SHA-256 hash chain guarantee that what was approved in AlloyDB is what gets planned and applied in GCS.

### Negative / Trade-offs

- Because each 2.0 GCP project is a single state unit (`default.tfstate`), concurrent operations targeting the same project are serialized by `StateUnitReconcilerWorkflow` (`su-gcp-<project_id>`) and GCS native lock (`default.tflock`).

## Acceptance Criteria

- [ ] `specs/data-model/spp_state_model.sql` defines the four-gate tables, `resource_observed_projection_small` (`< 2000` bytes) constraint, and immutability triggers (`request_guard`, `approval_guard`, `expected_revision_guard`, `gate_event_guard`).
- [ ] `ssp-cp` and `ssp-workers` implement canonical JSON SHA-256 hashing (`canonical_sha256`) and verify `approved_spec_sha256` before planning (`INV-6`).
- [ ] All state units point to `gs://microdrive-dev-spp-tfstate` with prefix `projects/<project_id>`.

## Success Criteria

- **SC-1:**
  - **Given** a `Requested` document submitted to `ssp-cp`
  - **When** it advances to `Approved` and is composed into an `Expected` revision (`rev-000002`)
  - **Then** `submission` and `request` are immutable in AlloyDB, `approval` records `approved_spec`, `approved_spec_sha256`, and `guardrail_trace`, and `expected/rev-000002/terraform.tfvars.json` is written to `gs://microdrive-dev-spp-tfstate` with `ifGenerationMatch=0` and matching `approved_spec_sha256` hashes.
- **SC-2:**
  - **Given** a completed `apply` or `refresh_plan` on a state unit
  - **When** `ssp-workers` records the observation in AlloyDB
  - **Then** `idp.observation` stores only the GCS URI (`gs://microdrive-dev-spp-tfstate/projects/<project_id>/default.tfstate`), generation, and serial, while `idp.resource_observed` stores a non-sensitive JSON projection `< 2000` bytes and skips the `UPDATE` if `projection_sha256` is unchanged.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the four-gate state model, hash chain, `<= 2 KB` projection rule, and `gs://microdrive-dev-spp-tfstate` layout |
| `ssp-cp` | Persists `Requested` and `Approved` gate rows, computes `canonical_sha256`, records `guardrail_trace`, and exposes `idp.v_resource_status` |
| `ssp-workers` | Renders create-only `Expected` revisions (`ifGenerationMatch=0`) in `gs://microdrive-dev-spp-tfstate`, runs K8s Jobs, and writes `<= 2 KB` `Observed` projections |
| `ssp-ui` | Queries `idp.v_resource_status`, `guardrail_trace`, and `resource_observed.projection` without fetching GCS state files |
| `ssp-module-<type>` | Consumes `tfvars_collection` entries from `terraform.tfvars.json` and outputs `cloud_resource_id` |
| `spp-factory-foundation` | Validates canonical JSON schemas, hash-chain invariants (`INV-1..INV-9`), and projection size constraints |

## Open Questions

- [x] **OQ-1 (Single State Bucket vs. Per-LOB Buckets — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Use a **single state bucket `gs://microdrive-dev-spp-tfstate`** in `us-east1` for now (no per-LOB state buckets).
- [x] **OQ-2 (Short Observed-State & Drift Summaries in PostgreSQL — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Short non-sensitive observed-state projections (`<= 2 KB` / `< 2000` bytes in `idp.resource_observed`) and `idp.drift_finding` rows in AlloyDB for PostgreSQL are explicitly allowed; full `Expected`/`Observed` state files stay in GCS.
- [ ] **OQ-3 (Unverified Source Gaps in Schemas & Examples — SOURCE GAP [Owner: Manoj]):** **Unverified (source gap):** In the source design package, `schemas/idp-common.schema.json`, `schemas/gcs_bucket.schema.json`, `schemas/spanner.schema.json`, `schemas/project-expected.schema.json`, `examples/resource_kinds.json`, `examples/expected/rev-000002/{manifest.json,terraform.tfvars.json}`, and `tools/validate_examples.py` (49 stdlib checks) were listed in the package file tree (photo 6548) but were `[NOT CAPTURED]` in the photographs (`examples/gcs_bucket.gates.json` is ~85% captured and reconstructed in `specs/examples/gcs_bucket.gates.json`). Must be authored/verified in `ssp-cp` and `spp-factory-foundation`.

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-007: Governance Gates and Policy (Rego)](ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-AUT-001: Terraform Execution via Deterministic Kubernetes Jobs](../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-AUT-002: Day-2 Operations Scope](../automation/ADR-AUT-002-day-2-operations-scope.md)
