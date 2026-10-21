# ADR-GLB-003: Four-State Provisioning Model and Storage Layout

- **ADR ID:** ADR-GLB-003
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define a uniform four-state lifecycle (`Requested`, `Approved`, `Expected`, `Observed`) and storage layout across centralized PostgreSQL and Google Cloud Storage (GCS) so that user requests remain simple and secret-free, mandatory guardrails are deterministically applied in `Approved` state, and deployed infrastructure state is isolated per GCP project without PostgreSQL write amplification or 5,000+ bucket sprawl.

## Context

During the architecture design session (`uploads/design-digest.md`), the team evaluated how to represent resource lifecycle states and where to store Terraform state:

1. **Why Four States:**
   - Developers want a fast, low-friction request experience without answering dozens of security and compliance questions ("there's so many options… I'm getting overloaded").
   - Security ("Raju") currently runs automated compliance scanners that delete non-compliant cloud resources randomly. By separating `Requested` (raw user intent) from `Approved` ("where we sprinkle all our niceness on it": CMEK, `>= 90`-day retention, Raju security rules, naming, labels, APM tier defaults), SPP guarantees every resource is compliant before Terraform ever runs.
   - Separating `Expected` (desired deployed state) from `Observed` (actual cloud state) enables drift detection when out-of-band changes occur.
