# Source Provenance, Overrides, and Unverified Source Gaps (`docs/source-provenance.md`)

This document records the provenance of the four-gate data model, naming specification, guardrail rules, and GCS bucket / Cloud Spanner specifications incorporated into `ssp-doc`, including:
1. What the source bundle contained and how it was captured.
2. What files and line ranges were missing or truncated in the source photographs (**Unverified (source gap)**).
3. Every locked **SPP user decision that overrides the source**.
4. Sanitization rules applied so the repository remains 100% free of enterprise/company/product names.
5. Deferred / out-of-scope items.

---

## 1. Source Provenance (Hand Transcription from 70 Photographs)

- **Input Archive:** A sanitized hand transcription (`bundle.zip`) derived from 70 HEIC phone photographs (`IMG_6522..IMG_6592`, with `IMG_6569` missing) of a monitor displaying an editor with the design package **"IDP four-gate data model: GCS bucket and Spanner"** (draft dated 21 Oct 2026).
- **Photographed Artifacts:**
  - `README_2.md` (`IMG_6522..6533`) — Architectural overview of the four-gate state model, GCS bucket and Spanner gate walkthroughs, legacy mapping tables, invariants `INV-1..INV-9`, identifiers/hashing, and open decisions.
  - `idp_state_model.sql` (`IMG_6534..6547`) — PostgreSQL DDL for schema `idp` (tables, immutability triggers, `v_resource_status` view, and seed rows for `approval_gate_config` and `resource_kind`).
  - Package file tree (`IMG_6548`).
  - `examples/spanner.gates.json` (`IMG_6549..6572`) — End-to-end Spanner instance + database example across all four gates, DB rows, `guardrail_trace`, and drift scenario.
  - Diagrams PDF (`IMG_6573..6575`) — Entity-Relationship diagram showing all 18 tables in schema `idp` (including `idp.apm_alias`) and the request/resource lifecycle state diagram.
  - `naming-spec.json` (`IMG_6576..6592`) — Naming templates, tokens, validation rules, label normalization rules, and platform identifier patterns.
- **Transcription Fidelity Rule:** Nothing was invented. Any text cut off at the right edge of the monitor is marked `[truncated]`, any line range not photographed is marked `[NOT CAPTURED]`, and any reconstruction/inference from adjacent constraints or views is explicitly flagged as **`Unverified (source gap)`**.

---

## 2. User Decisions That OVERRIDE the Source (Applied Everywhere)

Where the photographed design package conflicted with locked SPP decisions or contained open decisions, the following **user decisions override the source everywhere** (across all ADRs and `specs/`):

