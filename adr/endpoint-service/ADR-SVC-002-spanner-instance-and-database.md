# ADR-SVC-002: Cloud Spanner Instance (`spanner_instance`) and Database (`spanner_database`) Specification

- **ADR ID:** ADR-SVC-002
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-database-gcp@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Karen [DBA/Operations], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-spanner`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the four-gate specification (`Requested` → `Approved` → `Expected` → `Observed`), parent-child relationship, tier/environment-driven guardrails (`SPN-CFG-001`, `SPN-EDT-001/002`, `SPN-BKP-001/002`, `SPN-DEL-001/002`, `SPN-ENC-001`, `SPN-IAM-001`, `SPN-NAME-001..003`, `PRQ-003/004`), five Spanner-specific architectural quirks, and tenancy model for **`spanner_instance`** and **`spanner_database`** in `ssp-module-spanner`, constrained to single region **`us-east1`** (`regional-us-east1`) across both `nonprod` and `prod`.

## Context

From the sanitized four-gate design package (`resource-types.md` §7, `gates.md` §7, `raw/README_2.transcript.md`, `examples/spanner.gates.json`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)) and user overrides:

1. **Why Two Distinct Kinds (`spanner_instance` and `spanner_database`):**
   - Modelling `spanner_instance` (root kind) and `spanner_database` (`parent_kind = "spanner_instance"`, with `idp.resource.parent_resource_id` referencing the instance) as separate resource kinds enables:
     1. A single intake submission (`template = "spanner-instance-with-databases"`) to map into two linked `idp.request` rows (`/resources/0` for the instance, `/resources/1` for the database).
     2. Application teams to add new databases to an existing dedicated or shared DBaaS Spanner instance without modifying the instance resource itself.
     3. Each database to have its own `owner`, `apm_id`, and `approval` record while keeping IAM data-plane roles (`roles/spanner.databaseReader`, `roles/spanner.databaseUser`) scoped to the database level.
2. **User Overrides Applied to Spanner:**
   - **Region `us-east1` Only (No `nam3` Multi-Region, No `us-east4`):** In the source package, Tier 1 / `prod` resolved to multi-region `nam3` (active-active) and Tier 2–4 `nonprod` resolved to `regional-us-east4`. **User decision overrides this everywhere:** SPP is strictly **region `us-east1` only** (`config = "regional-us-east1"`, CMEK key in `locations/us-east1`), including `prod` and Tier 1 (`no multi-region`, `not nam3 Spanner`).
   - **Environments `nonprod` and `prod` Only (Including DBaaS Reviewer Skip Rule):** `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod` all map to `nonprod` everywhere, including the `spanner_data_owner` gate's `dbaas_reviewer` skip condition (`metadata.environment not in ('prod') and metadata.resolved.app_tier != '1'`).
   - **No Deletion/Destroy/Replace Without Explicit Human Approval in ANY Environment:** Both `spanner_instance` (`force_destroy = false`) and `spanner_database` (`deletion_protection = true`, `enable_drop_protection = true`) require explicit human approval for any delete or destructive replacement in `nonprod` and `prod`.

## Decision

### 1. Tier & Environment Guardrail Matrix (`SPN-*`)

At the `Approved` gate, `ssp-cp` resolves `app_tier` from `metadata.apm_id` (`idp.apm_alias` / portfolio lookup) and `environment_type` (`nonprod` or `prod`) and applies the following defaults (with the `us-east1`-only override applied):

| Dimension / Rule ID | Tier 1 **or** `prod` | Tier 2–4, `nonprod` |
| :--- | :--- | :--- |
| **Instance Config (`SPN-CFG-001`)** | **`regional-us-east1`** *(Overridden from source `nam3` per SPP `us-east1`-only, no-multi-region decision)* | **`regional-us-east1`** *(Overridden from source `regional-us-east4`)* |
| **Edition (`SPN-EDT-001` / `002`)** | `ENTERPRISE_PLUS` (or `ENTERPRISE` as required by tier policy) | `STANDARD` (`ENTERPRISE` if `autoscaling_config` is set) |
| **Capacity (`compute`)** | Autoscaling, minimum `1,000` processing units (`PU`) | As requested (e.g., `100` PU; must be `100..900` in steps of `100`, or multiples of `1,000`) |
| **Backups (`SPN-BKP-001` / `002`)** | Instance `default_backup_schedule_type = "AUTOMATIC"`, plus explicit daily `backup_schedule` on database (`SPN-BKP-002`) | Instance `default_backup_schedule_type = "AUTOMATIC"` (`SPN-BKP-001`); database `backup_schedule = null` (`SPN-BKP-002`) |
| **Approvers (`spanner_data_owner` gate)** | `data_owner` (`/metadata/owner`), then `dbaas_reviewer` (role `dbaas_reviewer`) | `data_owner` only (`dbaas_reviewer` skipped via `metadata.environment not in ('prod') and metadata.resolved.app_tier != '1'`) |

### 2. Complete Spanner Guardrail & Prerequisite Rules

| Rule ID | Target Kind | Gate | Path / Attribute | Enforced Value & Rationale (`guardrail_trace`) |
| :--- | :--- | :--- | :--- | :--- |
| **`SPN-NAME-001`** | `spanner_instance` | `requested` | `/spec/name` | Must match `{lob}-{env}-{app}[-{purpose}]` (`max 64` chars, `env` in `{"nonprod", "prod"}`, e.g., `<lob>-nonprod-orders`). |
| **`SPN-NAME-002`** | `spanner_database` | `requested` | `/spec/name` | Must match `{app}[_{purpose}]` (snake_case, `max 30` chars, e.g., `orders` or `orders_history`). |
| **`SPN-NAME-003`** | `spanner_instance` | `approved` | `/spec/display_name` | Replaced with generated `{LOB} {App}[ {Purpose}] ({env})` (`4..30` chars, e.g., `"SPP Orders (nonprod)"`) and recorded in `guardrail_trace`. |
| **`SPN-CFG-001`** | `spanner_instance` | `approved` | `/spec/config` | `null` → `"regional-us-east1"` (single-region `us-east1` override). |
| **`SPN-EDT-001` / `002`** | `spanner_instance` | `approved` | `/spec/edition` | `null` → `"STANDARD"` (for non-autoscaled Tier 2–4 `nonprod`), `"ENTERPRISE"` (if autoscaled in `nonprod`), or `"ENTERPRISE_PLUS"` (for Tier 1 / `prod`). Encoded in JSON Schema with `if/then` so `approved_spec` cannot violate edition rules. |
| **`SPN-BKP-001`** | `spanner_instance` | `approved` | `/spec/default_backup_schedule_type` | `null` → `"AUTOMATIC"` (legacy requests documented `"NONE"`). |
| **`SPN-BKP-002`** | `spanner_database` | `approved` | `/spec/backup_schedule` | `null` → `null` for Tier 2–4 `nonprod` (instance `AUTOMATIC` default suffices); explicit daily backup schedule for Tier 1 / `prod`. |
| **`SPN-DEL-001`** | `spanner_instance` | `approved` | `/spec/force_destroy` | `null` → `false` ("No force destroy."). |
| **`SPN-DEL-002`** | `spanner_database` | `approved` | `/spec/deletion_protection`, `/spec/enable_drop_protection` | `null` → `true` for both `deletion_protection` (Terraform-side delete guard) and `enable_drop_protection` (cloud drop protection). |
| **`SPN-ENC-001`** | `spanner_database` | `approved` | `/spec/kms_key_names` (`encryption_config.kms_key_names`) | `null` → `["projects/<lob>-kms-<env>/locations/us-east1/keyRings/<lob>-<env>-use1/cryptoKeys/spanner-default"]` (CMEK key in `us-east1` matching `regional-us-east1`; in `microdrive-dev`, uses `projects/microdrive-dev/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>`). |
| **`SPN-IAM-001`** | `spanner_instance` | `requested` / `approved` | `/spec/access` | **Denies** `roles/spanner.databaseReader` (or database-level data access roles) at the **instance** level on `shared` tenancy instances (allowed only on `dedicated` instances; instance-level access is for `roles/spanner.viewer` DBA groups). |
| **`LBL-001` / `002`** | `spanner_instance` | `approved` | `/metadata/labels` | Merges and normalizes the 9 mandatory labels (`ADR-GLB-008`). |
| **`PRQ-003`** | `spanner_instance` | `approved` | `/prerequisites/0` | `enable_service` for `spanner.googleapis.com` on `<project_id>`. |
| **`PRQ-004`** | `spanner_instance` | `approved` | `/prerequisites/1` | `vpc_sc_project_membership` verifying `<project_id>` is inside `<lob>_<env>_restricted_perimeter`. |

### 3. Gate 3 (`Expected`) Composed `tfvars` Entries (`spanner_instances` and `spanner_databases`)

**`spanner_instances["<lob>-nonprod-orders"]`:**
```json
{
  "project": "<lob>-nonprod-orders-svc",
  "name": "<lob>-nonprod-orders",
  "display_name": "SPP Orders (nonprod)",
  "config": "regional-us-east1",
  "edition": "STANDARD",
  "instance_type": "PROVISIONED",
  "processing_units": 100,
  "num_nodes": null,
  "autoscaling_config": null,
  "default_backup_schedule_type": "AUTOMATIC",
  "labels": {
    "app": "orders",
    "costcenter": "000000",
    "dataclassification": "proprietary",
    "datasensitivity": "restricted",
    "environmentsubtype": "nonprod",
    "environmenttype": "nonprod",
    "idp_resource_id": "3936dbd5-d13d-5d84-ad7a-a1e3a595f213",
    "owner": "data_owner_example_com",
    "primarylob": "<lob>",
    "provisionedby": "idp",
    "sharedemailaddress": "orders-team_example_com",
    "sppappid": "apm0017299",
    "tenancy": "dedicated"
  },
  "iam_bindings": {
    "roles/spanner.viewer": [
      "group:gcp-<lob>-nonprod-orders-dba@example.com"
    ]
  },
  "force_destroy": false
}
```

**`spanner_databases["<lob>-nonprod-orders/orders"]`:**
```json
{
  "project": "<lob>-nonprod-orders-svc",
  "instance": "<lob>-nonprod-orders",
  "name": "orders",
  "database_dialect": "GOOGLE_STANDARD_SQL",
  "version_retention_period": "1h",
  "encryption_config": {
    "kms_key_names": [
      "projects/<lob>-kms-nonprod/locations/us-east1/keyRings/<lob>-nonprod-use1/cryptoKeys/spanner-default"
    ]
  },
  "deletion_protection": true,
  "enable_drop_protection": true,
  "ddl": [
    "CREATE TABLE orders (order_id STRING(36) NOT NULL, created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)) PRIMARY KEY (order_id)"
  ],
  "backup_schedule": null,
  "iam_bindings": {
    "roles/spanner.databaseReader": [
      "group:gcp-<lob>-nonprod-orders-read@example.com"
    ],
    "roles/spanner.databaseUser": [
      "serviceAccount:orders-api@<lob>-nonprod-orders-svc.iam.gserviceaccount.com"
    ]
  }
}
```

### 4. Five Spanner Architectural Quirks & Tenancy Rules

1. **Quirk 1 — Spanner Databases Carry No GCP Labels:** GCP only supports labels on `google_spanner_instance`, not `google_spanner_database`. Therefore, `spanner_database` omits `labels` in `tfvars` and `Observed` projection, while `idp.resource` in AlloyDB tracks the database's `apm_id`, `resource_id`, and `owner`.
2. **Quirk 2 — `deletion_protection` Is a Terraform-Side Guard:** Because `deletion_protection` on `google_spanner_database` is a Terraform provider attribute rather than a GCP API property, `/deletion_protection` is listed in `idp.resource_kind.drift_ignore_paths` for `spanner_database` (while `enable_drop_protection` is enforced in GCP).
3. **Quirk 3 — Initial `ddl` Is Owned by the Application Migration Pipeline Post-Create:** `initial_ddl` / `ddl` is applied at database creation time and subsequently managed by the application team's schema migration pipeline. `/ddl` is therefore listed in `idp.resource_kind.drift_ignore_paths` so application schema migrations never trigger infrastructure drift alerts.
4. **Quirk 4 — `processing_units` When Autoscaled:** When `autoscaling_config` is set on `spanner_instance`, `processing_units` fluctuates dynamically and is observed-only (excluded from drift comparison). When `autoscaling_config` is `null` (provisioned capacity, e.g., `100` PU), out-of-band scaling (e.g., `100 -> 300` PU in GCP Console) produces a `medium` severity `out_of_band_change` drift finding (`specs/examples/spanner.gates.json`).
5. **Quirk 5 — Instance-Level `roles/spanner.databaseReader` (`SPN-IAM-001`):** Granting `roles/spanner.databaseReader` at the Spanner instance level grants read access to every database on that instance. The schema and OPA rule `SPN-IAM-001` allow this only when `metadata.tenancy == "dedicated"` and **deny** it when `metadata.tenancy == "shared"`.
6. **Dedicated vs. Shared DBaaS Tenancy:** A `spanner_database` always resides in its parent `spanner_instance`'s GCP project (`state_unit_id`). On a shared DBaaS instance, tenant databases live in the DBaaS project's state unit while `idp.resource.apm_id` records the tenant application's `apm_id`.

## Requirements

- **REQ-1 (MUST):** `ssp-cp` and `ssp-module-spanner` MUST model Spanner as two resource kinds (`spanner_instance` with `tfvars_collection = "spanner_instances"` and `spanner_database` with `parent_kind = "spanner_instance"` and `tfvars_collection = "spanner_databases"`).
- **REQ-2 (MUST):** `SPN-CFG-001` MUST set `config = "regional-us-east1"` and `SPN-ENC-001` MUST set CMEK keys in `locations/us-east1` across all tiers and environments (`nonprod` and `prod`); multi-region configurations (`nam3`) MUST NOT be used.
- **REQ-3 (MUST):** `processing_units` on non-autoscaled `spanner_instance` requests MUST be validated as `100..900` in increments of `100`, or multiples of `1,000`.
- **REQ-4 (MUST):** OPA rule `SPN-IAM-001` MUST reject `roles/spanner.databaseReader` (or database-level data roles) on `spanner_instance` when `metadata.tenancy == "shared"`.
- **REQ-5 (MUST):** `idp.resource_kind.drift_ignore_paths` MUST exclude `['/force_destroy']` on `spanner_instance` (plus `/processing_units` when `autoscaling_config != null`) and `['/ddl', '/deletion_protection']` on `spanner_database`.

## Guardrails

- **GR-1:** Never provision a multi-region Spanner instance (`nam3`) or non-`us-east1` regional instance (`regional-us-east4`); only `regional-us-east1` is permitted.
- **GR-2:** Never set `force_destroy = true` on `spanner_instance` (`SPN-DEL-001`) or `deletion_protection = false` / `enable_drop_protection = false` on `spanner_database` (`SPN-DEL-002`) at creation.
- **GR-3:** Never grant `roles/spanner.databaseReader` at the instance level on a shared Spanner instance (`SPN-IAM-001`).
- **GR-4:** Never allow deletion of a `spanner_instance` or `spanner_database` without explicit human approval in both `nonprod` and `prod`.

## Consequences

### Positive

- Clean separation between `spanner_instance` and `spanner_database` supports both single-submission creation (`spanner-instance-with-databases`) and Day-2 addition of databases to existing/shared instances.
- Ignoring `/ddl` and `/deletion_protection` in drift scans prevents false-positive drift alerts when app teams run Flyway/Liquibase/Alembic DDL migrations on their Spanner databases.

### Negative / Trade-offs

- Because `us-east1`-only overrides multi-region `nam3`, Tier 1 and `prod` Spanner instances use regional high availability in `regional-us-east1` with `ENTERPRISE_PLUS` and explicit daily backups rather than multi-region active-active replication.

## Acceptance Criteria

- [ ] `specs/examples/spanner.gates.json` documents the reconstructed `spanner_instance` + `spanner_database` walkthrough across all four gates and drift scenario with `us-east1` and `nonprod` overrides applied.
- [ ] `ssp-module-spanner` implements `modules/instance` and `modules/database` matching the `spanner_instances` and `spanner_databases` tfvars schemas and `idp.gcp.spanner_instance` / `idp.gcp.spanner_database` Rego policies.
- [ ] `idp.resource_kind` and `idp.approval_gate_config` (`spanner_data_owner`) seed rows are present in `specs/data-model/spp_state_model.sql`.

## Success Criteria

- **SC-1:**
  - **Given** a UI/API submission with `template = "spanner-instance-with-databases"` for Tier 2 `nonprod` (`apm0017299`, `<lob>-nonprod-orders`, database `orders`, `100` PU)
  - **When** processed through `Requested -> Approved -> Expected -> Observed`
  - **Then** two `idp.request` rows (`source_pointer = "/resources/0"` and `"/resources/1"`) are created, `dbaas_reviewer` is skipped (`nonprod` + Tier 2), `SPN-CFG-001` sets `regional-us-east1`, `SPN-ENC-001` injects the `us-east1` CMEK key on the database, and `Expected`/`Observed` states are recorded.
- **SC-2:**
  - **Given** a Tier 1 or `prod` Spanner request
  - **When** evaluated by `ApprovalGateWorkflow` (`spanner_data_owner`) and OPA
  - **Then** both `data_owner` and `dbaas_reviewer` approvals are required sequentially, `SPN-EDT-001` enforces `ENTERPRISE_PLUS`, and `SPN-BKP-002` requires an explicit daily backup schedule.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-SVC-002` and `specs/examples/spanner.gates.json` |
