# SPP Prerequisite & Architecture Decision Records (`adr/INDEX.md`)

This directory is the canonical source of truth for all prerequisite and cross-cutting Architecture Decision Records (ADRs) for the **Self-Service Provisioning Platform (SPP)**, consumed as the sole input by the **AI Software Factory** ([`vaishnavi4068/spp-factory-foundation`](https://github.com/vaishnavi4068/spp-factory-foundation)).

---

## 1. Five-Level ADR Hierarchy (Aligned with `spp-factory-foundation`)

| Level | Folder | ID Prefix | Scope |
| :--- | :--- | :--- | :--- |
| **1. Global** | `adr/global/` | `ADR-GLB-` | Platform-wide invariants: global architecture overview, languages & stack, 4-state model, data model & Postgres database, Workload Identity & auth, naming/labeling conventions, and clean-slate OPA/Rego governance gates |
| **2. Business Process** | `adr/business-process/` | `ADR-BP-` | Stakeholder ownership map, Operations governance, persona permissions, and 6-phase product build order |
| **3. Endpoint / Service** | `adr/endpoint-service/` | `ADR-SVC-` | Cross-cutting vertical slice and endpoint service specifications (first vertical slice = GCS bucket end-to-end with no UI; detailed per-service ADRs for GCS, Spanner, VM, API, and DB migrations live in `ssp-cp`) |
| **4. Per Cloud** | `adr/per-cloud/gcp/` | `ADR-CLD-GCP-` | Runtime platform on GCP (`md-dev`, tainted `spp-pool`, namespaces `spp-temporal`/`spp-factory`/`spp-platform`, self-hosted Temporal namespaces `factory` and `platform`) and GCP 2.0 target architecture (`adr/per-cloud/` kept extensible for future clouds) |
| **5. Automation** | `adr/automation/` | `ADR-AUT-` | Deterministic Kubernetes Job Terraform execution (`tf-op-<operation_id>`, state in `gs://microdrive-dev-spp-tfstate`), Day-2 operations scope (update, resize, upgrade, drift detection, rollback, decommission, cost), and software factory ADR flow across the 10 role skills |

---

## 2. Prerequisite ADR Catalog (`Status: Proposed`, Unsigned)

| ADR ID | Level | Title | Topic Covered | Status | Signers | Named Owner | Shared Mailbox | File |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **ADR-GLB-001** | `global` | Global Architecture Overview | GCP-only SPP control plane and 2.0 target scope, AI software factory integration | Proposed | Unsigned | Manoj | `spp-architecture@tbd` | [global/ADR-GLB-001-global-architecture-overview.md](global/ADR-GLB-001-global-architecture-overview.md) |
| **ADR-GLB-002** | `global` | Languages and Technology Stack | Python FastAPI (`ssp-cp`) + Temporal Python SDK (`ssp-workers`), React (`ssp-ui`), Terraform `>= 1.10`, Rego | Proposed | Unsigned | Manoj | `spp-architecture@tbd` | [global/ADR-GLB-002-languages-and-technology-stack.md](global/ADR-GLB-002-languages-and-technology-stack.md) |
| **ADR-GLB-003** | `global` | Four-State Provisioning Model and Storage Layout | `Requested` & `Approved` in Postgres (no secrets); `Expected` & `Observed` in GCS (`expected/` & `observed/`, 1 state/project) | Proposed | Unsigned | Manoj | `spp-architecture@tbd` | [global/ADR-GLB-003-four-state-model.md](global/ADR-GLB-003-four-state-model.md) |
| **ADR-GLB-004** | `global` | Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL) | Dedicated AlloyDB for PostgreSQL (`spp_platform` in `microdrive-dev`), private IP/PSA, IAM/Workload Identity auth, core tables, JSONB schemas, idempotency, Alembic migrations in `ssp-cp` | Proposed | Unsigned | Manoj | `spp-architecture@tbd` | [global/ADR-GLB-004-data-model-and-database.md](global/ADR-GLB-004-data-model-and-database.md) |
| **ADR-GLB-005** | `global` | Identity, Workload Identity, and Authentication | GKE Workload Identity (no keys), 1 SA/project + platform SA kill button, Argon2id local login now, SSO/OAuth later | Proposed | Unsigned | Manoj | `spp-security@tbd` | [global/ADR-GLB-005-identity-and-authentication.md](global/ADR-GLB-005-identity-and-authentication.md) |
| **ADR-GLB-006** | `global` | Naming and Labeling Conventions | 2.0 GCP naming convention, deterministic K8s Job names, mandatory labels (`apm_id`, `cost_center`, `environment`, `owner`, `data_classification`) | Proposed | Unsigned | Manoj | `spp-architecture@tbd` | [global/ADR-GLB-006-naming-and-labeling-conventions.md](global/ADR-GLB-006-naming-and-labeling-conventions.md) |
| **ADR-GLB-007** | `global` | Governance Gates and Policy (Rego) | Clean-slate OPA/Rego rules, CMEK, `>= 90d` retention, Raju baseline, non-bypassable Operations Gate, 7-stage CI gate | Proposed | Unsigned | Manoj | `spp-policy@tbd` | [global/ADR-GLB-007-governance-gates-and-policy-rego.md](global/ADR-GLB-007-governance-gates-and-policy-rego.md) |
| **ADR-BP-001** | `business-process` | Ownership Map and Stakeholder Governance | SPP team (`microdrive-dev` SAs), Raju (Security), Allen & Karen (Ops), Norm & Manoj (Lead Eng/Code Owners), Dwayne & Norm (Approvers), Hurley (enterprise clusters), Ken O'Connor (ServiceNow/CMDB post-MVP placeholder) | Proposed | Unsigned | Norm | `spp-governance@tbd` | [business-process/ADR-BP-001-ownership-map-and-governance.md](business-process/ADR-BP-001-ownership-map-and-governance.md) |
| **ADR-BP-002** | `business-process` | Product Build Order and Delivery Phasing | 1) Global/data-model ADRs -> 2) Control-plane skeleton -> 3) GCS E2E (no UI) -> 4) GCS Day-2 -> 5) UI/chat -> 6) More resource types | Proposed | Unsigned | Manoj | `spp-architecture@tbd` | [business-process/ADR-BP-002-build-order-and-phasing.md](business-process/ADR-BP-002-build-order-and-phasing.md) |
| **ADR-SVC-001** | `endpoint-service` | First Vertical Slice — GCS Bucket End-to-End (No UI) | Headless API-driven `google_storage_bucket` creation through all 4 states into `gs://microdrive-dev-spp-tfstate` | Proposed | Unsigned | Manoj | `spp-storage-gcp@tbd` | [endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md](endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md) |
| **ADR-CLD-GCP-001** | `per-cloud (gcp)` | Runtime Platform (GKE `md-dev`, Tainted `spp-pool`, Namespaces, and Self-Hosted Temporal) | GKE `md-dev`, tainted `spp-pool`, K8s namespaces `spp-temporal`/`spp-factory`/`spp-platform`, self-hosted Temporal with Postgres, Temporal namespaces `factory` and `platform` | Proposed | Unsigned | Manoj | `spp-cloud-gcp@tbd` | [per-cloud/gcp/ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md](per-cloud/gcp/ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md) |
| **ADR-AUT-001** | `automation` | Terraform Execution via Deterministic Kubernetes Jobs | One K8s Job per run (`tf-op-<operation_id>`) in `spp-platform`, ~30s polling, reattach on retry, state in `gs://microdrive-dev-spp-tfstate` | Proposed | Unsigned | Dwayne | `spp-automation@tbd` | [automation/ADR-AUT-001-terraform-execution-k8s-job.md](automation/ADR-AUT-001-terraform-execution-k8s-job.md) |
| **ADR-AUT-002** | `automation` | Day-2 Operations Scope | Update, resize, upgrade, drift detection (by CSP resource ID), rollback, decommission, and cost | Proposed | Unsigned | Norm | `spp-automation@tbd` | [automation/ADR-AUT-002-day-2-operations-scope.md](automation/ADR-AUT-002-day-2-operations-scope.md) |
| **ADR-AUT-003** | `automation` | Software Factory ADR Flow, 10 Role Skills, and Verification Gates | How ADRs flow into `spp-factory-foundation` across 10 role skills, 8 stations, 3-retry rework bound, and 3 autonomy phases | Proposed | Unsigned | Manoj | `spp-factory@tbd` | [automation/ADR-AUT-003-software-factory-adr-flow.md](automation/ADR-AUT-003-software-factory-adr-flow.md) |

---

## 3. Authoring & Linting Rules

1. Copy [`../templates/adr-template.md`](../templates/adr-template.md) into the appropriate level folder (`global/`, `business-process/`, `endpoint-service/`, `per-cloud/gcp/`, or `automation/`).
2. Populate all required metadata lines (`ADR ID`, `Level`, `Status`, `Owner` with `Shared Mailbox:` and `Named Owner:`, `Signers`, `Affected Repos`, `Last Updated`) and required sections (`## Goal`, `## Context`, `## Decision`, `## Requirements`, `## Guardrails`, `## Consequences`, `## Acceptance Criteria`, `## Success Criteria`, `## Affected Repos`, `## Open Questions`, `## Related ADRs`).
3. Validate against the factory ADR linter:
   ```bash
   python3 <path-to-spp-factory-foundation>/gates/scripts/lint_adrs.py adr
   ```
