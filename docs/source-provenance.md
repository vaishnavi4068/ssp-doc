# Source Provenance, Overrides, and Unverified Source Gaps (`docs/source-provenance.md`)

This document records the provenance of the four-gate data model, naming specification, guardrail rules, and GCS bucket / Cloud Spanner specifications incorporated into `ssp-doc`, including:
1. What the two source photo bundles (`bundle.zip` and `gcs-bundle.zip`) contained and how they were captured.
2. What earlier gaps `gcs-bundle.zip` filled by example vs. what files and line ranges remain uncaptured or truncated (**Unverified (source gap)**).
3. Every locked **SPP user decision that overrides the source**.
4. Sanitization rules applied so the repository remains 100% free of enterprise/company/product names.
5. Deferred / out-of-scope items.

---

## 1. Source Provenance (Hand Transcription from 87 Photographs Across Two Bundles)

### 1.1 Bundle 1 (`bundle.zip` — 70 HEIC Photos `IMG_6522..6592`, `IMG_6569` Missing)
- Phone photographs of a monitor displaying an editor with the design package **"IDP four-gate data model: GCS bucket and Spanner"** (draft dated 21 Oct 2026):
  - `README_2.md` (`IMG_6522..6533`) — Architectural overview of the four-gate state model, GCS bucket and Spanner gate walkthroughs, legacy mapping tables, invariants `INV-1..INV-9`, identifiers/hashing, and open decisions.
  - `idp_state_model.sql` (`IMG_6534..6547`) — PostgreSQL DDL for schema `idp` (tables, immutability triggers, `v_resource_status` view, and seed rows for `approval_gate_config` and `resource_kind`).
  - Package file tree (`IMG_6548`).
  - `examples/spanner.gates.json` (`IMG_6549..6572`, `IMG_6569` missing) — End-to-end Spanner instance + database example across all four gates, DB rows, `guardrail_trace`, and drift scenario.
  - Diagrams PDF (`IMG_6573..6575`) — Entity-Relationship diagram showing all 18 tables in schema `idp` (including `idp.apm_alias`) and the request/resource lifecycle state diagram.
  - `naming-spec.json` (`IMG_6576..6592`) — Naming templates, tokens, validation rules, label normalization rules, and platform identifier patterns.

### 1.2 Bundle 2 (`gcs-bundle.zip` — 17 HEIC Photos `IMG_6593..6600`, `IMG_6602..6610`, `IMG_6601` Missing)
- All 17 photos show **`examples/gcs_bucket.gates.json`** (~888 lines) in an editor (~85% line coverage):
  - **Captured line ranges:** `1-46`, `52-90`, `102-192`, `197-239`, `244-287`, `291-331`, `336-383`, `429-519`, `521-561`, `567-609`, `604-650`, `~650-689`, `689-733`, `736-777`, `765-788`.
  - **Uncaptured line ranges:** `~47-51`, `91-101`, `145-149`, `193-196`, `240-243`, `288-290`, `332-335`, `384-428`, `562-566`, `650-655` (`resource_observed` tail), `788-888` (end of file).
