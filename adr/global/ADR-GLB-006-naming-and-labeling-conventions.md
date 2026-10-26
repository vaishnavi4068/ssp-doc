# ADR-GLB-006: Naming Conventions and Identifier Patterns

- **ADR ID:** ADR-GLB-006
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the deterministic resource naming specification (`specs/naming/naming-spec.json`), token rules, validation rules (`GCS-NAME-*`, `SPN-NAME-*`, `NAM-*`), test vectors, platform identifier patterns, and looked-up resource conventions across SPP on GCP, using the two-environment taxonomy (`nonprod` and `prod` only, with no hyphen in `nonprod`).

## Context

From the sanitized four-gate design package (`naming.md` and `raw/naming-spec.reconstructed.json`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)) and user overrides:

1. **Structured Token-Driven Naming (`idp-naming` v1.0.0):** Every managed GCP resource name is constructed deterministically from validated tokens (`{lob}`, `{env}`, `{app}`, `{purpose}`, `{suffix}`) rather than free-form user strings, preventing collisions, encoding LOB and environment identity, and disallowing Cloud Storage reserved prefixes/substrings (`goog`, `google`, `g00gle`).
2. **Two Environments Only (`nonprod` and `prod` — No Hyphen):** The source package originally allowed 8 environment codes (`sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`, `prod`) and had an open conflict over whether `non-prod` (with a hyphen) would break kebab-case parsing. **User decision overrides the source everywhere:** SPP has **only two environments: `nonprod` and `prod`**, and the naming token is **`nonprod` (no hyphen)**. Legacy environment codes `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, and `preprod` all map to **`nonprod`** everywhere.
3. **Separation of Label Standard:** Detailed mandatory label keys (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`), value normalization (`LBL-001`, `LBL-002`), and legacy label mapping are governed in companion ADR **[`ADR-GLB-008: Label and Tag Standard`](ADR-GLB-008-label-and-tag-standard.md)**.

## Decision

### 1. Naming Tokens (`specs/naming/naming-spec.json`)

| Token | Source | Pattern / Allowed Values | Length & Rules |
| :--- | :--- | :--- | :--- |
| `lob` | `metadata.lob`, checked against the LOB code list | `^[a-z][a-z0-9]{1,5}$` | `2..6` chars, lowercase alphanumeric starting with a letter |
| `env` | `metadata.environment` (normalized to `nonprod` or `prod`) | Allowed: `["nonprod", "prod"]` | **User override:** `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod` all map to `nonprod` (no hyphen) |
| `app` | `idp.apm_alias.alias` for `metadata.apm_id` (e.g., `apm0017299 -> orders`) | `^[a-z][a-z0-9]{1,11}$` | `2..12` chars, unique per `apm_id` (`unique_per_apm: true`) |
| `purpose` | User-supplied (`spec.purpose` / purpose token) | Kebab: `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`<br>Snake: `^[a-z][a-z0-9]*(_[a-z0-9]+)*$` | `2..20` chars (`2..17` for `spanner_database`). **Reserved words forbidden (`NAM-RSV-001`):** `non-prod`, `nonprod`, `prod`, `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`, `restricted`, `unrestricted` *(Note: source lines 46–53 of `naming-spec.json` `[NOT CAPTURED]`; see `## Open Questions`)* |
| `suffix` | Platform-generated cryptographically secure random | `^[a-z0-9]{4}$` (alphabet `a-z0-9`) | 4 chars, `max_attempts: 5` on collision (`GCS-NAME-003`) |

### 2. Per-Kind Naming Templates