| # | Area | Source Package Content | Locked SPP Override Applied Everywhere | Affected ADRs & Specs |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Cloud & Region Scope** | `cloud CHECK (cloud IN ('gcp', 'aws', 'azure'))`; bucket `"location": "US"` (multi-region); Spanner nonprod `regional-us-east4` and Tier 1/prod multi-region `nam3` (active-active); KMS keys in `us` / `us-east4`. | **GCP only (`cloud IN ('gcp')`); region `us-east1` only, no multi-region** (not `US` multi-region buckets, not `nam3` Spanner, not `us-east4`), **prod included** (`location = "us-east1"`, `config = "regional-us-east1"`, KMS keys in `locations/us-east1`). | `ADR-GLB-001`, `ADR-GLB-004`, `ADR-GLB-006`, `ADR-GLB-007`, `ADR-GLB-009`, `ADR-SVC-001`, `ADR-SVC-002`, `specs/*` |
| **2** | **Control Plane Database** | Header in `idp_state_model.sql`: `Target: PostgreSQL 15+ (Cloud SQL for PostgreSQL in the GCP control-plane project)`. | **Google Cloud AlloyDB for PostgreSQL** (`spp_platform` in `microdrive-dev`, `us-east1`) — **not Cloud SQL**. All DDL constructs (`gen_random_uuid()`, `sha256()`, `plpgsql` triggers, partial/GIN indexes, `DEFERRABLE INITIALLY DEFERRED` FKs, `fillfactor = 80`) are AlloyDB-compatible. | `ADR-GLB-003`, `ADR-GLB-004`, `specs/data-model/spp_state_model.sql` |
| **3** | **Four-Gate Storage & `<= 2 KB` Projections** | `Requested` and `Approved` in full in Postgres; `Expected` and `Observed` in GCS; Postgres holds pointers, hashes, `< 2000`-byte `resource_observed.projection`, and `drift_finding` rows. | **Confirmed:** `Requested` and `Approved` in AlloyDB Postgres (zero secrets); `Expected` and `Observed` in GCS; short non-sensitive observed-state projections (`<= 2 KB` / `< 2000` bytes) and `drift_finding` summaries in Postgres are explicitly allowed. | `ADR-GLB-003`, `ADR-GLB-004`, `specs/data-model/spp_state_model.sql` |
| **4** | **Environment Taxonomy & Name Token** | 8 environment codes (`sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`, `prod`); open decision on `pdev`/`pqa`/`preprod`; bundle used `non-prod` (with hyphen) and treated `pdev`/`pqa`/`preprod` as prod-like in the Spanner `dbaas_reviewer` skip rule. | **Only `nonprod` and `prod`; name token is `nonprod` (no hyphen).** `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, and `preprod` **all map to `nonprod` everywhere**, including in the Spanner `dbaas_reviewer` skip condition (`metadata.environment not in ('prod') and metadata.resolved.app_tier != '1'`). | `ADR-GLB-006`, `ADR-GLB-008`, `ADR-BP-003`, `ADR-SVC-001`, `ADR-SVC-002`, `specs/*` |
| **5** | **State Bucket Topology** | Per-LOB state buckets (`gs://idp-tfstate-<lob>/projects/<project_id>/...`). | **Single state bucket `gs://microdrive-dev-spp-tfstate` for now** (no per-LOB buckets). | `ADR-GLB-003`, `ADR-GLB-004`, `ADR-GLB-006`, `ADR-AUT-001`, `specs/*` |
| **6** | **Deletion / Destroy / Replace Approval** | Open decision leaning toward "Owner plus platform team for prod"; `approval.status` allowed `AUTO_APPROVED` and `approval_decision.status` allowed `auto_approved`. | **No deletion, destroy, or replacement of any resource without explicit human approval in ANY environment (`nonprod` or `prod`)**; **no `AUTO_APPROVED` for deletes** (`CONSTRAINT approval_no_auto_approve_delete`, `blocked_reason = 'destroy_without_delete_request'`). | `ADR-GLB-004`, `ADR-GLB-007`, `ADR-BP-003`, `ADR-AUT-002`, `specs/data-model/spp_state_model.sql` |
| **7** | **Drift Response** | Open decision leaning toward "Auto-reapply critical guardrail drift (PAP, UBLA, CMEK, public IAM) after notifying the owner"; `drift_finding.status` included `REMEDIATING` and `resolution` included `'reapplied'`. | **Drift is alert-only, never auto-reapply.** `REMEDIATING` and `'reapplied'` are removed; remediation always goes through a new human-approved request. | `ADR-GLB-004`, `ADR-GLB-007`, `ADR-AUT-002`, `specs/data-model/spp_state_model.sql` |
| **8** | **Terraform Runner Execution** | One Kubernetes Job per run (`tf-<phase>-<20hex>`) in K8s namespace `idp-runners`. | **One Kubernetes Job per run (`tf-<phase>-<20hex>`) in K8s namespace `spp-platform`** on tainted node pool `spp-pool` (`ADR-AUT-001`, `ADR-CLD-GCP-001`). | `ADR-AUT-001`, `ADR-GLB-006`, `specs/*` |
| **9** | **Out-of-Scope Items** | Multi-cloud (`aws`, `azure`), UI details, ITSM/CMDB active integration, legacy portal shim field mappings (`§8`). | **Out of scope:** AWS/Azure, UI (beyond keeping `'ui'` in `submission.channel`), ServiceNow/CMDB, API Forge, and legacy portal mapping (kept only as a deferred note in Section 4 below). | All ADRs, `docs/source-provenance.md` |

---

## 3. Complete Catalog of Unverified Source Gaps (`[NOT CAPTURED]`, `[truncated]`, `inferred`)

Every item below was either not photographed or cut off in the source photos and remains flagged as **`Unverified (source gap)`**:

### 3.1 Entire Files Visible in Package File Tree (`IMG_6548`) But Not Photographed

1. **`schemas/idp-common.schema.json`** — Shared JSON Schema Draft 2020-12 definitions (metadata, labels, IAM members, KMS keys, lifecycle tasks).
2. **`schemas/gcs_bucket.schema.json`** — Bucket JSON Schema at each gate (`requested`, `approved`, `expected`, `observed`).
3. **`schemas/spanner.schema.json`** — Spanner instance + database JSON Schema at each gate (including `if/then` edition rules).
4. **`schemas/project-expected.schema.json`** — Project-level `terraform.tfvars.json` and revision `manifest.json` JSON Schemas.
5. **`examples/gcs_bucket.gates.json`** — Full JSON file for the GCS bucket walkthrough across all four gates (only the README summary in `gates.md` §6 was photographed).
6. **`examples/resource_kinds.json`** — JSON file mirroring `idp.resource_kind` seed rows.
7. **`examples/expected/rev-000002/manifest.json`** and **`examples/expected/rev-000002/terraform.tfvars.json`** — Composed project-level revision artifacts.
8. **`tools/validate_examples.py`** — Python stdlib validation script running 49 mechanical checks (schema validation, `Requested -> Expected` hash chain, drift comparer verification, `k8s_job_name` derivation).
9. **`naming-spec.md`** and **`README.md` (v1)** — Narrative companion files (`naming-spec.json` and `README_2.md` were photographed instead).
10. **Photo `IMG_6569`** — Missing from the numbered photo sequence `IMG_6522..IMG_6592` (inside `examples/spanner.gates.json`).

### 3.2 Uncaptured / Truncated Line Ranges in `idp_state_model.sql` (`specs/data-model/spp_state_model.sql`)

| Source Lines | Table / Object | What Was Missing & How It Is Handled |
| :--- | :--- | :--- |
| **Lines 47–52** | `idp.approval_gate_config` | Comment lines preceding `CREATE TABLE idp.approval_gate_config` (`[NOT CAPTURED]`). |
| **Lines 96–104** | `idp.state_unit` | Column definitions between `cloud` and `current_expected_rev` (`[NOT CAPTURED]`). Reconstructed (`scope_type`, `scope_id`, `lob`, `environment`, `apm_id`, `state_bucket`, `state_prefix`, `executor_identity`) from `UNIQUE (cloud, scope_id)`, `UNIQUE (state_bucket, state_prefix)`, column `COMMENT`s, and `idp.v_resource_status` (`su.scope_id AS project_id, su.lob`). Flagged as `Unverified (source gap)`. |
| **Line 148 & Lines 149–156** | `idp.resource` | Tail of `CREATE UNIQUE INDEX resource_gcs_bucket_name_uq ON idp.resource (name)` (`[NOT CAPTURED]`; reconstructed with `WHERE kind = 'gcs_bucket'`) and any following lines before `idp.submission`. |
| **Lines 205–209** | `idp.policy_evaluation` | Table header and primary key column (`[NOT CAPTURED]`; `evaluation_id uuid PRIMARY KEY DEFAULT gen_random_uuid()` inferred from `REFERENCES idp.policy_evaluation (evaluation_id)` in `idp.approval`). |
| **Lines 250–258** | `idp.approval` | Tail of `CONSTRAINT approval_spec_when_approved` (`[NOT CAPTURED]`; inferred `OR (approved_spec IS NOT NULL AND approved_spec_sha256 IS NOT NULL)`) and any additional constraints before `approval_resource_idx`. |
| **Lines 302–309** | `idp.expected_revision` | Closing columns/constraints of `idp.expected_revision` (`[NOT CAPTURED]`; `status`, `blocked_reason`, `created_at`, and `UNIQUE (state_unit_id, revision_no)` reconstructed from `COMMENT`s, `v_resource_status`, `INV-4`, and `spanner.gates.json`). |
| **Lines 356–362** | `idp.tf_operation` | Lines immediately following `CREATE TABLE idp.tf_operation` (`[NOT CAPTURED]`). |
| **Lines 408–411** | `idp.drift_finding` | Columns between `drift_kind` and `guardrail_rule_id` (`[NOT CAPTURED]`; `attribute_path`, `expected_value`, `observed_value`, and `severity` reconstructed from `drift_finding_open_uq` index and `examples/spanner.gates.json`). |
| **Lines 460–461** | `idp.gate_event` | Tail of `idp.gate_event` (`[NOT CAPTURED]`; `published_at timestamptz` reconstructed from `gate_event_unpublished_idx` and `gate_event_guard`). |
| **Lines 602 & 605** | `idp.v_resource_status` | `LEFT JOIN idp.approval ap ON ap.approval_id = r.current_approval_id` (line 602) and `FROM idp.expected_revision_member m` (line 605) (`[NOT CAPTURED]`; reconstructed from `SELECT` list and adjacent `JOIN`). |
| **Lines 649–652** | `idp.resource_kind` seed | `gcs_bucket` seed row (`[NOT CAPTURED]` except tail `ARRAY['/force_destroy'], 'storage-bucket')`; middle columns inferred from `spanner_instance` seed row and `resource-types.md`). |
| **18th Table** | `idp.apm_alias` | Shown on page 2 of the diagrams PDF (`IMG_6573..6575`, "All 18 tables in `idp` schema") and referenced in `naming-spec.json` (`idp.apm_alias.alias for metadata.apm_id`), but not present in the captured `idp_state_model.sql` photos. Reconstructed and flagged as `Unverified (source gap)`. |

### 3.3 Uncaptured / Truncated Sections in `naming-spec.json`, `README_2.md`, and `spanner.gates.json`

1. **`naming-spec.json` Lines 46–53 (`tokens.purpose.reserved`):** Additional reserved words after `"restricted", "unrestricted"` were `[NOT CAPTURED]`.
2. **`naming-spec.json` Lines 117–119 (`kinds.spanner_database.rules`):** Rule IDs after `"SPN-NAME-002"` were `[NOT CAPTURED]` (`"NAM-RSV-001"`, `"NAM-IMM-001"`, `"NAM-LEG-001"` inferred from `naming.md`).
3. **`README_2.md` §9 Invariants `INV-2..INV-4`:** The table rows for `INV-2`, `INV-3`, and the start of `INV-4` (ending with `...'plan'"); otherwise the revision becomes BLOCKED`) were `[NOT CAPTURED]` (`ADR-GLB-007` `OQ-4`).
4. **`README_2.md` §8 Legacy Mapping Rows 368–378 (`metadata.cost_center`):** Not captured in the legacy bucket mapping table (legacy mapping is deferred/out of scope).
5. **`examples/spanner.gates.json` `initial_ddl` Tail & Example Hashes:** The right edge of `CREATE TABLE orders (...)` was `[truncated]`, and example SHA-256 hex digests were invalidated by company-name sanitization.

---

## 4. Sanitization & Deferred Legacy Notes

### 4.1 Sanitization Applied
- All source company names, abbreviations, subsidiary names, and internal product/vendor names were replaced during transcription with `SPP`, `<lob>`, `example.com`, `sppappid`, `idp.spp/v1`, and `legacy` / `legacy_shim`.
- Workstation paths, internal repo names, internal KMS key resource paths, and shared nonprod project IDs were excluded.

### 4.2 Deferred Note: Legacy Portal Shim (`legacy_shim`)
- Section 8 of the source package described a translation shim (`channel = 'legacy_shim'`) that stored legacy ticket `templatejsondata` in `idp.submission.raw_payload` and mapped legacy form fields (`storage_bucket_name`, `ResourceName`, `selectedSpannerinstanceedition`, etc.) into canonical `Requested` documents.
- Per user decision, legacy portal mapping (and legacy "taxi" migration) is **out of scope for now** and deferred post-MVP (`ADR-GLB-001 OQ-4`). Only the `'legacy_shim'` and `'legacy_provisioning_shim'` enum values in `idp.submission.channel` and the optional `idp.resource_kind.legacy_resource_type` column are retained in the DDL for schema compatibility.