2. **Why PostgreSQL for `Requested`/`Approved` and GCS for `Expected`/`Observed`:**
   - The team debated storing Terraform state in PostgreSQL, MongoDB Atlas, or cloud object storage.
   - PostgreSQL was rejected for Terraform state due to write amplification, TOAST/vacuum churn on large state JSON blobs, and trust-boundary concerns (centralizing every secret from every project's Terraform state into one database). MongoDB Atlas had no native Terraform backend and an unverified security posture.
   - The finalized decision stores `Requested` and `Approved` metadata in **centralized PostgreSQL in GCP (dedicated AlloyDB for PostgreSQL, `spp_platform` database, with zero secrets)**, and stores `Expected` and `Observed` Terraform states in **Google Cloud Storage (GCS)** with native GCS object locking (`ADR-GLB-004`).
3. **Why One State File per Project in Two Folders (`expected/` and `observed/`):**
   - Per-resource or per-category state files (e.g., separate network, IAM, and database states inside one project) were rejected because cross-state dependencies are brittle to manage.
   - Creating 5,000+ individual state buckets (one bucket per project) was noted by Manoj as operationally difficult to manage at enterprise scale, leading to the **one bucket per Line of Business (LOB)** design (in each GCP LOB host project) with **two top-level folders (`expected/` and `observed/`)** and **one state file per GCP service project**. In the initial `microdrive-dev` runtime environment, the platform state bucket is `gs://microdrive-dev-spp-tfstate` (`ADR-AUT-001`).

## Decision

1. **Four Canonical States:**
   - **`Requested` (PostgreSQL):** The user's or API caller's raw request metadata. Written synchronously by `ssp-cp` directly to centralized PostgreSQL in GCP. Does **not** go through Temporal on write, and contains **zero secrets**.
   - **`Approved` (PostgreSQL):** The immutable, policy-enriched specification produced by `ssp-cp` after injecting mandatory guardrails (CMEK key reference, `retention_days >= 90`, `public_access_prevention = "enforced"`, Raju security baseline flags, APM ID tier defaults, standard resource naming, mandatory labels, and `operations_gate` approval, plus non-blocking post-MVP interface placeholder fields for ServiceNow/CMDB) and passing OPA validation. Contains **zero secrets**.
   - **`Expected` (GCS):** The desired deployed Terraform state written by the Kubernetes Job runner after `terraform apply`. May contain secrets injected post-approval during execution. Stored at `expected/<project-id>/terraform.tfstate`.
   - **`Observed` (GCS):** The actual cloud state captured from GCP by resource ID for drift comparison against `Expected`. Stored at `observed/<project-id>/terraform.tfstate`.
2. **State Granularity & Bucket Placement:**
   - **One state file per 2.0 GCP project** (never per-resource or per-category).
   - **Two folders per state bucket:** `expected/<project-id>/terraform.tfstate` and `observed/<project-id>/terraform.tfstate`.
   - **Bucket topology:** In the `microdrive-dev` GCP environment (Phase 1 / first vertical slice), Terraform state is stored in `gs://microdrive-dev-spp-tfstate`. At enterprise scale across LOBs, state is stored in **one GCS bucket per LOB host project**.

## Requirements

- **REQ-1 (MUST):** Every resource managed by SPP MUST progress through the four states (`Requested -> Approved -> Expected -> Observed`) in strict order.
- **REQ-2 (MUST):** `Requested` and `Approved` states MUST be stored in centralized PostgreSQL in GCP and MUST NOT contain any secrets, passwords, private keys, API keys, or tokens.
- **REQ-3 (MUST):** Persisting a `Requested` record MUST be a synchronous database write in `ssp-cp` and MUST NOT depend on Temporal availability.
- **REQ-4 (MUST):** `Expected` and `Observed` states MUST be stored in GCS (`gs://microdrive-dev-spp-tfstate` in `microdrive-dev`, and per-LOB buckets `gs://<lob-state-bucket>` at scale) under `expected/<project-id>/terraform.tfstate` and `observed/<project-id>/terraform.tfstate`.
- **REQ-5 (MUST NOT):** The platform MUST NOT store `Expected` or `Observed` Terraform state files in PostgreSQL or MongoDB, and MUST NOT split a single 2.0 GCP project across per-resource or per-category state files.

## Guardrails

- **GR-1:** Zero secrets in `Requested` or `Approved` PostgreSQL records; any payload with secret keys or credential patterns must be rejected by the JSON Schema and OPA gate.
- **GR-2:** Never transition a request to `Expected` (Terraform execution) unless it has reached `Approved` state with all security and operations gates satisfied.
- **GR-3:** Never use per-category or per-resource Terraform state files within a 2.0 GCP project.

## Consequences

### Positive

- Centralized PostgreSQL remains fast, queryable, and completely free of cloud secrets and Terraform state bloat.
- Every resource within a 2.0 GCP project shares one state file (`expected/<project-id>/terraform.tfstate`), allowing clean intra-project references (IAM, VPC, storage, compute) without fragile cross-state outputs.
- Two-folder layout (`expected/` and `observed/`) cleanly supports drift detection without mutating the `Expected` baseline during out-of-band observation scans.

### Negative / Trade-offs

- Because each 2.0 project has a single Terraform state file, concurrent runs targeting the same project must be serialized (via GCS native object locking and Temporal per-project workflow serialization) so two runs do not collide.
- `Expected` and `Observed` state files in GCS may contain provider-generated sensitive attributes, requiring strict IAM and CMEK encryption on the state bucket.

## Acceptance Criteria

- [ ] `ssp-cp` persists `Requested` and `Approved` records in PostgreSQL and validates both against the canonical JSON Schema and Rego secret-scanning rules.
- [ ] `ssp-workers` configures the Terraform GCS backend for `Expected` state at `gs://microdrive-dev-spp-tfstate/expected/<project-id>/terraform.tfstate` and writes/refreshes `Observed` state at `gs://microdrive-dev-spp-tfstate/observed/<project-id>/terraform.tfstate`.
- [ ] OPA policy rules enforce `state_backend.expected_key == "expected/<project_id>/terraform.tfstate"` and `state_backend.observed_key == "observed/<project_id>/terraform.tfstate"`.

## Success Criteria

- **SC-1:**
  - **Given** a developer submitting a valid GCS bucket request via `POST /api/v1/requests`
  - **When** `ssp-cp` processes the request
  - **Then** a `Requested` row is written synchronously to PostgreSQL with zero secrets and without calling Temporal, followed by `Approved` enrichment with CMEK, `>= 90`-day retention, and required labels.
- **SC-2:**
  - **Given** an `Approved` request for `project_id = "microdrive-dev"`
  - **When** the Kubernetes Job runner executes Terraform in `spp-platform`
  - **Then** `Expected` state is persisted to `gs://microdrive-dev-spp-tfstate/expected/microdrive-dev/terraform.tfstate` and `Observed` state is persisted to `gs://microdrive-dev-spp-tfstate/observed/microdrive-dev/terraform.tfstate`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the 4-state contract and GCS storage layout |
| `ssp-cp` | Implements `Requested` and `Approved` PostgreSQL persistence and guardrail enrichment |
| `ssp-workers` | Orchestrates `Approved -> Expected -> Observed` transitions and GCS state backend paths |
| `ssp-ui` | Displays the 4 lifecycle states (`Requested`, `Approved`, `Expected`, `Observed`) in order tracking |
| `ssp-module-<type>` | Outputs immutable GCP resource IDs and composes into the per-project state file |
| `spp-factory-foundation` | Enforces 4-state schema and Rego rules in `gates/` |

## Open Questions

- [ ] **OQ-1 (`gs://microdrive-dev-spp-tfstate` vs. Per-LOB Buckets):** Confirm whether `gs://microdrive-dev-spp-tfstate` serves as the LOB state bucket for the `microdrive-dev` environment during Phases 1–4, and what naming convention (`gs://spp-tfstate-<lob>-<env>`) will be used when onboarding production GCP LOB host projects.
- [ ] **OQ-2 (Root Module Composition per Project):** Since `Expected` state is one state file per project (`expected/<project-id>/terraform.tfstate`) while modules live in per-resource repos (`ssp-module-gcs`, `ssp-module-spanner`), confirm how `ssp-cp`/`ssp-workers` composes multiple resource instances of a project into the project's composite root `.tf.json` / `.tf` bundle before launching the K8s Job.
- [ ] **OQ-3 (Post-Approval Secret Injection Source):** When a resource requires secrets injected after `Approved` state into `Expected`, confirm whether secrets are fetched from GCP Secret Manager or Akeyless (noted in the design session as hosted outside the cloud).

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-004: Data Model and Database](ADR-GLB-004-data-model-and-database.md)
- [ADR-AUT-001: Terraform Execution via Kubernetes Jobs](../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-AUT-002: Day-2 Operations Scope](../automation/ADR-AUT-002-day-2-operations-scope.md)
