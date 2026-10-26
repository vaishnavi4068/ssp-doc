# SPP Repository Map (`docs/repo-map.md`)

This document defines the repository topology for the **Self-Service Provisioning Platform (SPP)**—a self-service infrastructure provisioning control plane (internal developer portal) on GCP—and how each product repository interacts with the **AI Software Factory** (`github.com/vaishnavi4068/spp-factory-foundation`).

---

## 1. Repository Topology Overview

| Repository | Category | Primary Stack | Kubernetes Namespace / Target | Purpose & Scope |
| :--- | :--- | :--- | :--- | :--- |
| **[`ssp-doc`](https://github.com/vaishnavi4068/ssp-doc)** | Architecture ADRs & Reconstructed Specs | Markdown, SQL, JSON | Consumed by Factory (`spp-factory`) | Source of truth for all prerequisite and cross-cutting architecture ADRs across the 5 ADR levels (`adr/global/`, `adr/business-process/`, `adr/endpoint-service/`, `adr/per-cloud/gcp/`, `adr/automation/`), reconstructed specifications (`specs/data-model/spp_state_model.sql`, `specs/naming/naming-spec.json`, `specs/examples/gcs_bucket.gates.json`, `specs/examples/spanner.gates.json`), `docs/source-provenance.md`, `templates/adr-template.md`, `CODEOWNERS`, and this repo map. |
| **[`spp-factory-foundation`](https://github.com/vaishnavi4068/spp-factory-foundation)** | AI Software Factory ("Dark Factory") | Python (FastAPI, Temporal SDK), React, Rego, Bash | SPP GKE cluster (`spp-factory` namespace, Temporal `factory` namespace) | The AI software factory that builds and verifies SPP. Houses the 10 agent role skills (`agents/skills/*/SKILL.md`), the 7-stage verification gate (`gates/`), the resource repo skeleton (`templates/resource-repo/`), and the Factory Console. Consumes ADRs and `specs/` as its **only input**. |
| **[`ssp-cp`](https://github.com/vaishnavi4068/ssp-cp)** | Control Plane API, DB & Per-Service ADRs | Python (FastAPI, SQLAlchemy/Alembic), OPA/Rego, AlloyDB for PostgreSQL (`spp_platform`) | SPP GKE cluster (`spp-platform` namespace) + dedicated AlloyDB in `<spp-factory-host-project-id>` (`us-east1`) | Control plane runtime code (REST API, local auth now / SSO later, `Requested` and `Approved` gate persistence, guardrail enrichment & `guardrail_trace`, OPA policy evaluation, naming/label validation from `specs/naming/naming-spec.json`, and **AlloyDB PostgreSQL schema & Alembic DB migrations derived from `specs/data-model/spp_state_model.sql`**) **plus** detailed component ADRs. |
| **[`ssp-workers`](https://github.com/vaishnavi4068/ssp-workers)** | Orchestration Workers & Runner Launcher | Python (Temporal Python SDK, Kubernetes client), Docker | SPP GKE cluster (`spp-platform` namespace, Temporal `platform` namespace) | Temporal workflows (`RequestWorkflow` `req-<request_id>`, `ApprovalGateWorkflow` `apr-<request_id>`, `StateUnitReconcilerWorkflow` `su-gcp-<project_id>`, `DriftSchedule` `drift-<project_id>`), `pre_apply`/`post_apply` lifecycle tasks, JSON-pointer drift comparer (alert-only), and the Terraform runner launcher that spawns one deterministic Kubernetes Job (`tf-<phase>-<20hex>`) per run in `spp-platform` writing state to `gs://microdrive-dev-spp-tfstate`. |
| **`ssp-ui`** | Self-Service Portal & Chat UI (`https://portal.taxi.growripple.ai`) | React, TypeScript, Vite, Tailwind CSS, nginx | SPP GKE cluster (`spp-platform` namespace) | User-facing internal developer portal (`https://portal.taxi.growripple.ai`, IDP Design Variant 17; see [`experiences/portal-ui/`](../experiences/portal-ui/) and [`ADR-EXP-004`](../adr/experience/ADR-EXP-004-portal-ui-experience.md)) behind an nginx reverse proxy to `spp-cp`. Exposes **GCS Bucket (`gcs_bucket` in `us-east1`) live** and **Cloud Spanner coming soon**. |
| **`ssp-module-<type>`** *(e.g. `ssp-module-gcs-bucket`, [`ssp-module-spanner`](https://github.com/vaishnavi4068/ssp-module-spanner))* | Per-Resource Terraform Module & Policy Bundle | Terraform (`>= 1.10`), OPA/Rego, JSON | Executed by runner Jobs in `spp-platform`; state in `gs://microdrive-dev-spp-tfstate` | One repository per GCP resource kind. Contains the Terraform modules (`modules/bucket` in **`ssp-module-gcs-bucket`**, `modules/instance` and `modules/database` in **`ssp-module-spanner`**), per-kind Rego policies (`idp.gcp.gcs_bucket`, `idp.gcp.spanner_instance`, `idp.gcp.spanner_database`) enforcing `GCS-*` and `SPN-*` guardrails, example gate payloads (`examples/`), and credential-free `terraform test` suites (`tests/`). |

---

## 2. Detailed Repository Responsibilities & Downstream Artifact Mapping

### 2.1 `ssp-doc` — Prerequisite ADRs & Reconstructed Specifications (This Repository)

- **Role:** Canonical upstream knowledge base for platform-wide architecture, runtime topology, language stack, four-gate state model, 18-table `idp` relational data model, identity/auth, Terraform execution, naming (`nonprod`/`prod`) and labeling (`LBL-001`/`LBL-002`) standards, resource kind registry, approval gates, Day-2 alert-only drift scope, and GCS bucket / Cloud Spanner specifications.
- **Structure:**
  - `adr/global/` — Platform-wide invariants (`ADR-GLB-001` .. `ADR-GLB-009`)
  - `adr/business-process/` — Ownership map, build order, and roles/approval gate governance (`ADR-BP-001` .. `ADR-BP-003`)
  - `adr/endpoint-service/` — Endpoint service specifications (`ADR-SVC-001` for `gcs_bucket`; `ADR-SVC-002` for `spanner_instance` and `spanner_database`)
  - `adr/experience/` — Experience line ADRs over `ssp-cp` (`ADR-EXP-001` Agentic Chatbot, `ADR-EXP-002` MCP Server, `ADR-EXP-003` Client SDK, `ADR-EXP-004` Portal UI)
  - `adr/per-cloud/gcp/` — Runtime platform on GCP (`<spp-factory-host-project-id>` / SPP GKE cluster / SPP VPC) and GCP 2.0 target architecture in `us-east1` (`ADR-CLD-GCP-001`)
  - `adr/automation/` — Temporal workflows, deterministic Kubernetes Job Terraform execution, Day-2 alert-only drift & deletion governance, factory ADR flow, and Jev model Agent Harness & deterministic Temporal workflow execution layer (`ADR-AUT-001` .. `ADR-AUT-004`)
  - `experiences/` — Multi-channel experience specifications ([`experiences/README.md`](../experiences/README.md), [`experiences/portal-ui/`](../experiences/portal-ui/), [`experiences/agentic-chat/`](../experiences/agentic-chat/), [`experiences/mcp/`](../experiences/mcp/), [`experiences/sdk/`](../experiences/sdk/)), all sharing the `ssp-cp` API and policy/approval path with zero privileged channels
  - `specs/data-model/spp_state_model.sql` — Reconstructed PostgreSQL DDL for schema `idp` (**becomes versioned Alembic migrations in `ssp-cp` later**)
  - `specs/naming/naming-spec.json` — Reconstructed naming & label normalization spec (`idp-naming` v1.0.0, **consumed by `ssp-cp` and `spp-factory-foundation`**)
  - `specs/examples/gcs_bucket.gates.json` — Reconstructed GCS bucket walkthrough across all four gates and critical PAP drift scenario
  - `specs/examples/spanner.gates.json` — Reconstructed Spanner instance + database walkthrough across all four gates and drift scenario
  - `docs/source-provenance.md` — Provenance of the photo-transcribed design package, applied user overrides, and unverified source gaps
  - `templates/adr-template.md` — Standardized ADR template required for all new decisions
  - `CODEOWNERS` — Review ownership (`manoj` as Architect; `dwayne` and `norm` as Approvers)
- **What Does NOT Live Here:** No runtime application code, no live Terraform deployment state, and no secrets.

### 2.2 `ssp-cp` — Control Plane Code, Alembic Migrations & Component ADRs

- **Role:** Houses the SPP Control Plane API service and database migrations, translating `specs/data-model/spp_state_model.sql` and `specs/naming/naming-spec.json` into executable Python/SQLAlchemy/Alembic code.
- **Runtime Responsibilities:**
  - **FastAPI Backend:** Deployed directly in `spp-platform` on the SPP GKE cluster and exposed via GKE Ingress / LoadBalancer; exposes REST endpoints for submitting requests (`idp.submission`, `idp.request`), querying the four gates (`idp.v_resource_status`, `idp.resource_observed`), recording human approval decisions (`idp.approval_decision`), and managing authentication.
  - **Database Schema & Alembic Migrations (from `specs/data-model/spp_state_model.sql`):** Owns versioned **Alembic** migrations targeting the dedicated **AlloyDB for PostgreSQL** instance (`spp_platform` database, schema `idp`, in `<spp-factory-host-project-id>`, region `us-east1`, connected over private IP/PSA in the SPP VPC) creating all 18 tables, `idp.k8s_job_name`, immutability triggers (`request_guard`, `approval_guard`, `expected_revision_guard`, `gate_event_guard`), `idp.v_resource_status`, and seed rows (`approval_gate_config`, `resource_kind`, `apm_alias`).
  - **Naming, Label & Guardrail Enrichment (from `specs/naming/naming-spec.json`, `ADR-GLB-006..009`):** Enforces `GCS-NAME-*`, `SPN-NAME-*`, `NAM-*`, `LBL-001`/`LBL-002`, and evaluates OPA policies (`requested`, `approved`, `plan`) while recording every mutation in `idp.approval.guardrail_trace`.

### 2.3 `ssp-workers` — Temporal Workflows, Reconciler & Terraform Runner Launcher

- **Role:** Asynchronous execution engine for SPP running in the `spp-platform` GKE namespace and polling the `platform` Temporal namespace on `temporal-frontend.spp-temporal.svc.cluster.local:7233`.
- **Runtime Responsibilities:**
  - **`RequestWorkflow` (`req-<request_id>`) & `ApprovalGateWorkflow` (`apr-<request_id>`):** Orchestrates `REQUESTED -> APPROVED`, sequential human approver chains (`gcs_bucket_owner`, `spanner_data_owner`), SLA timers, follow-up reminders, manager escalation, `self_approval = deny`, and mandatory human approval for all deletes (`ADR-BP-003`).
  - **`StateUnitReconcilerWorkflow` (`su-gcp-<project_id>`):** Serializes all runs for one GCP project via `signal-with-start` (`INV-8`), executes `pre_apply` `idp.lifecycle_task` rows (`PRQ-001..004`), renders create-only (`ifGenerationMatch=0`) `Expected` revisions (`projects/<project_id>/expected/rev-NNNNNN/{terraform.tfvars.json, manifest.json}`) in `gs://microdrive-dev-spp-tfstate`, verifies `INV-4..INV-9`, and captures `<= 2 KB` `Observed` projections (`idp.resource_observed`).
  - **Terraform Runner Launcher:** Spawns **one isolated Kubernetes Job per run** (`tf-<phase>-<first 20 hex of sha256(operation_id)>`) in namespace `spp-platform` (on the tainted `spp-pool` node pool), reattaches on `AlreadyExists`, and writes state to the single bucket `gs://microdrive-dev-spp-tfstate` (`ADR-AUT-001`).
  - **Scheduled Drift Scans (`drift-<project_id>`):** Runs `tf-refresh-plan-<20hex>`, compares `Expected` vs. `Observed` by JSON pointer minus `resource_kind.drift_ignore_paths`, and records alert-only findings in `idp.drift_finding` (`ADR-AUT-002`).

### 2.4 `ssp-ui` — Self-Service Portal & Chat Interface (`https://portal.taxi.growripple.ai`)

- **Role:** User-facing internal developer portal (`https://portal.taxi.growripple.ai`, IDP Design Variant 17, React + TypeScript + Vite + Tailwind CSS served via an nginx reverse proxy to `spp-cp`; documented in [`experiences/portal-ui/`](../experiences/portal-ui/) and [`ADR-EXP-004`](../adr/experience/ADR-EXP-004-portal-ui-experience.md)), with **GCS Bucket (`gcs_bucket`, `us-east1`) live** and **Cloud Spanner (`spanner_instance`, `spanner_database`) coming soon**.

### 2.5 `ssp-module-gcs-bucket` and `ssp-module-spanner` — Per-Kind Terraform Modules & Rego Policies

- **Role:** Standardized, self-contained repositories where the Terraform HCL modules and Rego policy packages defined in `ADR-SVC-001` and `ADR-SVC-002` are implemented:
  - **`ssp-module-gcs-bucket` (`ssp-module-gcs`):** Implements the `gcs_bucket` Terraform module (`modules/bucket`, `tfvars_collection = "gcs_buckets"`) and Rego policy package (`idp.gcp.gcs_bucket`) enforcing `GCS-UBLA-001`, `GCS-PAP-001`, `GCS-ENC-001/002` (`us-east1`), `GCS-RET-001`, `GCS-SDP-001`, `GCS-DEL-001`, `LBL-001/002`, and authoritative per-role `iam_bindings` (`ADR-SVC-001`).
  - **[`ssp-module-spanner`](https://github.com/vaishnavi4068/ssp-module-spanner):** Implements the `spanner_instance` (`modules/instance`, `tfvars_collection = "spanner_instances"`) and `spanner_database` (`modules/database`, `tfvars_collection = "spanner_databases"`) Terraform modules and Rego policy packages (`idp.gcp.spanner_instance`, `idp.gcp.spanner_database`) enforcing `SPN-CFG-001` (`regional-us-east1`), `SPN-EDT-001/002`, `SPN-BKP-001/002`, `SPN-DEL-001/002`, `SPN-ENC-001` (`us-east1`), and `SPN-IAM-001` (`ADR-SVC-002`).

---

## 3. How ADRs and Specs Flow Across Repositories Through the Factory

```text
+-----------------------------------------------------------------------+
| 1. Author & Review ADRs + Specs in `ssp-doc`                          |
|    - 18 ADRs across `adr/{global,business-process,endpoint-service,   |
|      per-cloud/gcp,automation}/`                                      |
|    - Reconstructed DDL (`specs/data-model/spp_state_model.sql`)       |
|    - Naming & Label Spec (`specs/naming/naming-spec.json`)            |
|    - Gate Walkthrough (`specs/examples/spanner.gates.json`)           |
+-----------------------------------+-----------------------------------+
                                    |
                                    v
+-----------------------------------------------------------------------+
| 2. AI Software Factory (`spp-factory-foundation` in `spp-factory` ns) |
|    - Temporal `WorkItemWorkflow` on `factory` namespace               |
|    - Dynamically loads 10 role skills from `agents/skills/*/SKILL.md` |
+-----------------------------------+-----------------------------------+
                                    |
          +-------------------------+-------------------------+
          |                         |                         |
          v                         v                         v
+-------------------+     +------------------------+  +-------------------+
| `ssp-cp` &        |     | `ssp-module-gcs-bucket`|  | `ssp-ui`          |
| `ssp-workers`     |     | & `ssp-module-spanner` |  | (Phase 5+)        |
| - DDL -> Alembic  |     | - Rego (`GCS-*`/`SPN-*`|  | React catalog &   |
|   migrations      |     |   / `LBL-*`)           |  | chat metadata     |
| - FastAPI & OPA   |     | - Terraform modules    |  |                   |
| - Reconciler &    |     | - `mock_provider` test |  |                   |
|   K8s Job runner  |     |                        |  |                   |
+-------------------+     +------------------------+  +-------------------+
```

---

## 4. Resolved Repository Boundary Decisions

- [x] **OQ-1 (GCS & Spanner Module Locations — RESOLVED 2026-10-21):** *Resolved:* Per-kind Rego policies (`idp.gcp.gcs_bucket`, `idp.gcp.spanner_instance`, `idp.gcp.spanner_database`) and Terraform modules live in `ssp-module-gcs-bucket` (`ssp-module-gcs`) and `ssp-module-spanner`, while `ssp-workers` composes one project-level `terraform.tfvars.json` (`gcs_buckets`, `spanner_instances`, `spanner_databases`) per state unit (`ADR-GLB-003`, `ADR-GLB-009`).
- [x] **OQ-2 (DDL to Alembic Migration Ownership — RESOLVED 2026-10-21):** *Resolved:* `specs/data-model/spp_state_model.sql` in `ssp-doc` is the upstream specification and becomes versioned **Alembic** database migrations in `ssp-cp` targeting AlloyDB `spp_platform` (`ADR-GLB-004`).
