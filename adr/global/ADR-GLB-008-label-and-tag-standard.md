# ADR-GLB-008: Label and Tag Standard

- **ADR ID:** ADR-GLB-008
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define a unified, canonical label standard (`LBL-001`, `LBL-002`) across all GCP resource kinds managed by SPP—including mandatory label keys (`sppappid`, `costcenter`, `environmenttype`, `environmentsubtype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`), key/value normalization rules, `guardrail_trace` recording, Cloud Asset Inventory mapping via `idp_resource_id`, and Spanner database label-exclusion handling.

## Context

From the sanitized four-gate design package (`labels.md`, `naming.md`, `raw/naming-spec.reconstructed.json`, `gates.md`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)) and user overrides:

1. **Replacing Three Divergent Legacy Label Vocabularies (`LBL-001`):** In the legacy system, bucket requests, Spanner requests, and project-vending calls used three inconsistent label vocabularies (e.g., `storage_bucket_primarylob` vs. `primarylob`, `provisioned_by` vs. `provisionedby`, or copying raw project labels onto Spanner instances while dropping `datasensitivity` and `owner`). `LBL-001` replaces all three with a single canonical label set computed at the `Approved` gate for every labelable resource kind.
2. **Cloud Asset Inventory Correlation via `idp_resource_id`:** Every labelable resource receives `idp_resource_id = <resource.resource_id>` (the deterministic UUID in `idp.resource`), allowing GCP Cloud Asset Inventory scans (`observation.source = 'asset_inventory'`) to map any cloud resource directly back to its `idp.resource` row and detect `unmanaged_in_cloud` drift.
3. **Label Value Normalization (`LBL-002`):** GCP resource labels only allow lowercase letters, digits, underscores, and hyphens (`^[a-z0-9_-]{0,63}$`). Emails (`bucket.owner@example.com`) or display strings (`SPP-Orders Team`) must be deterministically normalized at the `Approved` gate and recorded in `approval.guardrail_trace`.
4. **Two-Environment Override (`nonprod` and `prod`):** Both `environmenttype` and `environmentsubtype` normalize non-production environments (`sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`) to `nonprod` (no hyphen), and production to `prod`.

## Decision

### 1. Canonical Label Set (`LBL-001`)

At the `Approved` gate, rule `LBL-001` computes and merges the mandatory label set with user-supplied `metadata.labels` (such as `app: "orders"`):

| Canonical Label Key | Required | Source / Derivation in SPP | Example Value | Legacy Bucket Key (Deferred Note) | Legacy Spanner Key (Deferred Note) | Legacy Project Call (Deferred Note) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`sppappid`** | **Mandatory** | `metadata.apm_id` (`^apm[0-9]{7}$`) *(sanitized form of enterprise app-id label key)* | `apm0017299` | `<co>appid` | `<co>appid` | `<co>appid` |
| **`costcenter`** | **Mandatory** | `metadata.cost_center` | `000000` | `costcenter` | `costcenter` | `costCenter` (body field) |
| **`environmenttype`** | **Mandatory** | Resolved environment (`nonprod` or `prod`) | `nonprod` | `environmenttype` | `environmenttype` | `environmenttype` |
| **`environmentsubtype`** | **Mandatory** | Normalized environment (`nonprod` or `prod` per SPP two-env override) | `nonprod` | `environmentsubtype` | `environmentsubtype` | `projectenvironment` |
| **`primarylob`** | **Mandatory** | `metadata.lob` (lowercased) | `<lob>` | `storage_bucket_primarylob` | *(missing in legacy)* | `primarylob` |
| **`datasensitivity`** | **Mandatory** | `metadata.data_sensitivity` (e.g., `restricted`, `unrestricted`) | `restricted` | `storage_bucket_data_sensitivity` | *(missing in legacy)* | *(missing in legacy)* |
| **`owner`** | **Mandatory** | `metadata.owner` (normalized via `LBL-002`) | `bucket_owner_example_com` | `bucket_owner` | *(missing in legacy)* | *(missing in legacy)* |
| **`provisionedby`** | **Mandatory** | Constant `"idp"` | `idp` | `provisioned_by` | *(missing in legacy)* | `provisionedby` |
| **`idp_resource_id`** | **Mandatory** | `idp.resource.resource_id` (UUID string) | `9478bcfc-c2cf-583b-8bd8-096476647840` | *(none)* | *(none)* | *(none)* |
| **`dataclassification`** | Optional / Metadata-derived | `metadata.data_classification` (e.g., `proprietary`) | `proprietary` | `dataclassification` | `dataclassification` | — |
| **`sharedemailaddress`** | Optional / Metadata-derived | `metadata.shared_mailbox` (normalized via `LBL-002`) | `orders-team_example_com` | `sharedemailaddress` | `sharedemailaddress` | `sharedEmailAddress` (body field) |
| **`tenancy`** | Optional / Metadata-derived | `metadata.tenancy` (`dedicated` or `shared`) | `dedicated` | — | — | — |
| **`idp_naming`** | Conditional (`NAM-LEG-001`) | Added with value `"legacy"` when `action = "import"` keeps a non-standard legacy name | `legacy` | — | — | — |

