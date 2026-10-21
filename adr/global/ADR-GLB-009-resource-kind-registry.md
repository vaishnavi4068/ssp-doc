# ADR-GLB-009: Resource Kind Registry

- **ADR ID:** ADR-GLB-009
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the data-driven **Resource Kind Registry (`idp.resource_kind`)** that maps each supported GCP resource kind (`gcs_bucket`, `spanner_instance`, `spanner_database`) to its parent kind, JSON Schema URI and version, pinned Terraform module source, project-level `tfvars_collection` key, Terraform address template, OPA policy package, human approval gate key, and `drift_ignore_paths`, enabling SPP to onboard new resource kinds without adding database tables or changing reconciler logic.

## Context

From the sanitized four-gate design package (`resource-types.md`, `data-model.md`, `raw/idp_state_model.reconstructed.sql`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)) and user overrides:

1. **Why a Kind Registry Instead of Per-Kind Tables or Hardcoded Switch Statements:**
   - Every resource in SPP shares the same relational lifecycle (`idp.resource`, `idp.request`, `idp.approval`, `idp.expected_revision_member`, `idp.resource_observed`, `idp.drift_finding`), while kind-specific differences are purely declarative metadata:
     - Which JSON Schema validates `requested_spec`, `approved_spec`, `expected`, and `observed` (`schema_uri`, `schema_version`).
     - Which pinned Terraform module repo/version implements the kind (`tf_module_source`).
     - Which top-level map in `projects/<project_id>/expected/rev-NNNNNN/terraform.tfvars.json` holds entries of this kind (`tfvars_collection`, plural of `kind`, unique per `cloud`).
     - How the resource's Terraform address is formatted (`tf_address_template`, e.g., `module.spanner_database["{instance}/{name}"]`).
     - Which OPA package evaluates `requested`/`approved` guardrails (`opa_package`).
     - Which human approval gate governs the kind (`approval_gate_key` FK to `idp.approval_gate_config`).
     - Which JSON pointers are excluded from `Expected` vs. `Observed` drift comparison (`drift_ignore_paths`, for Terraform-only guards like `/force_destroy` and `/deletion_protection` or app-owned attributes like `/ddl`).
2. **Parent-Child Resource Relationships (`parent_kind`):**
   - Modelling `spanner_instance` and `spanner_database` as two distinct kinds where `spanner_database.parent_kind = 'spanner_instance'` (and `idp.resource.parent_resource_id` points to the parent instance row) allows application teams to add databases to an existing or shared DBaaS Spanner instance, assign each database its own `owner`, `apm_id`, and approval, and keep IAM bindings at the database level.

## Decision

### 1. `idp.resource_kind` Table Schema (`specs/data-model/spp_state_model.sql`)

```sql
CREATE TABLE idp.resource_kind (
  kind                 text PRIMARY KEY,
  cloud                text NOT NULL CHECK (cloud IN ('gcp')),
  parent_kind          text REFERENCES idp.resource_kind (kind),
  display_name         text NOT NULL,
  schema_uri           text NOT NULL,
  schema_version       text NOT NULL,
  tf_module_source     text NOT NULL,
  tfvars_collection    text NOT NULL,
  tf_address_template  text NOT NULL,
  opa_package          text NOT NULL,
  approval_gate_key    text REFERENCES idp.approval_gate_config (gate_key),
  drift_ignore_paths   text[] NOT NULL DEFAULT '{}',
  legacy_resource_type text,
  enabled              boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cloud, tfvars_collection)
);
```

### 2. Initial Seed Rows (`gcs_bucket`, `spanner_instance`, `spanner_database`)

*(Note: In the source DDL photos, lines 649–652 for `gcs_bucket` were partially cut off `[NOT CAPTURED]`; cells marked `[Unverified (source gap): inferred]` below preserve the exact captured tail `ARRAY['/force_destroy'], 'storage-bucket'` and infer the middle columns from the `spanner_instance` seed row and `resource-types.md`.)*