| Kind / Target | Template | Purpose Style & Requirement | Suffix | Max Length | Uniqueness Scope | Enforced Rules |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`gcs_bucket`** | `{lob}-{env}-{app}-{purpose}-{suffix}` | `kebab`, **required** (`max 20`) | Yes (`4` chars) | `63` | `global` (across GCP + `idp.resource`) | `GCS-NAME-001`, `GCS-NAME-002`, `GCS-NAME-003`, `NAM-RSV-001`, `NAM-IMM-001`, `NAM-LEG-001` |
| **`spanner_instance`** | `{lob}-{env}-{app}[-{purpose}]` | `kebab`, optional (`max 20`) | No | `64` | `project` | `SPN-NAME-001`, `NAM-RSV-001`, `NAM-IMM-001`, `NAM-LEG-001` |
| **`spanner_display_name`** | `{LOB} {App}[ {Purpose}] ({env})` | Title-cased words, mutable | No | `4..30` | — (shortening drops trailing purpose words, then truncates `App`) | `SPN-NAME-003` |
| **`spanner_database`** | `{app}[_{purpose}]` | `snake`, optional (`max 17`) | No | `30` | `instance` | `SPN-NAME-002`, `NAM-RSV-001`, `NAM-IMM-001`, `NAM-LEG-001` *(Note: lines 117–119 `[NOT CAPTURED]`)* |
| **`gcp_project`** | `{lob}-{env}-{purpose}` | `kebab` (owned by project vending) | No | `30` | `global` | Existing project-vending convention (e.g., `<lob>-nonprod-orders-svc`) |

**Forbidden GCS Bucket Prefixes & Substrings (`GCS-NAME-002`):**
- `applies_to`: `["gcs_bucket"]`
- `prefixes`: `["goog"]`
- `substrings`: `["google", "g00gle"]`

### 3. Naming Validation Rules (`GCS-NAME-*`, `SPN-NAME-*`, `NAM-*`)

| Rule ID | Gate | On Failure | Check Description |
| :--- | :--- | :--- | :--- |
| **`GCS-NAME-001`** | `requested` | `reject` | Bucket name equals `{lob}-{env}-{app}-{purpose}-{suffix}` built from the request (`env` in `{"nonprod", "prod"}`). |
| **`GCS-NAME-002`** | `requested` | `reject` | No `'goog'` prefix and no `'google'` or `'g00gle'` substring (Cloud Storage rule). |
| **`GCS-NAME-003`** | `intake` | `draw a new suffix, up to max_attempts (5)` | Name is free in `idp.resource` (`resource_gcs_bucket_name_uq`) and `storage.buckets.get` returns `404`. |
| **`SPN-NAME-001`** | `requested` | `reject` | Spanner instance name equals `{lob}-{env}-{app}[-{purpose}]`. |
| **`SPN-NAME-002`** | `requested` | `reject` | Spanner database name equals `{app}` or `{app}_{purpose}` (snake_case, `_` not `-`). |
| **`SPN-NAME-003`** | `approved` | `replace and record in guardrail_trace` | Spanner instance `display_name` equals generated `{LOB} {App}[ {Purpose}] ({env})` (`4..30` chars; drops trailing purpose words then cuts `App` if `> 30` chars). |
| **`NAM-RSV-001`** | `requested` | `reject` | `purpose` token is not a reserved word (environment names or data-sensitivity words like `restricted` / `unrestricted`, which belong in labels). |
| **`NAM-IMM-001`** | `requested` | `reject` | An `update` request keeps the exact name of the resource it updates (no rename via update). |
| **`NAM-LEG-001`** | `requested` | `allow and add label idp_naming=legacy` | An `import` request keeps its existing cloud resource name even if it does not match the 2.0 template, and adds label `idp_naming = "legacy"`. |

### 4. Canonical Naming Test Vectors & Generation Examples