- **What Bundle 2 (`gcs-bundle.zip`) Newly Confirmed / Filled:**
  1. **`examples/gcs_bucket.gates.json` (~85% coverage):** Reconstructed in [`specs/examples/gcs_bucket.gates.json`](../specs/examples/gcs_bucket.gates.json) with all four gates (`submission`, `requested`, `approved`, `expected`, `observed`) and the `drift_example` (`public_access_prevention` switched to `"inherited"` → `severity = "critical"`, `guardrail_rule_id = "GCS-PAP-001"`, `status = "OPEN"`).
  2. **New Guardrail Rule `GCS-RET-003`:** `/spec/retention_locked`: `null -> false` (`"Locks are irreversible and only applied on an explicit records-management request."`).
  3. **`gcs_bucket` Kind Registry Fields Confirmed by Example:** Confirmed `tfvars_collection = "gcs_buckets"` and `tf_address_template = 'module.gcs_bucket["{name}"]'` (via `expected_revision_member.tf_address = "module.gcs_bucket[\"<lob>-nonprod-orders-landing-a1b2\"]"`).
  4. **Intake Value Normalization Confirmed:** Form `"restrict"` → canonical `"restricted"`, `"APM0017299"` → `"apm0017299"`, `"<LOB>"` → `"<lob>"`.
  5. **DDL Columns Confirmed by Example Rows (while SQL types/CHECK constraints remain inferred):**
     - `idp.drift_finding` columns: `drift_id`, `resource_id`, `observation_id`, `revision_id`, `drift_kind`, `attribute_path`, `expected_value`, `observed_value`, `severity`, `guardrail_rule_id`, `status`, `detected_at`.
     - `idp.tf_operation` tail fields: `tf_exit_code`, `state_serial_before`, `state_serial_after`, `state_lineage`, `logs_uri`, `started_at`, `finished_at` (across phases `plan`, `apply`, `refresh_plan`).
     - `idp.expected_revision` tail fields: `artifact_uri`, `artifact_generation`, `status` (`"APPLIED"`), `plan_summary` (`{"add": 3, "change": 0, "destroy": 0, "replace": 0}`).
     - `idp.approval` row fields: `approval_id`, `request_id`, `resource_id`, `gate_key` (`"gcs_bucket_owner"`), `gate_version` (`1`), `status` (`"APPROVED"`), `approved_spec_sha256`, `guardrail_trace`.
     - `idp.observation` & `idp.resource_observed` upsert-on-change behavior: confirmed `source` (`"post_apply"` | `"refresh_plan"`), `snapshot_uri`, `drift_detected`, `cloud_resource_id = "projects/_/buckets/<bucket>"`, and the `_note`: *"The rev-000002 apply re-observes this bucket, finds the same projection hash and writes nothing (upsert-on-change)."*

---

## 2. User Decisions That OVERRIDE the Source (Applied Everywhere)

Where the photographed design package conflicted with locked SPP decisions or contained open decisions, the following **user decisions override the source everywhere** (across all ADRs and `specs/`):

