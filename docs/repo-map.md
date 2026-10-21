# SPP Repository Map (`docs/repo-map.md`)

This document defines the repository topology for the **Self-Service Provisioning Platform (SPP)**—a self-service infrastructure provisioning control plane (internal developer portal) on GCP—and how each product repository interacts with the **AI Software Factory** (`github.com/vaishnavi4068/spp-factory-foundation`).

---

## 1. Repository Topology Overview

| Repository | Category | Primary Stack | Kubernetes Namespace / Target | Purpose & Scope |
| :--- | :--- | :--- | :--- | :--- |
| **[`ssp-doc`](https://github.com/vaishnavi4068/ssp-doc)** | Architecture & Prerequisite ADRs | Markdown | Consumed by Factory (`spp-factory`) | Source of truth for all prerequisite and cross-cutting architecture ADRs across the 5 ADR levels (`adr/global/`, `adr/business-process/`, `adr/endpoint-service/`, `adr/per-cloud/gcp/`, `adr/automation/`), `templates/adr-template.md`, `CODEOWNERS`, and this repo map. |
| **[`spp-factory-foundation`](https://github.com/vaishnavi4068/spp-factory-foundation)** | AI Software Factory ("Dark Factory") | Python (FastAPI, Temporal SDK), React, Rego, Bash | GKE `md-dev` (`spp-factory` namespace, Temporal `factory` namespace) | The AI software factory that builds and verifies SPP. Houses the 10 agent role skills (`agents/skills/*/SKILL.md`), the 7-stage verification gate (`gates/`), the resource repo skeleton (`templates/resource-repo/`), and the Factory Console. Consumes ADRs as its **only input**. |
| **[`ssp-cp`](https://github.com/vaishnavi4068/ssp-cp)** | Control Plane API, DB & Per-Service ADRs | Python (FastAPI, SQLAlchemy/Alembic), OPA/Rego, AlloyDB for PostgreSQL (`spp_platform`) | GKE `md-dev` (`spp-platform` namespace) + dedicated AlloyDB in `microdrive-dev` | Control plane runtime code (REST API, local auth now / SSO later, synchronous `Requested` persistence, `Approved` state guardrail enrichment, OPA policy evaluation, AlloyDB PostgreSQL schema & Alembic DB migrations) **plus** detailed per-service and component ADRs for GCS, Spanner, VM, API, and DB migrations. |
| **[`ssp-workers`](https://github.com/vaishnavi4068/ssp-workers)** | Orchestration Workers & Runner Launcher | Python (Temporal Python SDK, Kubernetes client), Docker | GKE `md-dev` (`spp-platform` namespace, Temporal `platform` namespace) | Temporal workflows and activities for create (`Approved -> Expected -> Observed`), post-build bootstrap, and Day-2 operations (update, resize, upgrade, drift detection, rollback, decommission, cost), plus the Terraform runner launcher that spawns one deterministic Kubernetes Job (`tf-op-<operation_id>`) per run in `spp-platform`. |
| **`ssp-ui`** *(planned)* | Self-Service Portal & Chat UI | React, TypeScript, Vite, Tailwind CSS | GKE `md-dev` (`spp-platform` namespace) | User-facing internal developer portal and embedded conversational chat assistant (built in Phase 5 after GCS end-to-end and Day-2). Renders service catalog forms dynamically from templates/schemas and shows equivalent Terraform/CLI previews without redeploying the portal when new resource types are added. |
| **`ssp-module-<type>`** *(e.g. [`ssp-module-spanner`](https://github.com/vaishnavi4068/ssp-module-spanner), `ssp-module-gcs`)* | Per-Resource Terraform Module & Policy Bundle | Terraform (`>= 1.10`), OPA/Rego, JSON | Executed by runner Jobs in `spp-platform`; state in `gs://microdrive-dev-spp-tfstate` (and per-LOB buckets) | One repository per GCP resource type (scaling toward ~500 repos). Contains the Terraform module (`module/`), per-resource Rego policies and unit tests (`policies/`), `requested.json` and `approved.json` payloads (`examples/`), and credential-free `terraform test` suites (`tests/`). |

---

## 2. Detailed Repository Responsibilities

### 2.1 `ssp-doc` — Prerequisite & Architecture ADRs (This Repository)

- **Role:** Canonical upstream knowledge base for platform-wide architecture, runtime topology, language stack, 4-state model, data model, identity/auth, Terraform execution, naming/labeling, Rego governance gates, Day-2 scope, ownership map, first vertical slice, and build order.
- **Structure:**
  - `adr/global/` — Platform-wide invariants (`ADR-GLB-001` .. `ADR-GLB-007`)
  - `adr/business-process/` — Ownership map, ITSM/CMDB governance, and build order (`ADR-BP-001` .. `ADR-BP-002`)
  - `adr/endpoint-service/` — Cross-cutting vertical slice specifications (`ADR-SVC-001` for GCS bucket end-to-end without UI)
  - `adr/per-cloud/gcp/` — Runtime platform on GCP (`md-dev`) and GCP 2.0 target architecture (`ADR-CLD-GCP-001`; `adr/per-cloud/` remains extensible for future clouds)
  - `adr/automation/` — Deterministic Kubernetes Job Terraform execution, Day-2 operations scope, and factory ADR flow (`ADR-AUT-001` .. `ADR-AUT-003`)
  - `templates/adr-template.md` — Standardized ADR template required for all new decisions
  - `CODEOWNERS` — Review ownership (`manoj` as Architect; `dwayne` and `norm` as Approvers)
- **What Does NOT Live Here:** No runtime application code, no Terraform infrastructure code, and no secrets.

### 2.2 `ssp-cp` — Control Plane Code & Per-Service / Component ADRs

- **Role:** Houses the SPP Control Plane API service and database migrations, alongside the detailed per-service and component-level ADRs that drive `ssp-cp` implementation.
- **Runtime Responsibilities:**
  - **FastAPI Backend:** Deployed directly in `spp-platform` on GKE `md-dev` and exposed via GKE Ingress / LoadBalancer; exposes REST endpoints for submitting provisioning orders, querying `Requested`, `Approved`, `Expected`, and `Observed` states, triggering Day-2 operations, and managing authentication (local Argon2id login with Secret Manager bootstrap now; corporate SSO later).
  - **Synchronous `Requested` Persistence:** Writes raw user request metadata directly to the dedicated **AlloyDB for PostgreSQL** instance (`spp_platform` database in `microdrive-dev`, connected over private IP/PSA from `md-dev`) without invoking Temporal (`ADR-GLB-003`, `ADR-GLB-004`).
  - **`Approved` State Enrichment & Policy Engine:** Applies mandatory guardrails (CMEK, `>= 90` days retention, Raju security baseline, APM ID tier defaults, standard naming, required labels, `operations_gate`) and evaluates clean-slate OPA/Rego policies (`ADR-GLB-007`) before dispatching a workflow to Temporal (`platform` namespace).
  - **Database Schema & Migrations:** Owns PostgreSQL DDL and Alembic migrations targeting the dedicated AlloyDB `spp_platform` database for `Requested` and `Approved` state tables, audit logs, users/sessions, and operation tracking (`ADR-GLB-004`). (The factory's own in-cluster Postgres in `spp-factory` stays as-is.)
- **ADR Responsibilities Inside `ssp-cp`:**
  - Per-service endpoint ADRs for **GCS**, **Spanner**, and **VM**
  - Component ADRs for the **Control Plane API** contract and **Database Migrations**

### 2.3 `ssp-workers` — Temporal Workflows, Activities & Terraform Runner Launcher

- **Role:** Asynchronous execution engine for SPP running in the `spp-platform` GKE namespace and polling the `platform` Temporal namespace on `temporal-frontend.spp-temporal.svc.cluster.local:7233`.
- **Runtime Responsibilities:**
  - **Create Workflows & Activities:** Orchestrates post-approval provisioning (`Approved -> Expected -> Observed`) and post-build bootstrap steps (with a no-op interface placeholder for future post-MVP ServiceNow/CMDB integration).
  - **Day-2 Operations Workflows:** Orchestrates resource **update**, **resize**, **upgrade**, **drift detection**, **rollback**, **decommission**, and **cost** attribution/reporting (`ADR-AUT-002`).
  - **Terraform Runner Launcher:** Never executes `terraform` inside the long-lived worker process. Instead, launches **one isolated Kubernetes Job per run** (`tf-op-<operation_id>`) in `spp-platform` (on the tainted `spp-pool` node pool), polls status every ~30s, reattaches deterministically on retry, and writes `Expected` and `Observed` state to `gs://microdrive-dev-spp-tfstate` (`ADR-AUT-001`).

### 2.4 `ssp-ui` — Self-Service Portal & Chat Interface (Built Later)

- **Role:** User-facing internal developer portal and conversational provisioning assistant, scheduled for Phase 5 of the build order (`ADR-BP-002`) after GCS create and Day-2 workflows are proven end-to-end via API.
- **Runtime Responsibilities:**
  - **React Storefront:** Search at top-center, frequently used service catalog, GCP project selector, order status tracker across the 4 states, and bottom-right embedded chat.
  - **Template-Driven Rendering:** Renders request forms dynamically from ADR-derived schemas/templates (Handlebars / micro-frontend pattern) so adding a new `ssp-module-<type>` never requires redeploying `ssp-ui`.
  - **"Show the Code" Preview:** Displays the equivalent Terraform HCL and `gcloud` CLI command for every request.
  - **Persona-Based UI Controls:** Enforces field visibility and Day-2 action permissions (`developer` vs. `operations` vs. `security`).

### 2.5 `ssp-module-<type>` — Per-Resource Terraform Modules & Policies

- **Role:** Standardized, self-contained repository for each GCP resource type (derived from `spp-factory-foundation/templates/resource-repo/`), scaling toward ~500 repositories.
- **Existing & Planned Repositories:**
  - `ssp-module-spanner` (`github.com/vaishnavi4068/ssp-module-spanner` — existing repository)
  - `ssp-module-gcs` (or `ssp-module-gcs-bucket` — first end-to-end vertical slice, `ADR-SVC-001`)
  - Future modules: `ssp-module-cloudsql` / Postgres, `ssp-module-gce-vm`, `ssp-module-bigquery-dataset`, etc.
- **Standard Layout per Module Repo:**
  - `ADR.md` / `SKILL.md` — Links to the governing endpoint ADR and local agent instructions
  - `module/` — `versions.tf` (Terraform `>= 1.10`), `variables.tf`, `main.tf`, `outputs.tf` (must output immutable CSP `cloud_resource_id`)
  - `policies/` — Service-specific OPA/Rego rules and `*_test.rego` unit tests (may tighten, never weaken, global policies)
  - `examples/` — `requested.json` and `approved.json` payloads (zero secrets)
  - `tests/` — Offline `terraform test` suites using `mock_provider "google"` (zero cloud credentials required in CI)
  - `.github/workflows/gate.yml` — Calls the reusable 7-stage factory gate in `spp-factory-foundation`

---

## 3. How ADRs Flow Across Repositories Through the Factory

```text
+-----------------------------------------------------------------------+
| 1. Author & Review ADR                                                |
|    - Prerequisite / Global / Cloud / Automation ADRs in `ssp-doc`     |
|    - Per-service / API / DB ADRs in `ssp-cp`                          |
|    - Reviewed by CODEOWNERS (Architect: Manoj; Approvers: Dwayne, Norm)|
+-----------------------------------+-----------------------------------+
                                    |
                                    v
+-----------------------------------------------------------------------+
| 2. AI Software Factory (`spp-factory-foundation` in `spp-factory` ns) |
|    - Temporal `WorkItemWorkflow` on `factory` namespace               |
|    - Spawns sandboxed K8s Job `factory-wi-<id>-<station>[-attempt]`   |
|    - Runs `@google/gemini-cli` on Vertex AI (Workload Identity)       |
|    - Dynamically loads 10 role skills from `agents/skills/*/SKILL.md`:|
|      impact -> plan -> build -> gate -> review -> approval -> merge   |
+-----------------------------------+-----------------------------------+
                                    |
          +-------------------------+-------------------------+
          |                         |                         |
          v                         v                         v
+-------------------+     +-------------------+     +-------------------+
| `ssp-cp` &        |     | `ssp-module-*`    |     | `ssp-ui`          |
| `ssp-workers`     |     |                   |     | (Phase 5+)        |
| FastAPI, DB DDL,  |     | Terraform module, |     | React catalog &   |
| Temporal workflows|     | Rego policies,    |     | chat metadata     |
| & K8s Job launcher|     | mock_provider test|     |                   |
+-------------------+     +-------------------+     +-------------------+
```

---

## 4. Open Questions on Repository Boundaries

- [ ] **OQ-1:** For the first vertical slice (GCS bucket end-to-end), will the GCS Terraform module live in a dedicated `ssp-module-gcs` repository (matching `ssp-module-spanner`), or initially inside `ssp-cp` / `spp-factory-foundation/templates/resource-repo` before splitting out?
- [ ] **OQ-2:** Should per-service ADRs (GCS, Spanner, VM) authored in `ssp-cp` be mirrored or indexed in `ssp-doc/adr/INDEX.md` so the Factory Console ADR View displays a single unified catalog across both repos?