**Generation Examples (with `env = "nonprod"` / `"prod"`):**
- `gcs_bucket` (`lob="<lob>"`, `env="nonprod"`, `app="orders"`, `purpose="landing"`, `suffix="a1b2"`) → `<lob>-nonprod-orders-landing-a1b2`
- `spanner_instance` (`lob="<lob>"`, `env="nonprod"`, `app="orders"`, `purpose=null`) → `<lob>-nonprod-orders`
- `spanner_database` (`app="orders"`, `purpose="history"`) → `orders_history`
- `spanner_display_name`:
  - `("SPP", "Orders", null, "nonprod")` → `"SPP Orders (nonprod)"`
  - `("SPP", "Orders", "Reporting", "prod")` → `"SPP Orders Reporting (prod)"`
  - `("SPP", "Ledgerengine", "Reconciliation", "prod")` → `"SPP Ledgerengine (prod)"` *(purpose dropped by 30-char shortening rule)*

**Validation Test Vectors:**

| Target Kind | Input Name / Scenario | Expected Outcome | Rule Triggered |
| :--- | :--- | :--- | :--- |
| `gcs_bucket` | `<lob>-nonprod-orders-landing-a1b2` (with `env = "nonprod"`) | **VALID** | — |
| `gcs_bucket` | `<lob>-prod-orders-landing-a1b2` when request `environment = "nonprod"` | **REJECT** | `GCS-NAME-001` (env token mismatch) |
| `gcs_bucket` | `<lob>-nonprod-orders-landing` (missing 4-char random suffix) | **REJECT** | `GCS-NAME-001` |
| `gcs_bucket` | `<LOB>-nonprod-orders-landing-a1b2` (contains uppercase) | **REJECT** | `GCS-NAME-001` |
| `gcs_bucket` | `<lob>-nonprod-orders-google-a1b2` (contains `google`) | **REJECT** | `GCS-NAME-002` |
| `gcs_bucket` | `<lob>-nonprod-orders-restricted-a1b2` (`purpose = "restricted"`) | **REJECT** | `NAM-RSV-001` (sensitivity belongs in a label) |
| `gcs_bucket` | `action = "update"` changing name of existing bucket | **REJECT** | `NAM-IMM-001` |
| `gcs_bucket` | `action = "import"` of legacy-named bucket | **ALLOW** + sets label `idp_naming = "legacy"` | `NAM-LEG-001` |
| `spanner_instance` | `orders-db` (missing `{lob}` and `{env}`) | **REJECT** | `SPN-NAME-001` |
| `spanner_database` | `orders` or `orders_history` (`app = "orders"`) | **VALID** | — |
| `spanner_database` | `history` (missing `{app}` prefix) | **REJECT** | `SPN-NAME-002` |
| `spanner_database` | `orders-history` (uses hyphen `-` instead of underscore `_`) | **REJECT** | `SPN-NAME-002` |

### 5. Platform Identifier Patterns (`platform_identifiers`)

