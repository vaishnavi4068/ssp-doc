# ADR-CLD-GCP-001: Runtime Platform (GKE `md-dev`, Tainted `spp-pool`, Namespaces, and Self-Hosted Temporal)

- **ADR ID:** ADR-CLD-GCP-001
- **Level:** per-cloud (gcp)
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-cloud-gcp@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the GCP runtime platform architecture in the **non-prod** `microdrive-dev` environment hosting both the AI Software Factory (`spp-factory-foundation`) and the SPP Control Plane (`ssp-cp`, `ssp-workers`, `ssp-ui`), as well as the GCP 2.0 host-project/service-project target model.

## Context

In the design discussion (`uploads/design-digest.md`), stakeholder clarifications, and the live deployment of `spp-factory-foundation` (`docs/factory/runbook.md`, `ADR-AUT-004`, `ADR-AUT-005`):

1. **GCP as Control Plane and Target Cloud (`microdrive-dev` is NON-PROD):** The team chose **GCP** (`microdrive-dev`, which is a **non-prod** environment) for the control plane, dedicated **AlloyDB for PostgreSQL** product database (`spp_platform`), self-hosted Temporal, Kubernetes Job Terraform runners, and 2.0 target workloads.
2. **Self-Hosted Temporal Instead of Shared DevX Temporal:** Although Mitch had negotiated access to DevX's shared Temporal instance, the team decided to **run their own dedicated self-hosted Temporal cluster** inside their own GKE environment to preserve operational isolation, control worker/runner networking, and keep the new project low-profile.
3. **Runtime Cluster, Node & Database Isolation (`md-dev` in Non-Prod `microdrive-dev`):**
   - **GCP Project, Environment & Region:** `microdrive-dev` (**non-prod**, `us-east1`).
   - **GKE Cluster:** `md-dev` (private nodes).
   - **Dedicated Tainted Node Pool (`spp-pool`):** All SPP and factory workloads schedule onto `spp-pool` using `nodeSelector: workload=spp` and toleration `dedicated=spp:NoSchedule` so SPP workloads never contend with or spill onto non-SPP cluster nodes.
   - **Three Kubernetes Namespaces & Database Separation:**
     1. `spp-temporal`: Hosts the self-hosted Temporal 1.32 server (`temporal-frontend.spp-temporal.svc.cluster.local:7233`) backed by its in-cluster PostgreSQL instance.
     2. `spp-factory`: Hosts the AI Software Factory (`factory-console`, `factory-api`, `factory-worker`, sandboxed `factory-wi-<id>-<station>` coding-agent Jobs, and the factory's own in-cluster PostgreSQL, which stays as-is).
     3. `spp-platform`: Hosts the SPP runtime product (`ssp-cp`, `ssp-workers`, `ssp-ui`, and deterministic `tf-op-<operation_id>` Terraform runner Kubernetes Jobs). `ssp-cp` FastAPI is exposed directly via GKE Ingress / LoadBalancer in `spp-platform` (no external API gateway) and connects over private IP / Private Services Access (PSA) to a **dedicated AlloyDB for PostgreSQL cluster/instance** (`spp_platform` database in `microdrive-dev`, `ADR-GLB-004`)—not Cloud SQL, not in-cluster Postgres on `md-dev`, and not a StatefulSet.
   - **Two Isolated Temporal Namespaces:**
     1. `factory` (task queue `factory`): Used exclusively by `spp-factory` (`factory-api` and `factory-worker`) to orchestrate `WorkItemWorkflow` across the 8 factory stations.
     2. `platform` (task queue `platform`): Used exclusively by `ssp-platform` (`ssp-cp` and `ssp-workers`) to orchestrate runtime resource provisioning (`Approved -> Expected -> Observed`), post-build bootstrap, and Day-2 workflows.

## Decision

1. **GKE Runtime Topology (`microdrive-dev` Non-Prod / `md-dev`):**
   - **Cluster & Environment:** GKE cluster `md-dev` in **non-prod** project `microdrive-dev` (`us-east1`).
   - **Node Pool Placement:** Every Deployment, StatefulSet, and Kubernetes Job in `spp-temporal`, `spp-factory`, and `spp-platform` MUST specify:
     - `nodeSelector: { "workload": "spp" }`
     - `tolerations: [{ "key": "dedicated", "operator": "Equal", "value": "spp", "effect": "NoSchedule" }]`
   - **Artifact Registry:** Container images are stored in `us-east1-docker.pkg.dev/microdrive-dev/spp/<image>:<tag>`.
   - **Direct GKE Ingress / LoadBalancer Exposure:** SPP APIs (`ssp-cp` FastAPI) and UI (`ssp-ui`) are deployed directly in `spp-platform` on GKE `md-dev` and exposed via GKE Ingress / LoadBalancer without any external API gateway dependency.
2. **Kubernetes Namespace & Network Isolation:**
   - `spp-temporal`: Self-hosted Temporal server (`temporal-frontend.spp-temporal.svc.cluster.local:7233`) + Temporal PostgreSQL persistence. Allows gRPC ingress on port `7233` from `spp-factory` and `spp-platform`.
   - `spp-factory`: Dark Factory console, API, worker, and coding-agent Jobs. Enforces Kubernetes `NetworkPolicy` default-deny ingress and explicitly blocks all direct pod-to-pod traffic between `spp-factory` and `spp-platform`.
   - `spp-platform`: SPP Control Plane API (`ssp-cp`, connected via private IP/PSA and Workload Identity IAM auth to the dedicated AlloyDB for PostgreSQL `spp_platform` database in `microdrive-dev`), SPP Temporal workers (`ssp-workers`), SPP Portal (`ssp-ui`), and per-run Terraform Kubernetes Jobs (`tf-op-<operation_id>`, running under `<runner-sa>@microdrive-dev.iam.gserviceaccount.com` provided by the SPP team).
3. **Temporal Namespace Isolation:**
   - Temporal server in `spp-temporal` hosts two logical namespaces:
     - `factory` — consumed only by workloads in K8s namespace `spp-factory`.
     - `platform` — consumed only by workloads in K8s namespace `spp-platform`.
4. **GCP 2.0 Target Cloud Architecture:**
   - Target GCP workloads follow the **2.0 folder and host-project/service-project layout** (one `apm_id` per service project) in approved region **`us-east1` only** (`ADR-GLB-007`).
   - Each GCP service project has one dedicated provisioning service account impersonated by `<runner-sa>@microdrive-dev.iam.gserviceaccount.com` (`ADR-GLB-005`) and one Terraform state file per project (`expected/<project-id>/terraform.tfstate` and `observed/<project-id>/terraform.tfstate`).
   - Only BigQuery datasets (never individual BigQuery tables) are managed in Terraform state.

## Requirements

- **REQ-1 (MUST):** All pods and Kubernetes Jobs deployed to `spp-temporal`, `spp-factory`, and `spp-platform` on GKE cluster `md-dev` MUST include `nodeSelector: workload=spp` and toleration `dedicated=spp:NoSchedule` targeting node pool `spp-pool`.
- **REQ-2 (MUST):** SPP MUST use the self-hosted Temporal cluster in `spp-temporal` (`temporal-frontend.spp-temporal.svc.cluster.local:7233`) backed by PostgreSQL, and MUST NOT connect to the shared DevX Temporal instance.
- **REQ-3 (MUST):** Factory workflows (`spp-factory`) MUST execute in the `factory` Temporal namespace, and SPP runtime provisioning/Day-2 workflows (`ssp-platform`) MUST execute in the `platform` Temporal namespace.
- **REQ-4 (MUST):** Kubernetes `NetworkPolicy` resources MUST isolate `spp-factory` from `spp-platform` so coding-agent Jobs cannot reach runtime control-plane pods or runner Jobs.
- **REQ-5 (MUST):** All container images for `ssp-cp`, `ssp-workers`, and `ssp-ui` MUST run as non-root users with explicit CPU and memory requests/limits and authenticate to GCP via Workload Identity (`microdrive-dev.svc.id.goog`).
- **REQ-6 (MUST):** `ssp-cp` FastAPI endpoints MUST be deployed directly in `spp-platform` on GKE `md-dev` and exposed via GKE Ingress / LoadBalancer.

## Guardrails

- **GR-1:** Never schedule SPP or factory pods onto default GKE node pools; always target `spp-pool` (`workload=spp` / `dedicated=spp:NoSchedule`).
- **GR-2:** Never mix factory work-item workflows and runtime infrastructure provisioning workflows in the same Temporal namespace.
- **GR-3:** Never use the shared DevX Temporal cluster.

## Consequences

### Positive

- Complete workload, network, and identity isolation between the AI Software Factory (`spp-factory`) and the runtime provisioning control plane (`spp-platform`) while sharing the physical GKE `spp-pool` nodes and `spp-temporal` service.
- Direct GKE Ingress / LoadBalancer exposure in `spp-platform` and SPP-team-managed service accounts in `microdrive-dev` eliminate external gateway and external SA-provisioning blockers.

### Negative / Trade-offs

- The platform team owns operational health, backups, and upgrades of the self-hosted Temporal instance in `spp-temporal` and the GKE Ingress/LB configuration in `spp-platform`.

## Acceptance Criteria

- [ ] Helm charts / Kubernetes manifests for `ssp-cp`, `ssp-workers`, and `tf-op-<operation_id>` Jobs target namespace `spp-platform` with `nodeSelector: workload=spp` and toleration `dedicated=spp:NoSchedule`.
- [ ] Temporal namespace `platform` is registered on `temporal-frontend.spp-temporal.svc.cluster.local:7233` alongside `factory`.
- [ ] `NetworkPolicy` manifests in `spp-platform` and `spp-factory` deny cross-namespace traffic between `spp-factory` and `spp-platform`.

## Success Criteria

- **SC-1:**
  - **Given** a deployment of `ssp-cp` and `ssp-workers` to namespace `spp-platform` on GKE cluster `md-dev`
  - **When** the pods are scheduled by Kubernetes
  - **Then** all pods land exclusively on `spp-pool` nodes carrying label `workload=spp` and taint `dedicated=spp:NoSchedule`, and `ssp-workers` connects to Temporal namespace `platform` at `temporal-frontend.spp-temporal.svc.cluster.local:7233`.
- **SC-2:**
  - **Given** a pod running in namespace `spp-factory`
  - **When** it attempts to open a TCP connection to a service or pod in `spp-platform`
  - **Then** the connection is dropped by Kubernetes `NetworkPolicy`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the GKE `md-dev` non-prod runtime topology, namespaces, and Temporal architecture |
| `ssp-cp` | Deploys to K8s namespace `spp-platform` on `spp-pool` (exposed via GKE Ingress/LB); starts workflows in Temporal namespace `platform` |
| `ssp-workers` | Deploys to K8s namespace `spp-platform` on `spp-pool`; polls Temporal namespace `platform`; spawns Jobs in `spp-platform` |
| `ssp-ui` | Deploys to K8s namespace `spp-platform` on `spp-pool` |
| `spp-factory-foundation` | Runs in K8s namespace `spp-factory` on `spp-pool`; polls Temporal namespace `factory` |

## Open Questions

- [x] **OQ-1 (Environment Classification & Runner SA Ownership in `microdrive-dev` — RESOLVED 2026-10-21):** *Resolved:* `microdrive-dev` (`md-dev`) is a **non-prod** environment, and the **SPP team** provides and owns the runner GCP Service Account (`<runner-sa>@microdrive-dev.iam.gserviceaccount.com`, `TODO: vaishnavi4068`). Future production cluster provisioning beyond `microdrive-dev` remains with Hurley when SPP moves to prod.
- [ ] **OQ-2 (Temporal PostgreSQL High Availability & Backups):** What is the backup and PITR schedule for the PostgreSQL instance backing self-hosted Temporal in `spp-temporal`?
- [ ] **OQ-3 (VPC & CIDR Allocation with John Simon):** How will `spp-platform` runner pods route to private endpoints in target 2.0 GCP service projects (Shared VPC / Private Service Connect / VPC peering coordinated with John Simon)?

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](../../global/ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-004: Data Model and Database](../../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-AUT-001: Terraform Execution via Kubernetes Jobs](../../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