### 2. Label Key Style & Value Normalization Rules (`LBL-002`)

1. **Key Style & Pattern:**
   - Existing enterprise keys keep their lowercase run-together form (`sppappid`, `costcenter`, `environmenttype`, `environmentsubtype`, `primarylob`, `datasensitivity`, `dataclassification`, `sharedemailaddress`, `provisionedby`).
   - New platform-specific keys are prefixed with `idp_` (`idp_resource_id`, `idp_naming`).
   - All label keys MUST match `^[a-z][a-z0-9_-]{0,62}$`.
2. **Value Normalization (`LBL-002`):**
   - `lowercase`: `true` (convert all uppercase ASCII characters to lowercase).
   - `replace_pattern`: `[^a-z0-9_-]` replaced with `"_"` (e.g., `@` and `.` in email addresses become `_`; spaces become `_`; hyphens `-` are preserved).
   - `max_length`: `63` characters (values longer than 63 characters are truncated to 63 characters).
   - `drop_empty`: `true` (empty string label values are dropped).
   - **Normalization Test Vectors:**
     - `"bucket.owner@example.com"` → `"bucket_owner_example_com"`
     - `"orders-team@example.com"` → `"orders-team_example_com"`
     - `"SPP-Orders Team"` → `"spp-orders_team"`
     - `70+` character string → truncated to `63` characters
3. **Guardrail Trace Recording:**
   - Both `LBL-001` (merging mandatory labels over `metadata.labels`) and `LBL-002` (normalizing user or metadata values) record entries in `idp.approval.guardrail_trace`:
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
         "environmentsubtype": "nonprod",
         "environmenttype": "nonprod",
         "idp_resource_id": "9478bcfc-c2cf-583b-8bd8-096476647840",
         "owner": "bucket_owner_example_com",
         "primarylob": "<lob>",
         "provisionedby": "idp",
         "sharedemailaddress": "orders-team_example_com",
         "sppappid": "apm0017299",
         "tenancy": "dedicated"
       },
       "reason": "Mandatory labels merged (legacy copied project labels instead)."
     }
     ```

### 3. Resource-Kind Label Applicability & Drift Comparison

- **Labelable Kinds (`gcs_bucket`, `spanner_instance`):** Carry the full canonical `labels` map in `terraform.tfvars.json` and `resource_observed.projection`.
- **Non-Labelable Kinds (`spanner_database`):** In GCP, Cloud Spanner databases do not support GCP labels—only Spanner instances do (`Spanner quirk #1`). Therefore, `spanner_database` tfvars entries omit `labels`, while `idp.resource` in AlloyDB tracks the database's `apm_id`, `resource_id`, and `owner` in the registry.
- **Whole-Map Drift Comparison:** During `Expected` vs. `Observed` comparison (`ADR-AUT-002`), `labels` is compared as a whole map; any label removed or altered out of band in the GCP Console produces a `low` severity `idp.drift_finding` row.

## Requirements