| Identifier | Pattern / Rule | Example | Enforced By |
| :--- | :--- | :--- | :--- |
| `kind` | `^[a-z][a-z0-9]*(_[a-z0-9]+)*$` | `gcs_bucket`, `spanner_instance`, `spanner_database` | `idp.resource_kind` PK |
| `tfvars_collection` | Plural of `kind` | `gcs_buckets`, `spanner_instances`, `spanner_databases` | `idp.resource_kind.tfvars_collection` |
| `resource_key` | `^gcp:[^:]+:[a-z][a-z0-9_]*:[^:]+$` *(GCP-only override)* | `gcp:<lob>-nonprod-orders-svc:gcs_bucket:<lob>-nonprod-orders-landing-a1b2` | `idp.resource.resource_key` UNIQUE |
| `tf_address` | Rendered from `resource_kind.tf_address_template` | `module.spanner_database["<lob>-nonprod-orders/orders"]` | `idp.resource.tf_address` |
| `state_bucket` | `^microdrive-dev-spp-tfstate$` *(Single state bucket override; source had `^idp-tfstate-[a-z][a-z0-9]{1,5}$`)* | `microdrive-dev-spp-tfstate` | `idp.state_unit.state_bucket` |
| `state_uri` | `gs://microdrive-dev-spp-tfstate/projects/<project_id>/default.tfstate` | `gs://microdrive-dev-spp-tfstate/projects/<lob>-nonprod-orders-svc/default.tfstate` | `idp.observation.state_uri` |
| `artifact_uri` | `gs://microdrive-dev-spp-tfstate/projects/<project_id>/expected/rev-NNNNNN/terraform.tfvars.json` | `gs://microdrive-dev-spp-tfstate/projects/<lob>-nonprod-orders-svc/expected/rev-000002/terraform.tfvars.json` | `idp.expected_revision.artifact_uri` |
| `snapshot_uri` | `gs://microdrive-dev-spp-tfstate/projects/<project_id>/observed/scan-<window>/plan.json` | `gs://microdrive-dev-spp-tfstate/projects/<lob>-nonprod-orders-svc/observed/scan-2026-10-23T06/plan.json` | `idp.observation.snapshot_uri` |
| `logs_uri` | `gs://microdrive-dev-spp-tfstate/projects/<project_id>/logs/<k8s_job_name>.log` | `gs://microdrive-dev-spp-tfstate/projects/<lob>-nonprod-orders-svc/logs/tf-plan-eba5f9ebf4fafecad8e9.log` | `idp.tf_operation.logs_uri` |
| `executor_identity` | Per-project SA (`idp-tf@<project_id>.iam.gserviceaccount.com` / `spp-provisioner@<project_id>.iam.gserviceaccount.com`) | `idp-tf@<lob>-nonprod-orders-svc.iam.gserviceaccount.com` | `idp.state_unit.executor_identity` |
| `temporal_workflow_id` | `req-<request_id>`, `apr-<request_id>`, `su-gcp-<project_id>` | `su-gcp-<lob>-nonprod-orders-svc` | Temporal / `idp.request`, `idp.approval`, `idp.tf_operation` |
| `temporal_schedule_id` | `drift-<project_id>` | `drift-<lob>-nonprod-orders-svc` | Temporal Schedule |
| `task_queue` | `^idp-[a-z]+(-[a-z]+)*-v[0-9]+$` (or `platform` in `spp-platform`) | `idp-reconciler-v1` / `platform` | `ssp-workers` |
| `operation_id` | `op:<state_unit_id>:r<revision_no>:<phase>:<run_key>` | `op:af42f828-3378-5ee2-8e9b-2378d2314f97:r1:plan:1` | `idp.tf_operation` PK & `tf_operation_id_format` |
| `k8s_job_name` | `tf-<phase>-<first 20 hex of sha256(operation_id)>` (max 36 chars, `<= 63`) | `tf-plan-eba5f9ebf4fafecad8e9` | `idp.k8s_job_name(operation_id, phase)` |
| `k8s_namespace` | `spp-platform` *(SPP override of source `idp-runners`; per `ADR-AUT-001` & `ADR-CLD-GCP-001`)* | `spp-platform` | `idp.tf_operation.k8s_namespace` |
| `task_key` | `<task_type>:<target>` | `enable_service:spanner.googleapis.com` | `idp.lifecycle_task.task_key` |
| `gate_key` | `^[a-z][a-z0-9_]*$` | `gcs_bucket_owner`, `spanner_data_owner` | `idp.approval_gate_config.gate_key` |
| `rule_id` | `^[A-Z]{3}(-[A-Z]{2,5})?-[0-9]{3}$` | `GCS-UBLA-001`, `SPN-CFG-001`, `LBL-001`, `PRQ-003` | `guardrail_trace`, `drift_finding.guardrail_rule_id` |
| `module_repo` | `ssp-module-<type>` (source pattern `^tf-gcp-[a-z0-9-]+$`) | `ssp-module-gcs-bucket`, `ssp-module-spanner` | `docs/repo-map.md` |

### 6. Looked-Up (Not Platform-Generated) Resource Names

