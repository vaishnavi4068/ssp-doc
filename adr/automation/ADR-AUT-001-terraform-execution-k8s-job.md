# ADR-AUT-001: Terraform Execution via Deterministic Kubernetes Jobs

- **ADR ID:** ADR-AUT-001
- **Level:** automation
- **Status:** Proposed
- **Owner:** Dwayne (Shared Mailbox: `spp-automation@tbd`, Named Owner: `Dwayne`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the Terraform execution architecture in which Temporal workers (`ssp-workers`) launch **one isolated Kubernetes Job per Terraform run** inside the `spp-platform` namespace on GKE cluster `md-dev` (named deterministically from `operation_id`), poll status every ~30 seconds, reattach idempotently on worker retry, and persist `Expected` and `Observed` state in `gs://microdrive-dev-spp-tfstate`.

## Context

In the design discussion (`uploads/design-digest.md`):

1. **Why Separate Kubernetes Jobs Instead of Running Terraform Inside the Worker:**
   - Dwayne pushed for running each Terraform operation in its own Kubernetes Job separate from the Temporal worker pod so execution is "massively parallel" and survives Temporal worker restarts or crashes without killing in-flight `terraform apply` processes.
   - Norm initially questioned whether separate runners were over-engineering (especially regarding cross-cluster callback ingress), and the team resolved both concerns by:
     1. Running the Temporal workers and the Kubernetes Jobs in the **same GKE cluster (`md-dev`) and namespace (`spp-platform`)** on the dedicated tainted `spp-pool` node pool.
     2. Naming every Kubernetes Job **deterministically from `operation_id`** (`tf-op-<operation_id>`) so a retried Temporal activity checks for the existing Job and reattaches rather than spawning a duplicate run.
     3. Using **~30-second status polling** from the Temporal activity first (avoiding callback ingress complexity), with the option to add an internal completion callback later.
2. **State Bucket in `microdrive-dev`:**
   - All Terraform runner Jobs in the `microdrive-dev` environment store `Expected` and `Observed` state in `gs://microdrive-dev-spp-tfstate` under `expected/<project_id>/terraform.tfstate` and `observed/<project_id>/terraform.tfstate` (`ADR-GLB-003`).

## Decision

1. **One Kubernetes Job per Run in `spp-platform`:**
   - Temporal workers (`ssp-workers`) polling the `platform` Temporal namespace MUST NOT invoke the `terraform` binary inside the worker container.
   - For each approved operation (`operation_id`), the Temporal activity launches a Kubernetes `batch/v1` `Job` in namespace `spp-platform`.
2. **Deterministic Job Name & Idempotent Reattachment:**
   - The Kubernetes Job name MUST be derived deterministically from `operation_id`: `tf-op-<operation_id>` (if `len("tf-op-" + operation_id) > 63`, use `tf-op-` + first 50 chars of `operation_id` + `-` + 6-char SHA-256 prefix).
   - When the Temporal activity starts (including after a worker crash, restart, or activity retry):
     - It calls the Kubernetes API (`read_namespaced_job`) for `tf-op-<operation_id>` in `spp-platform`.
     - If the Job already exists (`409 AlreadyExists` on create or found on read), the activity **reattaches** to the existing Job and resumes polling without creating a second Job.
3. **Scheduling, Identity, and Polling:**
   - Each Job pod MUST include `nodeSelector: workload=spp` and toleration `dedicated=spp:NoSchedule` (`ADR-CLD-GCP-001`), `restartPolicy: Never`, `backoffLimit: 0` (retries are controlled explicitly by Temporal), non-root `securityContext`, and CPU/memory/timeout (`activeDeadlineSeconds`) limits.
   - Each Job authenticates via GKE Workload Identity (`microdrive-dev.svc.id.goog`) and impersonates only the single target project's dedicated service account (`ADR-GLB-005`).
   - The Temporal activity polls Job status every **~30 seconds** (sending Temporal activity heartbeats on each poll) until `status.succeeded >= 1` or `status.failed >= 1`.
4. **State Persistence in `gs://microdrive-dev-spp-tfstate`:**
   - The runner initializes the GCS backend pointing to bucket `gs://microdrive-dev-spp-tfstate` with prefix/key `expected/<project_id>/terraform.tfstate`.
   - Upon completion of `terraform apply`, the runner captures/updates `observed/<project_id>/terraform.tfstate` in `gs://microdrive-dev-spp-tfstate` and emits a structured result summary (`cloud_resource_id`, `expected_state_uri`, `observed_state_uri`, outputs).

## Requirements

- **REQ-1 (MUST):** `ssp-workers` MUST execute every Terraform operation (`create`, `update`, `resize`, `upgrade`, `drift_check`, `rollback`, `decommission`) as an isolated Kubernetes Job in namespace `spp-platform` on node pool `spp-pool`.
- **REQ-2 (MUST):** The Kubernetes Job name MUST be derived deterministically from `operation_id` (`tf-op-<operation_id>`) so that Temporal worker restarts or activity retries reattach to an in-flight Job and never spawn concurrent duplicate runs.
- **REQ-3 (MUST):** The Temporal activity in `ssp-workers` MUST poll the Kubernetes Job status every ~30 seconds and emit Temporal heartbeats on each poll cycle.
- **REQ-4 (MUST):** The runner Job MUST configure its Terraform GCS state backend against `gs://microdrive-dev-spp-tfstate` using `expected/<project_id>/terraform.tfstate` for `Expected` state and `observed/<project_id>/terraform.tfstate` for `Observed` state.
- **REQ-5 (MUST):** Concurrent operations targeting the same `project_id` MUST be serialized (both via Temporal workflow locking per `project_id` and GCS native state locking on `expected/<project_id>/terraform.tfstate`).
- **REQ-6 (SHOULD):** Completed Kubernetes Jobs SHOULD be retained for a configurable TTL (`ttlSecondsAfterFinished`, e.g., `86400` seconds / 24 hours) after logs and results are persisted so pod logs remain inspectable for debugging without leaking completed Job objects indefinitely.

## Guardrails

- **GR-1:** Never execute `terraform init`, `terraform plan`, `terraform apply`, or `terraform destroy` inside the long-lived `ssp-workers` pod.
- **GR-2:** Never use random UUIDs or timestamps in Kubernetes Job names; the Job name must be a pure deterministic function of `operation_id`.
- **GR-3:** Never mount static cloud service account keys into `tf-op-<operation_id>` Jobs; use Workload Identity and per-project SA impersonation only.

## Consequences

### Positive

- **Crash Resilience:** If a `ssp-workers` pod restarts or scales down mid-apply, the `tf-op-<operation_id>` Kubernetes Job continues running unaffected on `spp-pool`, and the replacement worker reattaches to `tf-op-<operation_id>` seamlessly.
- **Massive Parallelism:** Hundreds of Terraform runs across different 2.0 projects can execute concurrently as independent K8s Jobs scaled by GKE `spp-pool` without starving Temporal workers of CPU or memory.
- **Zero Callback Ingress Complexity:** ~30-second polling within the same GKE cluster (`spp-platform`) requires no webhook ingress or callback authentication tokens.

### Negative / Trade-offs

- Polling at ~30s intervals adds up to 30 seconds of latency between Job completion and workflow advancement (acceptable for infrastructure provisioning; can be augmented with an in-cluster callback later if sub-second notification is needed).

## Acceptance Criteria

- [ ] `ssp-workers` implements the deterministic `tf-op-<operation_id>` Kubernetes Job launcher with idempotent create-or-reattach logic and ~30s heartbeat polling.
- [ ] Runner Jobs schedule onto `spp-pool` (`workload=spp` / `dedicated=spp:NoSchedule`) in namespace `spp-platform` and write state to `gs://microdrive-dev-spp-tfstate`.
- [ ] Chaos/unit test verifies that restarting the activity while `tf-op-<operation_id>` is `Active` reattaches to the same Job without creating a second Job.

## Success Criteria

- **SC-1:**
  - **Given** an approved operation with `operation_id = "op-20261021-0001"` for `project_id = "microdrive-dev"`
  - **When** `ssp-workers` executes the Terraform runner activity
  - **Then** it creates Kubernetes Job `tf-op-op-20261021-0001` in namespace `spp-platform`, polls every ~30s, and persists state to `gs://microdrive-dev-spp-tfstate/expected/microdrive-dev/terraform.tfstate` and `gs://microdrive-dev-spp-tfstate/observed/microdrive-dev/terraform.tfstate`.
- **SC-2:**
  - **Given** an in-flight Kubernetes Job `tf-op-op-20261021-0001` and a simulated `ssp-workers` pod termination
  - **When** Temporal retries the activity on another worker pod
  - **Then** the worker detects existing Job `tf-op-op-20261021-0001`, reattaches to its status loop, and completes the workflow with exactly 1 Job execution.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the deterministic K8s Job runner contract and `gs://microdrive-dev-spp-tfstate` state path |
| `ssp-cp` | Generates deterministic `operation_id` values and records `k8s_job_name` and state URIs |
| `ssp-workers` | Implements the K8s Job launcher, reattachment logic, ~30s polling, and runner container image |
| `ssp-module-<type>` | Executed inside `tf-op-<operation_id>` Jobs |
| `spp-factory-foundation` | Validates `operation_id` and `state_backend` fields in `gates/schemas/resource-request.schema.json` |

## Open Questions

- [ ] **OQ-1 (Pre-Baked Provider Mirror in Runner Image):** Should the Terraform runner container image (`us-east1-docker.pkg.dev/microdrive-dev/spp/tf-runner:<tag>`) pre-bake the `hashicorp/google`, `hashicorp/aws`, and `hashicorp/azurerm` provider binaries into `/mirror` so `tf-op-<operation_id>` Jobs do not download providers from `registry.terraform.io` on every run?
- [ ] **OQ-2 (Callback vs. 30s Polling Evolution):** At what concurrency threshold (beyond the initial 10–20 provisions/day target) should ~30s K8s Job polling be supplemented by a Kubernetes Job informer/watch stream in `ssp-workers`?
- [ ] **OQ-3 (Payload Delivery to Runner Job):** Should `ssp-workers` pass the rendered Terraform configuration and `Approved` variables to `tf-op-<operation_id>` via an immutable per-operation object in `gs://microdrive-dev-spp-tfstate/runs/<operation_id>/` or via a per-Job Kubernetes `ConfigMap`?

## Related ADRs

- [ADR-CLD-GCP-001: Runtime Platform (GKE `md-dev` and Self-Hosted Temporal)](../per-cloud/gcp/ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md)
- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-AUT-002: Day-2 Operations Scope](ADR-AUT-002-day-2-operations-scope.md)