- **REQ-1 (MUST):** At the `Approved` gate, `ssp-cp` MUST apply `LBL-001` to every labelable resource kind (`gcs_bucket`, `spanner_instance`), ensuring all 9 mandatory labels (`sppappid`, `costcenter`, `environmenttype`, `environmentsubtype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`) are present and non-empty.
- **REQ-2 (MUST):** `ssp-cp` MUST normalize all label values via `LBL-002` (lowercase, replace `[^a-z0-9_-]` with `_`, truncate to `63` chars, drop empty values) and record `LBL-001` / `LBL-002` mutations in `idp.approval.guardrail_trace`.
- **REQ-3 (MUST):** `idp_resource_id` MUST equal the resource's `idp.resource.resource_id` UUID so Cloud Asset Inventory scans can join cloud resources back to `idp.resource`.
- **REQ-4 (MUST):** When `action = "import"` imports a resource whose name does not match the 2.0 naming template (`NAM-LEG-001`), `ssp-cp` MUST inject `idp_naming = "legacy"` into the resource's labels.
- **REQ-5 (MUST):** `spanner_database` resources MUST NOT emit a `labels` attribute in `terraform.tfvars.json`; ownership and `apm_id` for Spanner databases MUST be tracked in `idp.resource`.

## Guardrails

- **GR-1:** Never provision a labelable GCP resource without the 9 mandatory labels defined in `LBL-001`.
- **GR-2:** Never copy raw GCP project labels as a substitute for computing `LBL-001` from the request's `metadata`.
- **GR-3:** Never place secrets, credentials, or unnormalized email symbols (`@`, `.`) in GCP label values.

## Consequences

### Positive

- Unifies billing (`costcenter`, `sppappid`, `primarylob`), data governance (`datasensitivity`, `dataclassification`), ownership (`owner`, `sharedemailaddress`), and Cloud Asset Inventory reconciliation (`idp_resource_id`) under one schema across all GCP resource types.

### Negative / Trade-offs

- Existing dashboards or queries that filtered on legacy inconsistent label names (e.g., `provisioned_by` with an underscore or `storage_bucket_primarylob`) must use the canonical keys (`provisionedby`, `primarylob`).

## Acceptance Criteria

- [ ] `specs/naming/naming-spec.json` includes the `labels` block (`mandatory`, `key_pattern`, `value_normalization`, `legacy_marker`) and `LBL-001`/`LBL-002` rules.
- [ ] `ssp-cp` implements `LBL-001` and `LBL-002` enrichment and passes the normalization test vectors (`bucket.owner@example.com` → `bucket_owner_example_com`, `SPP-Orders Team` → `spp-orders_team`, 70-char truncation to 63).
- [ ] `ssp-module-gcs-bucket` and `ssp-module-spanner` apply the rendered `labels` map on `google_storage_bucket` and `google_spanner_instance`.

## Success Criteria

- **SC-1:**
  - **Given** a `gcs_bucket` or `spanner_instance` request with `owner = "bucket.owner@example.com"`, `shared_mailbox = "orders-team@example.com"`, `apm_id = "apm0017299"`, and `metadata.labels = {"app": "orders"}`
  - **When** enriched at the `Approved` gate
  - **Then** `LBL-001` and `LBL-002` produce `owner = "bucket_owner_example_com"`, `sharedemailaddress = "orders-team_example_com"`, `sppappid = "apm0017299"`, `provisionedby = "idp"`, `idp_resource_id = "<resource_id>"`, and record the mutation in `approval.guardrail_trace`.
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

- [x] **OQ-1 (Legacy Portal Field Mapping — OUT OF SCOPE / DEFERRED 2026-10-21):** *Resolved:* Legacy portal field-mapping tables (`labels.md` §8, where rows 368–378 for `metadata.cost_center` were `[NOT CAPTURED]`) are out of scope for now per user decision and retained only as a deferred note in [`docs/source-provenance.md`](../../docs/source-provenance.md).

## Related ADRs

- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](../endpoint-service/ADR-SVC-002-spanner-instance-and-database.md)
