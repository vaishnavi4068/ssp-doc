# `ssp-doc` — Prerequisite & Architecture ADRs for the Self-Service Provisioning Platform (SPP)

This repository (`ssp-doc`) is the **source of truth for all prerequisite and cross-cutting Architecture Decision Records (ADRs)** for the **Self-Service Provisioning Platform (SPP)**—a clean-slate, self-service infrastructure provisioning control plane (internal developer portal) replacing legacy "taxi" on **Google Cloud Platform (GCP)**.

SPP is built, verified, and governed by an **AI Software Factory ("Dark Factory")** hosted in [`github.com/vaishnavi4068/spp-factory-foundation`](https://github.com/vaishnavi4068/spp-factory-foundation). The software factory consumes ADRs as its **only input**: humans author, review, and sign off ADRs here (and per-service ADRs in `ssp-cp`), and the factory's unified coding agent translates those ADRs into schemas, OPA/Rego policies, Terraform modules, Python FastAPI control-plane code, Temporal workflows, and React UI catalog templates.

> **Scope Boundary:** This repository contains **only** architecture decision records (`adr/`), the canonical ADR template (`templates/adr-template.md`), repository governance (`CODEOWNERS`), and the multi-repo topology map (`docs/repo-map.md`). It contains **no** runtime application code and **no** infrastructure deployment manifests.

---

## 1. How ADRs Flow into the AI Software Factory (`spp-factory-foundation`)

```text
+-----------------------------------------------------------------------------+
| 1. Human Intent & ADR Authoring (`ssp-doc` & `ssp-cp`)                      |
|    - Prerequisite & architecture ADRs authored in `ssp-doc/adr/`            |
|    - Per-service/component ADRs (GCS, Spanner, VM, API, DB) in `ssp-cp`     |
|    - Reviewed & approved by CODEOWNERS:                                     |
|      Architect: Manoj | Approvers: Dwayne, Norm | Domain Owners             |
+--------------------------------------+--------------------------------------+
                                       |
                                       v
+-----------------------------------------------------------------------------+
| 2. Temporal Assembly Line (`spp-factory-foundation` in GKE `md-dev`)        |
|    - Orchestrated by `WorkItemWorkflow` in Temporal namespace `factory`     |
|    - Each station launches a deterministic sandboxed Kubernetes Job         |
|      (`factory-wi-<work_item_id>-<station>[-attempt]`) in K8s ns `spp-factory`|
|    - Runs `@google/gemini-cli` on Vertex AI (`gemini-2.5-pro`) via          |
|      GKE Workload Identity (`factory-agent` -> `spp-factory-agent`, no keys)|
+--------------------------------------+--------------------------------------+
                                       |
                                       v
+-----------------------------------------------------------------------------+
| 3. Single Unified Agent Dynamically Loads 10 Role Skills (`agents/skills/`) |
|    1. `requirements-impact`    (Station 1: `impact`)                        |
|    2. `change-plan`            (Station 2: `plan`)                          |
|    3. `iac-module`             (Station 3: `build` — Terraform modules)     |
|    4. `control-plane`          (Station 3: `build` — FastAPI & Temporal)    |
|    5. `portal-and-catalog`     (Station 3: `build` — React & templates)     |
|    6. `policy-and-compliance`  (Station 3: `build` — OPA/Rego & schemas)    |
|    7. `validation`             (Station 4: `gate` — 7-stage CI gate,        |
|                                 max 3 rework retries before `BLOCKED`)      |
|    8. `change-review`          (Station 5: `review` — pre-human audit)      |
|    9. `drift-and-reconciliation` (Station 8: `reconcile` — Day-2 drift)     |
|   10. `standards-feedback`     (Continuous learning back into ADRs/gates)   |
+--------------------------------------+--------------------------------------+
                                       |
                                       v
+-----------------------------------------------------------------------------+
| 4. Verified Pull Requests Opened Against Product Repositories               |
|    - `ssp-cp`           (Python FastAPI control plane, DB migrations, OPA)  |
|    - `ssp-workers`      (Python Temporal workflows & K8s Job launcher)      |
|    - `ssp-module-<type>`(Terraform module + Rego policy per resource type)  |
|    - `ssp-ui`           (React portal + chat, built in Phase 5)             |
+-----------------------------------------------------------------------------+
```

---

## 2. Repository Layout

```text
.
├── README.md                                                          # Purpose & ADR-to-Factory flow (this file)
├── CODEOWNERS                                                         # Architect: manoj; Approvers: dwayne, norm
├── templates/
│   └── adr-template.md                                                # Standard ADR template (status, owner, signers, context, decision, consequences, acceptance criteria, affected repos, open questions)
├── docs/
│   └── repo-map.md                                                    # Product repo map: ssp-doc, ssp-cp, ssp-workers, ssp-ui, ssp-module-<type>
└── adr/                                                               # Organised by the 5 ADR levels used in spp-factory-foundation
    ├── INDEX.md                                                       # Master catalog of all prerequisite ADRs
    ├── OWNERSHIP_MATRIX.md                                            # Stakeholder ownership & sign-off matrix
    ├── global/                                                        # Level 1: Platform-wide invariants
    │   ├── ADR-GLB-001-global-architecture-overview.md
    │   ├── ADR-GLB-002-languages-and-technology-stack.md
    │   ├── ADR-GLB-003-four-state-model.md
    │   ├── ADR-GLB-004-data-model-and-database.md
    │   ├── ADR-GLB-005-identity-and-authentication.md
    │   ├── ADR-GLB-006-naming-and-labeling-conventions.md
    │   └── ADR-GLB-007-governance-gates-and-policy-rego.md
    ├── business-process/                                              # Level 2: Governance, ITSM/CMDB, ownership, build order
    │   ├── ADR-BP-001-ownership-map-and-governance.md
    │   └── ADR-BP-002-build-order-and-phasing.md
    ├── endpoint-service/                                              # Level 3: Per-service / vertical slice specifications
    │   └── ADR-SVC-001-first-vertical-slice-gcs-bucket.md
    ├── per-cloud/                                                     # Level 4: Cloud-specific runtime & target architectures (extensible per cloud)
    │   └── gcp/
    │       └── ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md
    └── automation/                                                    # Level 5: Runner execution, Day-2 ops, factory flow
        ├── ADR-AUT-001-terraform-execution-k8s-job.md
        ├── ADR-AUT-002-day-2-operations-scope.md
        └── ADR-AUT-003-software-factory-adr-flow.md
```

*(Note: Legacy v0.1 exploratory directories `00-constitution/` through `90-tasks/` from the initial repo bootstrap remain in the tree for historical reference; the canonical factory-aligned structure is `adr/`, `templates/adr-template.md`, `docs/repo-map.md`, and `CODEOWNERS`.)*

---

## 3. Five ADR Levels (Aligned with `spp-factory-foundation`)

| Level | Folder | ID Pattern | What Belongs Here |
| :--- | :--- | :--- | :--- |
| **1. Global** | [`adr/global/`](adr/global/) | `ADR-GLB-NNN` | Architecture overview, language stack (Python FastAPI + Temporal workers, React UI), 4-state model (`Requested`/`Approved` in Postgres, `Expected`/`Observed` in GCS), relational data model on dedicated AlloyDB for PostgreSQL (`spp_platform`), Workload Identity & auth, naming/labeling conventions, and OPA/Rego governance gates |
| **2. Business Process** | [`adr/business-process/`](adr/business-process/) | `ADR-BP-NNN` | Ownership map (SPP team for `microdrive-dev` SAs, Ken O'Connor, Hurley, Raju's team, Allen, Karen, Norm, Manoj, Dwayne), ServiceNow/CMDB integration, APM ID tiering, persona permissions, and the 6-phase product build order |
| **3. Endpoint / Service** | [`adr/endpoint-service/`](adr/endpoint-service/) | `ADR-SVC-NNN` | Cross-cutting vertical slice specifications (first vertical slice = GCS bucket end-to-end with no UI); detailed per-service ADRs for GCS, Spanner, VM, API, and DB migrations live in `ssp-cp` |
| **4. Per Cloud** | [`adr/per-cloud/gcp/`](adr/per-cloud/gcp/) | `ADR-CLD-GCP-NNN` | GCP runtime platform (`md-dev`, dedicated tainted `spp-pool`, K8s namespaces `spp-temporal`/`spp-factory`/`spp-platform`, self-hosted Temporal with Postgres, Temporal namespaces `factory` and `platform`) and GCP 2.0 target architecture |
| **5. Automation** | [`adr/automation/`](adr/automation/) | `ADR-AUT-NNN` | Terraform execution (1 K8s Job per run in `spp-platform`, state in `gs://microdrive-dev-spp-tfstate`), Day-2 operations scope (update, resize, upgrade, drift detection, rollback, decommission, cost), and software factory ADR flow |

---

## 4. Product Repository Map Summary

See **[`docs/repo-map.md`](docs/repo-map.md)** for full details:

- **`ssp-doc`** (this repo): Prerequisite and cross-cutting architecture ADRs across the 5 ADR levels.
- **`ssp-cp`**: Control plane runtime code (Python FastAPI, local auth now / SSO later, PostgreSQL models & Alembic DB migrations, `Requested`/`Approved` state management, OPA policy evaluation) **plus** per-service/component ADRs for **GCS**, **Spanner**, **VM**, **API**, and **DB migrations**.
- **`ssp-workers`**: Python Temporal workflows and activities (on Temporal namespace `platform`) for resource creation, post-build bootstrap, and Day-2 operations, plus the deterministic Kubernetes Job Terraform runner launcher (`tf-op-<operation_id>` in `spp-platform`).
- **`ssp-ui`**: React + TypeScript self-service portal and embedded chat assistant (built in Phase 5 after GCS end-to-end and Day-2 are proven).
- **`ssp-module-<type>`**: One repository per Terraform resource module + Rego policy bundle (e.g., existing [`ssp-module-spanner`](https://github.com/vaishnavi4068/ssp-module-spanner) and `ssp-module-gcs`).