The following enterprise resources are looked up or verified by SPP rather than generated as managed Terraform resources in the tenant state unit:
- **`vpc_sc_perimeter`** (owned by Network Security): `^[a-z][a-z0-9]*_[a-z]+_(restrict|unrestrict)ed_perimeter$`, e.g., `<lob>_nonprod_restricted_perimeter`.
- **`kms_key`** (owned by Security Key Vault team; looked up by `(LOB, environment_type, location="us-east1")`, never hardcoded to a single nonprod constant): `projects/<kms-project>/locations/us-east1/keyRings/<ring>/cryptoKeys/<key>`, e.g., `projects/<lob>-kms-nonprod/locations/us-east1/keyRings/<lob>-nonprod-use1/cryptoKeys/gcs-default` (or `projects/<spp-factory-host-project-id>/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>` in `<spp-factory-host-project-id>`).
- **`ad_group`** (owned by Identity team via directory service): `gcp-<lob>-<env>-<app>-(read|write|admin|dba)`, e.g., `gcp-<lob>-nonprod-orders-read@example.com`.
- **`service_account`** (owned by project owners): `^[a-z][a-z0-9]{1,11}-[a-z0-9-]*[a-z0-9]$` (`6..30` chars), e.g., `orders-api@<lob>-nonprod-orders-svc.iam.gserviceaccount.com`.
- **`gcp_project`** (owned by project vending): `{lob}-{env}-{purpose}`, e.g., `<lob>-nonprod-orders-svc`.

## Requirements

- **REQ-1 (MUST):** `ssp-cp` MUST validate all `gcs_bucket`, `spanner_instance`, `spanner_display_name`, and `spanner_database` names against [`specs/naming/naming-spec.json`](../../specs/naming/naming-spec.json) and enforce rules `GCS-NAME-001..003`, `SPN-NAME-001..003`, `NAM-RSV-001`, `NAM-IMM-001`, and `NAM-LEG-001`.
- **REQ-2 (MUST):** The `env` naming token MUST only allow `"nonprod"` (no hyphen) and `"prod"`. Input environment values `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, and `preprod` MUST all normalize to `"nonprod"`.
- **REQ-3 (MUST):** When `SPN-NAME-003` normalizes or shortens a `spanner_instance` `display_name` at the `Approved` gate, `ssp-cp` MUST replace the value in `approved_spec` and append an entry to `approval.guardrail_trace`.
- **REQ-4 (MUST):** Every Terraform runner Kubernetes Job name MUST be derived via `k8s_job_name(operation_id, phase) = "tf-" + phase.replace("_", "-") + "-" + sha256(operation_id)[:20]` (`<= 36` characters) and verified by the SQL constraint `tf_operation_job_name_derived` (`ADR-AUT-001`).
- **REQ-5 (MUST):** Automated unit tests in `ssp-cp` and `spp-factory-foundation` MUST execute all naming test vectors defined in Section 4 above.

## Guardrails

- **GR-1:** Never allow `non-prod` (with a hyphen) or raw legacy sub-environment codes (`sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`) as the `{env}` token inside generated 2.0 resource names; always use `nonprod` or `prod`.
- **GR-2 (`NAM-IMM-001`):** Never allow an `update` request to rename an existing resource.
- **GR-3 (`NAM-RSV-001`):** Never allow environment names or data sensitivity classification terms (`restricted`, `unrestricted`) inside the `{purpose}` token.
- **GR-4 (`GCS-NAME-002`):** Never allow GCS bucket names starting with `goog` or containing `google` or `g00gle`.

## Consequences

### Positive

- Using `nonprod` (no hyphen) eliminates ambiguity when parsing hyphen-delimited kebab-case names (`{lob}-{env}-{app}-{purpose}-{suffix}`) and saves 1 character against GCS (`63` char) and Spanner display name (`30` char) limits.
- `NAM-LEG-001` cleanly supports brownfield `import` of legacy resources (tagging them `idp_naming = "legacy"`) without relaxing naming rules for greenfield `create` requests.

### Negative / Trade-offs

- Requires `idp.apm_alias` to be populated for every onboarded `apm_id` so `{app}` can be resolved deterministically.

## Acceptance Criteria

- [ ] `specs/naming/naming-spec.json` is committed in `ssp-doc` with `env.allowed = ["nonprod", "prod"]` and all rules, test vectors, platform identifiers, and looked-up patterns.
- [ ] `ssp-cp` implements the naming validator and `SPN-NAME-003` guardrail trace mutation.
- [ ] All positive and negative test vectors in Section 4 pass in CI.

## Success Criteria

- **SC-1:**
  - **Given** a `gcs_bucket` create request for `apm_id = "apm0017299"` (`alias = "orders"`), `lob = "<lob>"`, `environment = "dev"` (normalized to `"nonprod"`), `purpose = "landing"`, and drawn suffix `"a1b2"`
  - **When** validated by `ssp-cp` at the `Requested` gate
  - **Then** the bucket name `<lob>-nonprod-orders-landing-a1b2` passes `GCS-NAME-001..003` and `NAM-RSV-001`.
- **SC-2:**
  - **Given** a `gcs_bucket` request with `purpose = "restricted"` or name containing `"google"`, or a `spanner_database` request with hyphenated name `"orders-history"`
  - **When** evaluated at the `Requested` gate
  - **Then** `ssp-cp` rejects the request citing `NAM-RSV-001`, `GCS-NAME-002`, or `SPN-NAME-002`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-GLB-006` and `specs/naming/naming-spec.json` |