| Column | `gcs_bucket` | `spanner_instance` | `spanner_database` |
| :--- | :--- | :--- | :--- |
| **`kind`** | `gcs_bucket` | `spanner_instance` | `spanner_database` |
| **`cloud`** | `gcp` | `gcp` | `gcp` |
| **`parent_kind`** | `NULL` | `NULL` | `spanner_instance` |
| **`display_name`** | `Cloud Storage bucket` *(Unverified: inferred)* | `Spanner instance` | `Spanner database` |
| **`schema_uri`** | `schemas/gcs_bucket.schema.json` | `schemas/spanner.schema.json` | `schemas/spanner.schema.json` |
| **`schema_version`** | `1.0.0` | `1.0.0` | `1.0.0` |
| **`tf_module_source`** | `git::https://github.com/vaishnavi4068/ssp-module-gcs-bucket.git//modules/bucket?ref=v1.0.0` *(Unverified: source had `git::https://github.com/<org>/tf-gcp-gcs-bucket.git...` `[NOT CAPTURED]`)* | `git::https://github.com/vaishnavi4068/ssp-module-spanner.git//modules/instance?ref=v1.0.0` *(source: `tf-gcp-spanner.git//modules/instance?ref=v1.0.0`)* | `git::https://github.com/vaishnavi4068/ssp-module-spanner.git//modules/database?ref=v1.0.0` *(source: `tf-gcp-spanner.git//modules/database?ref=v1.0.0`)* |
| **`tfvars_collection`** | `gcs_buckets` | `spanner_instances` | `spanner_databases` |
| **`tf_address_template`** | `module.gcs_bucket["{name}"]` *(Unverified: inferred)* | `module.spanner_instance["{name}"]` | `module.spanner_database["{instance}/{name}"]` |
| **`opa_package`** | `idp.gcp.gcs_bucket` *(Unverified: inferred)* | `idp.gcp.spanner_instance` | `idp.gcp.spanner_database` |
| **`approval_gate_key`** | `gcs_bucket_owner` | `spanner_data_owner` | `spanner_data_owner` |
| **`drift_ignore_paths`** | `ARRAY['/force_destroy']` | `ARRAY['/force_destroy']` | `ARRAY['/ddl', '/deletion_protection']` |
| **`legacy_resource_type`** | `'storage-bucket'` *(deferred note)* | `'spanner-instance'` *(deferred note)* | `'spanner-instance (databases[])'` *(deferred note)* |

### 3. Deterministic Resource Key and Terraform Address Construction

- **`resource_key`:** Constructed as `gcp:<project_id>:<kind>:<name>`
  - For root kinds (`parent_kind IS NULL`): `<name>` is `spec.name` (e.g., `gcp:<lob>-nonprod-orders-svc:gcs_bucket:<lob>-nonprod-orders-landing-a1b2` or `gcp:<lob>-nonprod-orders-svc:spanner_instance:<lob>-nonprod-orders`).
  - For child kinds (`spanner_database`): `<name>` in `idp.resource` and `tfvars_key` is `<instance>/<database>` (e.g., `gcp:<lob>-nonprod-orders-svc:spanner_database:<lob>-nonprod-orders/orders`), and `tf_address` renders `module.spanner_database["<lob>-nonprod-orders/orders"]`.

## Requirements

- **REQ-1 (MUST):** Every resource kind supported by SPP MUST be registered in `idp.resource_kind` with `cloud = 'gcp'`, a unique `(cloud, tfvars_collection)` pair, a pinned `tf_module_source` (`?ref=vX.Y.Z`), `schema_uri`, `schema_version`, `tf_address_template`, `opa_package`, `approval_gate_key`, and `drift_ignore_paths`.
- **REQ-2 (MUST):** When `parent_kind` is non-null on `idp.resource_kind` (such as `spanner_database` → `spanner_instance`), `ssp-cp` MUST require `idp.resource.parent_resource_id` to reference an existing `idp.resource` row of `kind = parent_kind` in the same `state_unit_id`.
- **REQ-3 (MUST):** `StateUnitReconcilerWorkflow` (`ssp-workers`) MUST compose `projects/<project_id>/expected/rev-NNNNNN/terraform.tfvars.json` dynamically by grouping each active member's `Expected` entry under its kind's `tfvars_collection` (`gcs_buckets`, `spanner_instances`, `spanner_databases`).
- **REQ-4 (MUST):** The drift comparer in `ssp-workers` MUST subtract `resource_kind.drift_ignore_paths` from the JSON-pointer diff between `Expected` and `Observed`.

