# ADR-GLB-002: Languages and Technology Stack

- **ADR ID:** ADR-GLB-002
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Standardize the programming languages, frameworks, and policy/infrastructure toolchains across all SPP product repositories (`ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`) so that they align with the AI Software Factory (`spp-factory-foundation`) and enable uniform code generation, testing, and operational support.

## Context

To avoid fragmenting the runtime stack across multiple backend languages and to match the proven implementation already running in `spp-factory-foundation` (`services/factory-api`, `services/factory-worker`, `services/factory-console`), the platform standardizes on:

1. **Python (`FastAPI` + `Temporal Python SDK`)** for the control plane API (`ssp-cp`) and Temporal workflow/activity workers (`ssp-workers`).
2. **React (`TypeScript` + `Vite` + `Tailwind CSS`)** for the user-facing portal and chat UI (`ssp-ui`), using template-driven catalog rendering (e.g., Handlebars / declarative schema templates) so adding a new resource module never requires redeploying the portal.
3. **Terraform (`>= 1.10`)** for all resource modules (`ssp-module-<type>`) and runner execution Jobs.
4. **Open Policy Agent (`OPA` / `Rego`) + `Conftest` + `JSON Schema Draft 2020-12`** for request validation, `Approved`-state guardrail verification, and CI gates.

*Note on Design Digest Context:* The raw design discussion transcript (`uploads/design-digest.md`) discussed Temporal, Terraform, OPA, Postgres, and Handlebars/micro-frontend UI templates, and did not mandate Go vs. Python in the spoken transcript; the standardization on Python (FastAPI + Temporal Python SDK) and React aligns the SPP product stack with the deployed `spp-factory-foundation` stack. Any unconfirmed library choices are tracked in `## Open Questions`.

## Decision

| Layer / Repository | Language & Runtime | Primary Frameworks & Libraries | Verification & Lint Tooling |
| :--- | :--- | :--- | :--- |
| **Control Plane API (`ssp-cp`)** | Python `3.11+` | `FastAPI`, `Pydantic v2`, `SQLAlchemy 2.x`, `Alembic`, `psycopg` / `google-cloud-alloydb-connector` (AlloyDB for PostgreSQL), `argon2-cffi`, `httpx` | `pytest`, `ruff` / `flake8`, `mypy`, `validate_schema.py` |
| **Temporal Workers & Runner Launcher (`ssp-workers`)** | Python `3.11+` | `temporalio` (Temporal Python SDK), `kubernetes` (official Python K8s client), `google-cloud-storage` | `pytest`, Temporal workflow replay tests, offline K8s Job spec tests |
| **Portal & Chat Storefront (`ssp-ui`)** | TypeScript `5.x` (Node `20+`) | `React 18+`, `Vite`, `Tailwind CSS`, declarative catalog templates (Handlebars / JSON Schema form renderer) | `tsc --noEmit`, `vitest` / `playwright`, `eslint` |
| **Resource Modules (`ssp-module-<type>`)** | HCL (Terraform `>= 1.10`) | Google Cloud provider (`hashicorp/google` / `hashicorp/google-beta`) | `terraform fmt -check`, `terraform validate`, `terraform test` (`mock_provider "google"`), `tfsec` |
| **Policy & Governance Gates (`ssp-doc`, `ssp-cp`, `ssp-module-*`)** | Rego (`rego.v1`), JSON Schema | `OPA v0.69+`, `Conftest v0.56+`, `jsonschema` (Draft 2020-12) | `opa test -v`, `conftest test`, `lint_adrs.py` |

## Requirements

- **REQ-1 (MUST):** The control plane service in `ssp-cp` MUST be implemented in Python (`>= 3.11`) using **FastAPI**, **Pydantic v2** for strict schema validation, and **SQLAlchemy / Alembic** for PostgreSQL persistence and schema migrations.
- **REQ-2 (MUST):** Temporal workflows and activities in `ssp-workers` MUST be implemented in Python (`>= 3.11`) using the official **Temporal Python SDK (`temporalio`)** and the official **Kubernetes Python client** to launch and poll `tf-op-<operation_id>` Jobs in `spp-platform`.
- **REQ-3 (MUST):** The user-facing portal and chat interface in `ssp-ui` MUST be implemented in **React** (with TypeScript) and MUST render service catalog forms dynamically from declarative templates/schemas so that adding a new `ssp-module-<type>` does not require rebuilding or redeploying `ssp-ui`.
- **REQ-4 (MUST):** All Terraform modules in `ssp-module-<type>` MUST require **Terraform `>= 1.10.0`** and support offline validation via `terraform test` with `mock_provider "google"`.
- **REQ-5 (MUST):** All policy rules in `ssp-cp` and `ssp-module-<type>` MUST be written in **Rego (`import rego.v1`)** and accompanied by unit tests (`*_test.rego`).
- **REQ-6 (SHOULD):** Shared Python schemas or contract models between `ssp-cp` and `ssp-workers` SHOULD be generated or validated directly against the canonical JSON Schema (`resource-request.schema.json`) to prevent drift.

