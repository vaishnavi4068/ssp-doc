# ADR-GLB-008: Label and Tag Standard

- **ADR ID:** ADR-GLB-008
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define a unified, canonical label standard (`LBL-001`, `LBL-002`) across all GCP resource kinds managed by SPP—including the **8 mandatory label keys** (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`), key/value normalization rules, `guardrail_trace` recording, Cloud Asset Inventory mapping via `idp_resource_id`, and Spanner database label-exclusion handling.

## Context

From the sanitized four-gate design package (`labels.md`, `naming.md`, `raw/naming-spec.reconstructed.json`, `gates.md`, `specs/examples/gcs_bucket.gates.json`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)) and user overrides:

1. **Replacing Three Divergent Legacy Label Vocabularies (`LBL-001`):** In the legacy system, bucket requests, Spanner requests, and project-vending calls used three inconsistent label vocabularies (e.g., `storage_bucket_primarylob` vs. `primarylob`, `provisioned_by` vs. `provisionedby`, or copying raw project labels onto Spanner instances while dropping `datasensitivity` and `owner`). `LBL-001` replaces all three with a single canonical label set computed at the `Approved` gate for every labelable resource kind ("Mandatory labels merged with user labels; one key set for every kind.").
2. **Cloud Asset Inventory Correlation via `idp_resource_id`:** Every labelable resource receives `idp_resource_id = <resource.resource_id>` (the deterministic UUID in `idp.resource`), allowing GCP Cloud Asset Inventory scans (`observation.source = 'asset_inventory'`) to map any cloud resource directly back to its `idp.resource` row and detect `unmanaged_in_cloud` drift.
3. **Label Value Normalization (`LBL-002`) & Intake Normalization:** GCP resource labels only allow lowercase letters, digits, underscores, and hyphens (`^[a-z0-9_-]{0,63}$`). Emails (`bucket.owner@example.com`, `<lob>-orders-team@example.com`) or display strings (`SPP-Orders Team`) must have `@`, `.`, and spaces replaced with `_` at the `Approved` gate, while intake normalizes raw form values (`"restrict" -> "restricted"`, `"APM0017299" -> "apm0017299"`, `"<LOB>" -> "<lob>"`).
4. **User Override — Dropping `environmentsubtype` Everywhere:** Because SPP has exactly two environments (`nonprod` and `prod`), the source's `environmentsubtype` label is **dropped entirely everywhere**, and `environmenttype` carries `nonprod` | `prod` (`8` mandatory labels total).

## Decision

### 1. Canonical Label Set (`LBL-001` — 8 Mandatory Labels + Metadata-Derived Labels)

At the `Approved` gate, rule `LBL-001` computes and merges the **8 mandatory labels** (plus metadata-derived `dataclassification`, `sharedemailaddress`, `tenancy`) with user-supplied `metadata.labels` (such as `app: "orders"`):

| Canonical Label Key | Requirement | Source / Derivation in SPP | Example Value |
| :--- | :--- | :--- | :--- |
| **`sppappid`** | **Mandatory (1/8)** | `metadata.apm_id` (normalized lowercase `^apm[0-9]{7}$`) | `apm0017299` |
| **`costcenter`** | **Mandatory (2/8)** | `metadata.cost_center` | `000000` |
| **`environmenttype`** | **Mandatory (3/8)** | Resolved environment (`nonprod` or `prod` only; `environmentsubtype` is dropped) | `nonprod` |
| **`primarylob`** | **Mandatory (4/8)** | `metadata.lob` (lowercased) | `<lob>` |
| **`datasensitivity`** | **Mandatory (5/8)** | `metadata.data_sensitivity` (normalized, e.g., `"restrict"` → `"restricted"`, `"unrestricted"`) | `restricted` |
| **`owner`** | **Mandatory (6/8)** | `metadata.owner` (normalized via `LBL-002`: `@` and `.` → `_`) | `bucket_owner_example_com` |
| **`provisionedby`** | **Mandatory (7/8)** | Constant `"idp"` | `idp` |
| **`idp_resource_id`** | **Mandatory (8/8)** | `idp.resource.resource_id` (UUID string) | `9478bcfc-c2cf-583b-8bd8-096476647840` |
| **`dataclassification`** | Metadata-derived | `metadata.data_classification` (e.g., `proprietary`) | `proprietary` |
| **`sharedemailaddress`** | Metadata-derived | `metadata.shared_mailbox` (normalized via `LBL-002`) | `<lob>-orders-team_example_com` |
| **`tenancy`** | Metadata-derived | `metadata.tenancy` (`dedicated` or `shared`) | `dedicated` |
| **`idp_naming`** | Conditional (`NAM-LEG-001`) | Added with value `"legacy"` when `action = "import"` keeps a non-standard legacy name | `legacy` |

### 2. Label Key Style & Value Normalization Rules (`LBL-002`)

1. **Key Style & Pattern:**
   - Existing enterprise keys keep their lowercase run-together form (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `dataclassification`, `sharedemailaddress`, `provisionedby`).
   - New platform-specific keys are prefixed with `idp_` (`idp_resource_id`, `idp_naming`).
   - All label keys MUST match `^[a-z][a-z0-9_-]{0,62}$`.
2. **Value Normalization (`LBL-002`):**
   - `lowercase`: `true` (convert all uppercase ASCII characters to lowercase).
   - `replace_pattern`: `[^a-z0-9_-]` replaced with `"_"` (e.g., `@` and `.` in email addresses become `_`; spaces become `_`; hyphens `-` are preserved).
   - `max_length`: `63` characters (values longer than 63 characters are truncated to 63 characters).
   - `drop_empty`: `true` (empty string label values are dropped).
   - **Normalization Test Vectors:**
     - `"bucket.owner@example.com"` → `"bucket_owner_example_com"`
     - `"<lob>-orders-team@example.com"` → `"<lob>-orders-team_example_com"`
     - `"SPP-Orders Team"` → `"spp-orders_team"`
     - `70+` character string → truncated to `63` characters
3. **Guardrail Trace Recording (`LBL-001` & `LBL-002`):**
   ```json
   {
     "rule_id": "LBL-001",
     "path": "/metadata/labels",
     "from": { "app": "orders" },
     "to": {
       "app": "orders",
       "costcenter": "000000",
       "dataclassification": "proprietary",
       "datasensitivity": "restricted",
       "environmenttype": "nonprod",
       "idp_resource_id": "9478bcfc-c2cf-583b-8bd8-096476647840",
       "owner": "bucket_owner_example_com",
       "primarylob": "<lob>",
       "provisionedby": "idp",
       "sharedemailaddress": "<lob>-orders-team_example_com",
       "sppappid": "apm0017299",
       "tenancy": "dedicated"
     },
     "reason": "Mandatory labels merged with user labels; one key set for every kind."
   }
   ```

### 3. Resource-Kind Label Applicability & Drift Comparison

- **Labelable Kinds (`gcs_bucket`, `spanner_instance`):** Carry the full canonical `labels` map in `terraform.tfvars.json` and `resource_observed.projection`.
- **Non-Labelable Kinds (`spanner_database`):** In GCP, Cloud Spanner databases do not support GCP labels—only Spanner instances do (`Spanner quirk #1`). Therefore, `spanner_database` tfvars entries omit `labels`, while `idp.resource` in AlloyDB tracks the database's `apm_id`, `resource_id`, and `owner` in the registry.
- **Whole-Map Drift Comparison:** During `Expected` vs. `Observed` comparison (`ADR-AUT-002`), `labels` is compared as a whole map; any label removed or altered out of band in the GCP Console produces a `low` severity `idp.drift_finding` row.

## Requirements

- **REQ-1 (MUST):** At the `Approved` gate, `ssp-cp` MUST apply `LBL-001` to every labelable resource kind (`gcs_bucket`, `spanner_instance`), ensuring all **8 mandatory labels** (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`) are present and non-empty, with `environmenttype` in `{"nonprod", "prod"}`.
- **REQ-2 (MUST):** `ssp-cp` and all Terraform modules MUST NOT emit the legacy `environmentsubtype` label key.
- **REQ-3 (MUST):** `ssp-cp` MUST normalize all label values via `LBL-002` (lowercase, replace `[^a-z0-9_-]` with `_`, truncate to `63` chars, drop empty values) and record `LBL-001` / `LBL-002` mutations in `idp.approval.guardrail_trace`.
- **REQ-4 (MUST):** `idp_resource_id` MUST equal the resource's `idp.resource.resource_id` UUID so Cloud Asset Inventory scans can join cloud resources back to `idp.resource`.
- **REQ-5 (MUST):** When `action = "import"` imports a resource whose name does not match the 2.0 naming template (`NAM-LEG-001`), `ssp-cp` MUST inject `idp_naming = "legacy"` into the resource's labels.
- **REQ-6 (MUST):** `spanner_database` resources MUST NOT emit a `labels` attribute in `terraform.tfvars.json`; ownership and `apm_id` for Spanner databases MUST be tracked in `idp.resource`.

## Guardrails

- **GR-1:** Never provision a labelable GCP resource without the 8 mandatory labels defined in `LBL-001`.
- **GR-2:** Never emit `environmentsubtype` or copy raw GCP project labels as a substitute for computing `LBL-001` from the request's `metadata`.
- **GR-3:** Never place secrets, credentials, or unnormalized email symbols (`@`, `.`) in GCP label values.

## Consequences

### Positive

- Unifies billing (`costcenter`, `sppappid`, `primarylob`), data governance (`datasensitivity`, `dataclassification`), environment (`environmenttype` = `nonprod` | `prod`), ownership (`owner`, `sharedemailaddress`), and Cloud Asset Inventory reconciliation (`idp_resource_id`) under one schema across all GCP resource types without redundant sub-environment labels.

### Negative / Trade-offs

- Existing dashboards or queries that filtered on legacy inconsistent label names must use the canonical keys (`provisionedby`, `primarylob`, `environmenttype`).

## Acceptance Criteria

- [ ] `specs/naming/naming-spec.json` includes the 8 mandatory labels (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`) with `environmentsubtype` removed.
- [ ] `ssp-cp` implements `LBL-001` and `LBL-002` enrichment and passes the normalization test vectors (`bucket.owner@example.com` → `bucket_owner_example_com`, `SPP-Orders Team` → `spp-orders_team`, 70-char truncation to 63).
- [ ] `ssp-module-gcs-bucket` and `ssp-module-spanner` apply the rendered `labels` map on `google_storage_bucket` and `google_spanner_instance`.

## Success Criteria

- **SC-1:**
  - **Given** a `gcs_bucket` or `spanner_instance` request with `owner = "bucket.owner@example.com"`, `shared_mailbox = "<lob>-orders-team@example.com"`, `apm_id = "apm0017299"`, and `metadata.labels = {"app": "orders"}`
  - **When** enriched at the `Approved` gate
  - **Then** `LBL-001` and `LBL-002` produce the 8 mandatory labels plus metadata-derived labels (`owner = "bucket_owner_example_com"`, `sharedemailaddress = "<lob>-orders-team_example_com"`, `environmenttype = "nonprod"`, `sppappid = "apm0017299"`, `provisionedby = "idp"`, `idp_resource_id = "<resource_id>"`, with no `environmentsubtype`), and record the mutation in `approval.guardrail_trace`.
- **SC-2:**
  - **Given** a `spanner_database` request
  - **When** rendered into `expected/rev-NNNNNN/terraform.tfvars.json`
  - **Then** the `spanner_databases` entry contains no `labels` key, while `idp.resource` in AlloyDB records `apm_id` and `resource_id`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-GLB-008` and the `labels` section of `specs/naming/naming-spec.json` |
| `ssp-cp` | Implements `LBL-001` / `LBL-002` enrichment, normalization, and `guardrail_trace` recording |
| `ssp-workers` | Compares `labels` as a whole map in drift detection (`low` severity on drift) and correlates `idp_resource_id` |
| `ssp-ui` | Displays normalized labels and `guardrail_trace` explanations |
| `ssp-module-gcs-bucket`, `ssp-module-spanner` | Applies authoritative `labels` map to buckets and Spanner instances |
| `spp-factory-foundation` | Validates `LBL-001` and `LBL-002` test vectors in `gates/` |

## Open Questions

- [x] **OQ-1 (Drop `environmentsubtype` Label — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* `environmentsubtype` is dropped everywhere; `environmenttype` is `nonprod` | `prod` (8 mandatory labels).
- [x] **OQ-2 (Legacy Portal Field Mapping — OUT OF SCOPE / DEFERRED 2026-10-21):** *Resolved:* Legacy portal field-mapping tables are out of scope and skipped per user decision.

## Related ADRs

- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](../endpoint-service/ADR-SVC-002-spanner-instance-and-database.md)