## Guardrails

- **GR-1:** Never hardcode per-kind `tfvars` map keys, OPA package names, or drift-ignore lists in Python workflow code when they belong in `idp.resource_kind`.
- **GR-2:** Never use unpinned (`main` / `HEAD`) Git references in `idp.resource_kind.tf_module_source`; always pin a semantic version tag (`?ref=vX.Y.Z`).
- **GR-3:** Never enable non-GCP clouds (`aws`, `azure`) in `idp.resource_kind.cloud` without a superseding ADR.

## Consequences

### Positive

- Onboarding a new GCP resource kind requires only: 1) authoring its per-kind ADR, JSON Schema, and `ssp-module-<type>` repo, and 2) inserting one row into `idp.resource_kind` (and `idp.approval_gate_config` if needed)—zero DDL table additions and zero reconciler code changes.

### Negative / Trade-offs

- Schema versions (`schema_version`) and module versions (`tf_module_source`) must be versioned carefully when evolving an existing kind's contract.

## Acceptance Criteria

- [ ] `idp.resource_kind` table and seed rows for `gcs_bucket`, `spanner_instance`, and `spanner_database` are present in `specs/data-model/spp_state_model.sql`.
- [ ] `ssp-cp` loads kind metadata from `idp.resource_kind` to drive schema validation, OPA evaluation, and approval gate selection.
- [ ] `ssp-workers` uses `tfvars_collection`, `tf_address_template`, and `drift_ignore_paths` from `idp.resource_kind`.

## Success Criteria

- **SC-1:**
  - **Given** the `idp.resource_kind` seed rows for `gcs_bucket`, `spanner_instance`, and `spanner_database`
  - **When** `StateUnitReconcilerWorkflow` renders an `Expected` revision containing one bucket, one Spanner instance, and one Spanner database
  - **Then** `terraform.tfvars.json` contains top-level keys `gcs_buckets`, `spanner_instances`, and `spanner_databases`, and `idp.expected_revision_member.tf_address` matches each kind's `tf_address_template`.
- **SC-2:**
  - **Given** a `spanner_database` with `drift_ignore_paths = ['/ddl', '/deletion_protection']`
  - **When** the application's migration pipeline alters tables in the database after creation
  - **Then** the drift comparer ignores `/ddl` and `/deletion_protection` and reports zero false-positive drift findings.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-GLB-009` and the `idp.resource_kind` seed catalog in `specs/data-model/spp_state_model.sql` |
| `ssp-cp` | Queries `idp.resource_kind` for intake validation, OPA dispatch, and approval gate routing |
| `ssp-workers` | Uses `idp.resource_kind` to compose `terraform.tfvars.json`, pin modules in `manifest.json`, and filter drift paths |
| `ssp-module-gcs-bucket`, `ssp-module-spanner` | Implements the modules referenced by `idp.resource_kind.tf_module_source` |
| `spp-factory-foundation` | Validates `resource_kind` entries and module interfaces |

## Open Questions

- [ ] **OQ-1 (Unverified Source Gaps in `gcs_bucket` Kind Seed & `examples/resource_kinds.json` — SOURCE GAP [Owner: Manoj]):** **Unverified (source gap):**
  1. `idp_state_model.sql` lines 649–652 (`gcs_bucket` seed row) had its middle columns cut off in the photo (`tf_address_template`, `opa_package`, `tf_module_source`, `display_name`, `schema_uri` are inferred from `spanner_instance` and `resource-types.md`).
  2. `examples/resource_kinds.json` was listed in the source package file tree (photo 6548) as "kind registry mirroring `resource_kind` seed rows" but was `[NOT CAPTURED]` in the photos.

## Related ADRs

- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](../endpoint-service/ADR-SVC-002-spanner-instance-and-database.md)