| # | Area | Source Package Content | Locked SPP Override Applied Everywhere | Affected ADRs & Specs |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Cloud & Region Scope** | `cloud CHECK (cloud IN ('gcp', 'aws', 'azure'))`; bucket `"location": "US"` (multi-region); Spanner nonprod `regional-us-east4` and Tier 1/prod multi-region `nam3` (active-active); KMS keys in `us` / `us-east4`. | **GCP only (`cloud IN ('gcp')`); region `us-east1` only, no multi-region** (not `US` multi-region buckets, not `nam3` Spanner, not `us-east4`), **prod included** (`location = "us-east1"`, `config = "regional-us-east1"`, KMS keys in `locations/us-east1`). | `ADR-GLB-001`, `ADR-GLB-004`, `ADR-GLB-006`, `ADR-GLB-007`, `ADR-GLB-009`, `ADR-SVC-001`, `ADR-SVC-002`, `specs/*` |
| **2** | **Control Plane Database** | Header in `idp_state_model.sql`: `Target: PostgreSQL 15+ (Cloud SQL for PostgreSQL in the GCP control-plane project)`. | **Google Cloud AlloyDB for PostgreSQL** (`spp_platform` in `microdrive-dev`, `us-east1`) — **not Cloud SQL**. All DDL constructs are AlloyDB-compatible. | `ADR-GLB-003`, `ADR-GLB-004`, `specs/data-model/spp_state_model.sql` |
| **3** | **Four-Gate Storage & `<= 2 KB` Projections** | `Requested` and `Approved` in full in Postgres; `Expected` and `Observed` in GCS; Postgres holds pointers, hashes, `< 2000`-byte `resource_observed.projection`, and `drift_finding` rows. | **Confirmed:** `Requested` and `Approved` in AlloyDB Postgres (zero secrets); `Expected` and `Observed` in GCS; short non-sensitive observed-state projections (`<= 2 KB` / `< 2000` bytes) and `drift_finding` summaries in Postgres are explicitly allowed. | `ADR-GLB-003`, `ADR-GLB-004`, `specs/data-model/spp_state_model.sql` |
| **4** | **Environment Taxonomy & Dropping `environmentsubtype`** | 8 environment codes (`sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`, `prod`); source used `environmenttype` + `environmentsubtype` labels and treated `pdev`/`pqa`/`preprod` as prod-like in Spanner `dbaas_reviewer` skip rule. | **Only `nonprod` and `prod`; name token is `nonprod` (no hyphen).** `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, and `preprod` **all map to `nonprod` everywhere** (including the Spanner `dbaas_reviewer` skip rule). **The `environmentsubtype` label is DROPPED entirely everywhere**, leaving `environmenttype` (`nonprod`\|`prod`) and **8 mandatory labels**. | `ADR-GLB-006`, `ADR-GLB-007`, `ADR-GLB-008`, `ADR-BP-003`, `ADR-SVC-001`, `ADR-SVC-002`, `specs/*` |
| **5** | **Single State Bucket Retaining Folder Layout** | Per-LOB state buckets (`gs://idp-tfstate-<lob>/projects/<project_id>/{expected/rev-N,logs,observed/scan-*,default.tfstate}`). | **Single state bucket `gs://microdrive-dev-spp-tfstate` for now** (no per-LOB buckets), keeping the folder layout **`projects/<project>/{expected/rev-N, logs, observed/scan-*, default.tfstate}`** inside `gs://microdrive-dev-spp-tfstate`. | `ADR-GLB-003`, `ADR-GLB-004`, `ADR-GLB-006`, `ADR-AUT-001`, `ADR-SVC-001`, `specs/*` |
| **6** | **Object Lifecycle Rules vs. Bucket Deletion** | `gcs_bucket.gates.json` included a default 365-day object auto-delete rule (`{"action": {"type": "Delete"}, "condition": {"age_days": 365, "with_state": "ANY"}}`). | **Object `lifecycle_rules` default to NONE (`[]`)** (365-day auto-delete default removed) and are exposed as **optional user-configurable options** on the `gcs_bucket` request (e.g., delete objects after `N` days, transition storage class after `N` days, delete noncurrent versions after `N` days), validated by policy at request time and approved through the normal `gcs_bucket_owner` approval gate. **Bucket resource deletion (`action = 'delete'`) still always requires explicit human approval in ANY environment (`nonprod` or `prod`); no `AUTO_APPROVED` for deletes.** | `ADR-GLB-004`, `ADR-GLB-007`, `ADR-BP-003`, `ADR-AUT-002`, `ADR-SVC-001`, `specs/examples/gcs_bucket.gates.json` |
| **7** | **Drift Response** | Open decision leaning toward "Auto-reapply critical guardrail drift (PAP, UBLA, CMEK, public IAM) after notifying the owner"; `drift_finding.status` included `REMEDIATING` and `resolution` included `'reapplied'`. | **Drift is alert-only, never auto-reapply.** `REMEDIATING` and `'reapplied'` are removed; remediation always goes through a new human-approved request. | `ADR-GLB-004`, `ADR-GLB-007`, `ADR-AUT-002`, `ADR-SVC-001`, `specs/*` |
| **8** | **Terraform Runner Execution** | One Kubernetes Job per run (`tf-<phase>-<20hex>`) in K8s namespace `idp-runners`. | **One Kubernetes Job per run (`tf-<phase>-<20hex>`) in K8s namespace `spp-platform`** on tainted node pool `spp-pool` (`ADR-AUT-001`, `ADR-CLD-GCP-001`). | `ADR-AUT-001`, `ADR-GLB-006`, `ADR-SVC-001`, `specs/*` |
| **9** | **Out-of-Scope Items** | Multi-cloud (`aws`, `azure`), UI details, ITSM/CMDB (`cmdb_register`), data-portal registration (`dataportal_register`), external group-provisioning provider details, legacy portal shim/FormData/legacy-equivalent section. | **Out of scope and skipped:** AWS/Azure, UI, ServiceNow/CMDB (`cmdb_register`), data-portal registration (`dataportal_register`), legacy shim/form/legacy-equivalent section, and group-provisioning provider details. | All ADRs, `specs/*`, `docs/source-provenance.md` |

---

## 3. Complete Catalog of Remaining Unverified Source Gaps (`[NOT CAPTURED]`, `[truncated]`, `inferred`)

Every item below was either not photographed or cut off in the source photos across Bundles 1 and 2 and remains flagged as **`Unverified (source gap)`**:

### 3.1 Entire Files Visible in Package File Tree (`IMG_6548`) Still Not Photographed

1. **`schemas/idp-common.schema.json`** — Shared JSON Schema Draft 2020-12 definitions (metadata, labels, IAM members, KMS keys, lifecycle tasks).
2. **`schemas/gcs_bucket.schema.json`** — Bucket JSON Schema at each gate (`requested`, `approved`, `expected`, `observed`).
3. **`schemas/spanner.schema.json`** — Spanner instance + database JSON Schema at each gate (including `if/then` edition rules).
4. **`schemas/project-expected.schema.json`** — Project-level `terraform.tfvars.json` and revision `manifest.json` JSON Schemas.
5. **`examples/resource_kinds.json`** — JSON file mirroring `idp.resource_kind` seed rows.
6. **`examples/expected/rev-000002/manifest.json`** and **`examples/expected/rev-000002/terraform.tfvars.json`** — Composed project-level revision artifacts (referenced in `gcs_bucket.gates.json` and `spanner.gates.json`, but the files themselves were not photographed).
7. **`tools/validate_examples.py`** — Python stdlib validation script running 49 mechanical checks (schema validation, `Requested -> Expected` hash chain, drift comparer verification, `k8s_job_name` derivation).
8. **`naming-spec.md`** and **`README.md` (v1)** — Narrative companion files (`naming-spec.json` and `README_2.md` were photographed instead).
9. **Missing Photo Numbers:** `IMG_6569` (in Bundle 1 `spanner.gates.json`) and `IMG_6601` (in Bundle 2 `gcs_bucket.gates.json`).

### 3.2 Uncaptured Line Ranges in `examples/gcs_bucket.gates.json` (`specs/examples/gcs_bucket.gates.json`)

- **Lines `~47-51`, `91-101`:** Portions of `submission.raw_payload.FormData` (legacy portal form; out of scope and skipped per user override).
- **Lines `145-149`:** Partial lines in `requested.document.spec.access` (`roles/storage.objectAdmin` member entry; full SA confirmed from `expected.entry.iam_bindings`).
- **Lines `193-196`, `240-243`:** Section transitions between `requested.db` / `approved.document`.
- **Lines `288-290`:** Partial lines in `approved.document.post_apply`.
- **Lines `332-335`:** `guardrail_trace` entry for `GCS-PAP-001` (`to: "enforced"` confirmed from `approved.document.spec.public_access_prevention`; verbatim `reason` string not captured).
- **Lines `384-428`:** Tail of `guardrail_trace` (including `PRQ-002` trace entry and whether `GCS-RET-002` exists) and head of `approved.db.lifecycle_task` (`pre_apply` rows for `ad_group` and `vpc_sc_ingress`, inferred from `approved.document.prerequisites`).
- **Lines `562-566`:** Tail of `tf_operations` `apply` entry (`state_serial_after`, inferred as `3` from `post_apply` `observation.state_serial = 3`).
- **Lines `650-655`:** Tail of `observed.db.resource_observed`.
- **Lines `788-888`:** End of file / `legacy_equivalent` tail (`legacy_equivalent` is out of scope and skipped per user override).

### 3.3 Uncaptured / Truncated Line Ranges in `idp_state_model.sql` (`specs/data-model/spp_state_model.sql`)

| Source Lines | Table / Object | Status After Bundle 2 (`gcs-bundle.zip`) |
| :--- | :--- | :--- |
| **Lines 47–52** | `idp.approval_gate_config` | Comment lines preceding `CREATE TABLE idp.approval_gate_config` (`[NOT CAPTURED]`). |
| **Lines 96–104** | `idp.state_unit` | Column definitions between `cloud` and `current_expected_rev` (`[NOT CAPTURED]` in SQL; `scope_type`, `scope_id`, `lob`, `environment`, `apm_id`, `state_bucket`, `state_prefix`, `executor_identity` reconstructed from `UNIQUE` constraints, column `COMMENT`s, and `idp.v_resource_status`). |
| **Line 148 & Lines 149–156** | `idp.resource` | Tail of `CREATE UNIQUE INDEX resource_gcs_bucket_name_uq ON idp.resource (name)` (`[NOT CAPTURED]`; reconstructed with `WHERE kind = 'gcs_bucket'`). |
| **Lines 205–209** | `idp.policy_evaluation` | Table header and `evaluation_id uuid PRIMARY KEY DEFAULT gen_random_uuid()` (`[NOT CAPTURED]` in SQL; inferred from FK in `idp.approval`). |
| **Lines 250–258** | `idp.approval` | **Partially filled by example:** `gcs_bucket.gates.json` and `spanner.gates.json` confirm the `approval` row fields (`approval_id`, `request_id`, `resource_id`, `gate_key`, `gate_version`, `status`, `approved_spec_sha256`, `guardrail_trace`, `temporal_workflow_id`, `decided_at`, `valid_until`); exact SQL `CHECK` expression for `approval_spec_when_approved` remains inferred. |
| **Lines 302–309** | `idp.expected_revision` | **Partially filled by example:** `gcs_bucket.gates.json` and `spanner.gates.json` confirm `artifact_uri`, `artifact_generation`, `status` (`"APPLIED"`), and `plan_summary` (`{add, change, destroy, replace}`); exact SQL column types, full `status` `CHECK` list, `blocked_reason`, and `UNIQUE (state_unit_id, revision_no)` remain inferred. |
| **Lines 356–362** | `idp.tf_operation` | **Filled by example:** `gcs_bucket.gates.json` confirms the `tf_operation` tail fields (`tf_exit_code`, `state_serial_before`, `state_serial_after`, `state_lineage`, `logs_uri`, `started_at`, `finished_at`) and phases (`plan`, `apply`, `refresh_plan`); any trailing SQL index in lines 356–362 remains inferred. |
| **Lines 408–411** | `idp.drift_finding` | **Column names filled by example:** `gcs_bucket.gates.json` and `spanner.gates.json` confirm columns `drift_id`, `resource_id`, `observation_id`, `revision_id`, `drift_kind`, `attribute_path`, `expected_value`, `observed_value`, `severity`, `guardrail_rule_id`, `status`, `detected_at`; exact SQL column types and `CHECK` constraints remain inferred. |
| **Lines 460–461** | `idp.gate_event` | Tail of `idp.gate_event` (`[NOT CAPTURED]`; `published_at timestamptz` reconstructed from `gate_event_unpublished_idx` and `gate_event_guard`). |
| **Lines 602 & 605** | `idp.v_resource_status` | `LEFT JOIN idp.approval ap ON ap.approval_id = r.current_approval_id` (line 602) and `FROM idp.expected_revision_member m` (line 605) (`[NOT CAPTURED]`; reconstructed from `SELECT` list and adjacent `JOIN`). |
| **Lines 649–652** | `idp.resource_kind` seed | **Partially filled by example:** `gcs_bucket.gates.json` confirms `tfvars_collection = 'gcs_buckets'` and `tf_address_template = 'module.gcs_bucket["{name}"]'` (and SQL photo showed tail `ARRAY['/force_destroy'], 'storage-bucket'`); `display_name`, `schema_uri`, `tf_module_source`, and `opa_package` remain inferred. |
| **18th Table** | `idp.apm_alias` | Shown on page 2 of the diagrams PDF (`IMG_6573..6575`) and referenced in `naming-spec.json` (`idp.apm_alias.alias for metadata.apm_id`), but not present in the captured `idp_state_model.sql` photos. |

### 3.4 Uncaptured / Truncated Sections in `naming-spec.json`, `README_2.md`, and `spanner.gates.json`

1. **`naming-spec.json` Lines 46–53 (`tokens.purpose.reserved`):** Additional reserved words after `"restricted", "unrestricted"` were `[NOT CAPTURED]`.
2. **`naming-spec.json` Lines 117–119 (`kinds.spanner_database.rules`):** Rule IDs after `"SPN-NAME-002"` were `[NOT CAPTURED]` (`"NAM-RSV-001"`, `"NAM-IMM-001"`, `"NAM-LEG-001"` inferred from `naming.md`).
3. **`README_2.md` §9 Invariants `INV-2..INV-4`:** The table rows for `INV-2`, `INV-3`, and the start of `INV-4` (ending with `...'plan'"); otherwise the revision becomes BLOCKED`) were `[NOT CAPTURED]` (`ADR-GLB-007 OQ-4`).
4. **`examples/spanner.gates.json` `initial_ddl` Tail:** The right edge of `CREATE TABLE orders (...)` was `[truncated]`.

---

## 4. Sanitization & Out-of-Scope Summary

- **Zero Company / Product Names:** All source company names, abbreviations, subsidiary names, and internal vendor/product names were replaced during transcription with `SPP`, `<lob>`, `example.com`, `sppappid`, and `idp.spp/v1`.
- **Skipped Out-of-Scope Sections:** Legacy portal shim/FormData, `legacy_equivalent` payloads, ServiceNow/CMDB (`cmdb_register`), data-portal registration (`dataportal_register`), and external group-provisioning provider details are out of scope for SPP and omitted from active specifications.