| `ssp-cp` | Implements `spanner_instance` and `spanner_database` validation, `SPN-*` guardrails, and `spanner_data_owner` gate |
| `ssp-workers` | Executes `PRQ-003`/`PRQ-004` pre-apply tasks and Spanner drift comparison |
| `ssp-module-spanner` | Implements Terraform modules (`modules/instance`, `modules/database`) and Rego packages (`idp.gcp.spanner_instance`, `idp.gcp.spanner_database`) |
| `spp-factory-foundation` | Validates `spanner.gates.json` and `ssp-module-spanner` in `gates/` |

## Open Questions

- [x] **OQ-1 (Multi-Region `nam3` vs. `regional-us-east1` for Tier 1 / Prod — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Region is **`us-east1` only** (`regional-us-east1`), no multi-region (`not nam3 Spanner`), prod included.
- [x] **OQ-2 (Pre-Prod Environment Mapping in `dbaas_reviewer` Skip Condition — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod` all map to `nonprod` everywhere, including the Spanner `dbaas_reviewer` skip condition (`metadata.environment not in ('prod') and metadata.resolved.app_tier != '1'`).
- [ ] **OQ-3 (Unverified Source Gaps in `spanner.gates.json` & `spanner.schema.json` — SOURCE GAP [Owner: Manoj / Karen]):** **Unverified (source gap):**
  1. In `examples/spanner.gates.json` (`photos 6549-6572`), the tail of `initial_ddl` (`CREATE TABLE orders (order_id STRING(36) NOT NULL, created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp...[truncated]`) and the tail of the KMS key name in the README table (`.../cryptoKeys/[truncated]`, shown in `guardrail_trace` as `.../cryptoKeys/spanner-default`) were truncated at the right screen edge.
  2. `schemas/spanner.schema.json` was listed in the source file tree (photo 6548) but `[NOT CAPTURED]` in the photos.
  3. Whether shared DBaaS Spanner instances are enabled in Phase 6 alongside dedicated per-APM instances was listed as an open decision in the source ("Support both; databases on shared instance live in DBaaS project's state unit").

## Related ADRs

- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](../global/ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-008: Label and Tag Standard](../global/ADR-GLB-008-label-and-tag-standard.md)
- [ADR-GLB-009: Resource Kind Registry](../global/ADR-GLB-009-resource-kind-registry.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End and Guardrails](ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