## Guardrails

- **GR-1:** Do not introduce additional backend programming languages (e.g., Go, Java, Ruby) into `ssp-cp` or `ssp-workers` without a superseding Global ADR.
- **GR-2:** Do not hardcode per-service UI forms in React components that require a `ssp-ui` code deployment every time a new `ssp-module-<type>` is onboarded.
- **GR-3:** Never execute non-deterministic I/O (network calls, system clock, random UUIDs, subprocess execution) directly inside a Temporal `@workflow.defn` method; all side effects must execute inside `@activity.defn` activities.

## Consequences

### Positive

- **Unified Stack Across Factory and Product:** Both `spp-factory-foundation` (`factory-api`, `factory-worker`, `factory-console`) and the SPP product (`ssp-cp`, `ssp-workers`, `ssp-ui`) use Python (FastAPI + Temporal Python SDK) and React, allowing shared patterns, container base images, and agent skills.
- **Deterministic Code Generation:** Pydantic v2 models, FastAPI OpenAPI specs, and React catalog forms can be derived directly from ADR requirements and JSON Schemas.

### Negative / Trade-offs

- Earlier v0.1 exploratory notes in `ssp-doc` (`10-product/`, `40-repos/`) referenced Go (`chi`, `sqlc`) and Next.js; those legacy notes are superseded by this ADR and must not be used by factory agents when scaffolding `ssp-cp`, `ssp-workers`, or `ssp-ui`.

## Acceptance Criteria

- [ ] `ssp-cp` scaffolds its API and database migration layer using Python 3.11+, FastAPI, SQLAlchemy, and Alembic.
- [ ] `ssp-workers` scaffolds its Temporal worker and Kubernetes Job launcher using Python 3.11+ and `temporalio`.
- [ ] `ssp-ui` (when built in Phase 5) uses React + TypeScript + template-driven catalog rendering.

## Success Criteria

- **SC-1:**
  - **Given** the `ssp-cp` and `ssp-workers` repositories
  - **When** the factory agent executes the `control-plane` build skill
  - **Then** all generated API endpoints, database models, and Temporal workflows are authored in Python (`FastAPI` + `temporalio`) and pass `pytest` and static linting.
- **SC-2:**
  - **Given** a new resource repository `ssp-module-<type>` publishing its JSON Schema and catalog template metadata
  - **When** the bundle is registered with `ssp-cp`
  - **Then** `ssp-ui` renders the service's request form and IaC preview dynamically without a frontend code redeploy.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Establishes Python FastAPI + Temporal Python SDK + React as the locked stack |
| `ssp-cp` | Implemented in Python (FastAPI, SQLAlchemy, Alembic, OPA evaluation) |
| `ssp-workers` | Implemented in Python (`temporalio` SDK, `kubernetes` client) |
| `ssp-ui` | Implemented in React + TypeScript with template-driven catalog forms |
| `ssp-module-<type>` | Implemented in Terraform `>= 1.10` HCL (`hashicorp/google`) and OPA Rego (`rego.v1`) |
| `spp-factory-foundation` | Aligns `control-plane` and `portal-and-catalog` skills with Python/FastAPI and React |

## Open Questions

- [ ] **OQ-1 (Legacy v0.1 Spec Cleanup):** Should the earlier v0.1 exploratory directories (`10-product/`, `40-repos/`) that referenced Go and Next.js be archived/removed in a follow-up cleanup PR once this prerequisite ADR PR is reviewed?
- [ ] **OQ-2 (OPA Evaluation in Python):** Should `ssp-cp` evaluate Rego policies at runtime by invoking the `opa` binary / sidecar HTTP API (`localhost:8181`) or via an embedded WebAssembly/Python OPA bindings wrapper?
- [ ] **OQ-3 (UI Template Engine):** For `ssp-ui`, confirm whether Handlebars templates (`*.hbs`) + JSON Schema (`ui.json`) is the final template format for the micro-frontend catalog renderer, and which top-5 UI prototypes from Dwayne's gallery are selected as the visual baseline.

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-004: Data Model and Database](ADR-GLB-004-data-model-and-database.md)
- [ADR-AUT-001: Terraform Execution via Kubernetes Jobs](../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