| `ssp-cp` | Enforces `GCS-NAME-*`, `SPN-NAME-*`, `NAM-*` and resolves `{app}` from `idp.apm_alias` |
| `ssp-workers` | Enforces `operation_id`, `k8s_job_name`, `resource_key`, and `tf_address` patterns |
| `ssp-ui` | Previews generated resource and display names using `specs/naming/naming-spec.json` |
| `ssp-module-gcs-bucket`, `ssp-module-spanner` | Validates input names and applies `idp_naming = "legacy"` on imports |
| `spp-factory-foundation` | Runs naming test vectors in `gates/` |

## Open Questions

- [x] **OQ-1 (Environment Token `nonprod` vs. `non-prod` — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Only `nonprod` (no hyphen) and `prod` are valid environment tokens; `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod` all map to `nonprod` everywhere.
- [ ] **OQ-2 (Unverified Source Gaps in `naming-spec.json` — SOURCE GAP [Owner: Manoj]):** **Unverified (source gap):** In `raw/naming-spec.reconstructed.json`:
  1. **Lines 46–53:** Complete list of `tokens.purpose.reserved` words beyond `non-prod`, `nonprod`, `prod`, `restricted`, `unrestricted` was `[NOT CAPTURED]` in the photos.
  2. **Lines 117–119:** Additional rule IDs in `kinds.spanner_database.rules` after `"SPN-NAME-002"` were `[NOT CAPTURED]` (inferred as `"NAM-RSV-001"`, `"NAM-IMM-001"`, `"NAM-LEG-001"` from `naming.md`).
  3. **Real KMS Key Resource Path Example:** The source's internal KMS key example in `looked_up.kms_key.example` was excluded during sanitization; the canonical shape `projects/<kms-project>/locations/us-east1/keyRings/<ring>/cryptoKeys/<key>` is preserved.

## Related ADRs

- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-007: Governance Gates and Policy (Rego)](ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-008: Label and Tag Standard](ADR-GLB-008-label-and-tag-standard.md)
- [ADR-GLB-009: Resource Kind Registry](ADR-GLB-009-resource-kind-registry.md)
- [ADR-SVC-001: GCS Bucket End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](../endpoint-service/ADR-SVC-002-spanner-instance-and-database.md)
