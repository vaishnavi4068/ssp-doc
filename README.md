# `ssp-doc` — Prerequisite & Architecture ADRs for the Self-Service Provisioning Platform (SPP)

This repository (`ssp-doc`) is the **source of truth for all prerequisite and cross-cutting Architecture Decision Records (ADRs) and reconstructed four-gate specifications** for the **Self-Service Provisioning Platform (SPP)**—a clean-slate, self-service infrastructure provisioning control plane (internal developer portal) on **Google Cloud Platform (GCP)** (`us-east1`).

SPP is built, verified, and governed by an **AI Software Factory ("Dark Factory")** hosted in [`github.com/vaishnavi4068/spp-factory-foundation`](https://github.com/vaishnavi4068/spp-factory-foundation). The software factory consumes ADRs and `specs/` as its **only input**: humans author, review, and sign off ADRs here, and the factory's unified coding agent translates those ADRs into schemas, OPA/Rego policies (`ssp-module-gcs-bucket`, `ssp-module-spanner`), Terraform modules, Python FastAPI control-plane code and Alembic migrations (`ssp-cp`), Temporal workflows (`ssp-workers`), and React UI catalog templates (`ssp-ui`).

> **Scope Boundary:** This repository contains architecture decision records (`adr/`), reconstructed four-gate specifications (`specs/`), source provenance documentation (`docs/source-provenance.md`), the canonical ADR template (`templates/adr-template.md`), repository governance (`CODEOWNERS`), and the multi-repo topology map (`docs/repo-map.md`). It contains **no** runtime application code and **no** secrets.

---

## 1. How ADRs Flow into the AI Software Factory (`spp-factory-foundation`)

```text
+-----------------------------------------------------------------------------+
| 1. Human Intent & ADR Authoring (`ssp-doc`)                                 |
|    - 18 Prerequisite & architecture ADRs authored in `ssp-doc/adr/`         |
|    - Reconstructed DDL, naming spec & gate examples in `ssp-doc/specs/`     |
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
|    - `ssp-cp`                (FastAPI control plane, AlloyDB Alembic DDL)   |
|    - `ssp-workers`           (Temporal workflows & K8s Job launcher)        |
|    - `ssp-module-gcs-bucket` (GCS bucket Terraform module + Rego policies)  |
|    - `ssp-module-spanner`    (Spanner instance/DB module + Rego policies)   |
|    - `ssp-ui`                (React portal + chat, built in Phase 5)        |
+-----------------------------------------------------------------------------+
```

---

## 2. Repository Layout

```text
.
├── README.md                                                          # Purpose & ADR-to-Factory flow (this file)
├── CODEOWNERS                                                         # Architect: manoj; Approvers: dwayne, norm
├── templates/
│   └── adr-template.md                                                # Standard ADR template
├── docs/
│   ├── repo-map.md                                                    # Product repo map & downstream artifact mapping
│   └── source-provenance.md                                           # Photo-transcription provenance, overrides & source gaps
├── specs/
│   ├── data-model/
│   │   └── spp_state_model.sql                                        # Reconstructed AlloyDB PostgreSQL DDL (schema idp, 18 tables)
│   ├── naming/
│   │   └── naming-spec.json                                           # Reconstructed naming & label normalization spec
│   └── examples/
│       ├── gcs_bucket.gates.json                                      # Reconstructed GCS bucket 4-gate & critical PAP drift walkthrough
│       └── spanner.gates.json                                         # Reconstructed Spanner 4-gate & drift walkthrough
└── adr/                                                               # Organised by the 5 ADR levels used in spp-factory-foundation
    ├── INDEX.md                                                       # Master catalog of all 18 prerequisite ADRs
    ├── OWNERSHIP_MATRIX.md                                            # Stakeholder ownership & sign-off matrix
    ├── global/                                                        # Level 1: Platform-wide invariants
    │   ├── ADR-GLB-001-global-architecture-overview.md
    │   ├── ADR-GLB-002-languages-and-technology-stack.md
    │   ├── ADR-GLB-003-four-state-model.md
    │   ├── ADR-GLB-004-data-model-and-database.md
    │   ├── ADR-GLB-005-identity-and-authentication.md
    │   ├── ADR-GLB-006-naming-and-labeling-conventions.md
    │   ├── ADR-GLB-007-governance-gates-and-policy-rego.md
    │   ├── ADR-GLB-008-label-and-tag-standard.md
    │   └── ADR-GLB-009-resource-kind-registry.md
    ├── business-process/                                              # Level 2: Governance, ownership, build order, approval gates
    │   ├── ADR-BP-001-ownership-map-and-governance.md
    │   ├── ADR-BP-002-build-order-and-phasing.md
    │   └── ADR-BP-003-roles-and-approver-governance.md
    ├── endpoint-service/                                              # Level 3: Per-service / vertical slice specifications
    │   ├── ADR-SVC-001-first-vertical-slice-gcs-bucket.md
    │   └── ADR-SVC-002-spanner-instance-and-database.md
    ├── per-cloud/                                                     # Level 4: Cloud-specific runtime & target architectures
    │   └── gcp/
    │       └── ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md
    └── automation/                                                    # Level 5: Runner execution, Day-2 ops, factory flow
        ├── ADR-AUT-001-terraform-execution-k8s-job.md
        ├── ADR-AUT-002-day-2-operations-scope.md
        └── ADR-AUT-003-software-factory-adr-flow.md
```

---

## 3. Five ADR Levels (Aligned with `spp-factory-foundation`)

| Level | Folder | ID Pattern | What Belongs Here |
| :--- | :--- | :--- | :--- |
| **1. Global** | [`adr/global/`](adr/global/) | `ADR-GLB-NNN` | Architecture overview, language stack, 4-gate state model (`Requested`/`Approved` in AlloyDB Postgres, `Expected`/`Observed` in `gs://microdrive-dev-spp-tfstate`, `<= 2 KB` Observed projections), 18-table `idp` data model on dedicated AlloyDB (`spp_platform`), Workload Identity & auth, naming conventions (`nonprod`/`prod`), OPA/Rego governance gates & invariants (`INV-1..INV-9`), label standard (`LBL-001`/`LBL-002`), and resource kind registry (`idp.resource_kind`) |
| **2. Business Process** | [`adr/business-process/`](adr/business-process/) | `ADR-BP-NNN` | Ownership map, 6-phase product build order, and roles/personas/sequential approval gates (`gcs_bucket_owner`, `spanner_data_owner`, SLA escalation, self-approval denial, mandatory human approval on all deletes) |
| **3. Endpoint / Service** | [`adr/endpoint-service/`](adr/endpoint-service/) | `ADR-SVC-NNN` | Per-kind specifications and guardrail rules for `gcs_bucket` (`ADR-SVC-001`, `GCS-*`) and `spanner_instance` / `spanner_database` (`ADR-SVC-002`, `SPN-*`) |
| **4. Per Cloud** | [`adr/per-cloud/gcp/`](adr/per-cloud/gcp/) | `ADR-CLD-GCP-NNN` | GCP runtime platform (`md-dev`, dedicated tainted `spp-pool`, K8s namespaces `spp-temporal`/`spp-factory`/`spp-platform`, self-hosted Temporal with Postgres, Temporal namespaces `factory` and `platform`) and GCP 2.0 target architecture in `us-east1` |
| **5. Automation** | [`adr/automation/`](adr/automation/) | `ADR-AUT-NNN` | Temporal workflows (`req-*`, `apr-*`, `su-gcp-*`, `drift-*`), deterministic K8s Job Terraform execution (`tf-<phase>-<20hex>` in `spp-platform`, state in `gs://microdrive-dev-spp-tfstate`), Day-2 operations & alert-only drift detection, and software factory ADR flow |

---

## 4. Product Repository Map Summary

See **[`docs/repo-map.md`](docs/repo-map.md)** and **[`docs/source-provenance.md`](docs/source-provenance.md)** for full details:

- **`ssp-doc`** (this repo): Prerequisite and cross-cutting architecture ADRs (`adr/`) and reconstructed four-gate specifications (`specs/`).
- **`ssp-cp`**: Control plane runtime code (Python FastAPI, local auth now / SSO later, AlloyDB PostgreSQL models & **Alembic DB migrations derived from `specs/data-model/spp_state_model.sql`**, `Requested`/`Approved` gate management, OPA policy evaluation, and naming/label validation from `specs/naming/naming-spec.json`).
- **`ssp-workers`**: Python Temporal workflows and activities (on Temporal namespace `platform`) for `RequestWorkflow`, `ApprovalGateWorkflow`, `StateUnitReconcilerWorkflow`, and `DriftSchedule`, plus the deterministic Kubernetes Job Terraform runner launcher (`tf-<phase>-<20hex>` in `spp-platform`).
- **`ssp-module-gcs-bucket`** and **[`ssp-module-spanner`](https://github.com/vaishnavi4068/ssp-module-spanner)**: Per-kind Terraform modules and OPA/Rego policy packages implementing `ADR-SVC-001` (`gcs_bucket`) and `ADR-SVC-002` (`spanner_instance`, `spanner_database`).
- **`ssp-ui`**: React + TypeScript self-service portal and embedded chat assistant (built in Phase 5 after GCS end-to-end and Day-2 are proven).
