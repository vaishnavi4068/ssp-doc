# ADR-SVC-001: First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails

- **ADR ID:** ADR-SVC-001
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-storage-gcp@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-gcs-bucket` (`ssp-module-gcs`), `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the end-to-end four-gate contract (`Requested` → `Approved` → `Expected` → `Observed`), schema rejections, guardrail rules (`GCS-UBLA-001`, `GCS-PAP-001`, `GCS-ENC-001/002`, `GCS-RET-001`, `GCS-SDP-001`, `GCS-DEL-001`, `GCS-NAME-001..003`, `LBL-001/002`, `PRQ-001/002`), authoritative IAM bindings, and drift severity rules for SPP's **first vertical slice**: provisioning a **Google Cloud Storage bucket (`kind = "gcs_bucket"`, `google_storage_bucket`)** in region **`us-east1`** into `gs://microdrive-dev-spp-tfstate`, with **no UI**.

## Context

From the design session (`uploads/design-digest.md`), build order (`ADR-BP-002`), the sanitized four-gate design package (`resource-types.md` §6, `gates.md` §6, `naming.md`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)), and user overrides:

1. **Why `gcs_bucket` Is the First Vertical Slice:** Exercises every layer of the four-gate architecture (intake submission, closed JSON Schema validation, `RequestWorkflow`, `ApprovalGateWorkflow` with `gcs_bucket_owner`, OPA guardrail mutations + `guardrail_trace`, `pre_apply` tasks, `StateUnitReconcilerWorkflow`, deterministic K8s Job `tf-<phase>-<20hex>` in `spp-platform`, `Expected` revision in `gs://microdrive-dev-spp-tfstate`, and `<= 2 KB` `Observed` projection in AlloyDB) with **no UI**.
2. **User Overrides Applied to `gcs_bucket`:**
   - **Region `us-east1` Only (No Multi-Region `US`):** Although the source example showed `"location": "US"` and KMS key path `.../locations/us/...`, SPP's locked override restricts all GCP resources (including `prod`) to single region **`us-east1`** (`"location": "us-east1"`, KMS key in `locations/us-east1`).
   - **Environment Token `nonprod` (No Hyphen):** All non-production environment codes (`sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`) map to **`nonprod`** (`{lob}-{env}-{app}-{purpose}-{suffix}`, e.g., `<lob>-nonprod-orders-landing-a1b2`).
   - **Single State Bucket:** `gs://microdrive-dev-spp-tfstate` (no per-LOB state buckets).
   - **No Deletion Without Human Approval in ANY Environment:** `force_destroy` is always `false` (`GCS-DEL-001`), and `action = "delete"` requires explicit human approval in both `nonprod` and `prod` (no `AUTO_APPROVED`).

## Decision

### 1. Gate 1 (`Requested`) Canonical Envelope & Schema Rejections

Example `Requested` document for `kind = "gcs_bucket"` (with `us-east1` and `nonprod` overrides applied):

```json
{
  "api_version": "idp.spp/v1",
  "kind": "gcs_bucket",
  "action": "create",
  "metadata": {
    "apm_id": "apm0017299",
    "project_id": "<lob>-nonprod-orders-svc",
    "environment": "nonprod",
    "lob": "<lob>",
    "data_sensitivity": "restricted",
    "data_classification": "proprietary",
    "owner": "bucket.owner@example.com",
    "shared_mailbox": "orders-team@example.com",
    "requested_by": "requester@example.com",
    "cost_center": "000000",
    "tenancy": "dedicated",
    "labels": {
      "app": "orders"
    },
    "extensions": {
      "<lob>": {
        "<lob>ml_version": "1.5"
      }
    }
  },
  "spec": {
    "name": "<lob>-nonprod-orders-landing-a1b2",
    "location": "us-east1",
    "storage_class": "STANDARD",
    "versioning": false,
    "lifecycle_rules": [
      {
        "action": { "type": "Delete" },
        "condition": { "age_days": 365, "with_state": "ANY" }
      }
    ],
    "access": [
      {
        "role": "roles/storage.objectAdmin",
        "members": [
          "serviceAccount:orders-pipeline@<lob>-nonprod-orders-svc.iam.gserviceaccount.com"
        ]
      },
      {
        "role": "roles/storage.objectViewer",
        "members": [
          "group:gcp-<lob>-nonprod-orders-read@example.com"
        ]
      }
    ],
    "purpose": "Landing zone for order events"
  }
}
```

**Schema & Policy Rejections at the `Requested` Gate:**
1. **IAM Principal Types:** Rejects any member prefix other than `group:` and `serviceAccount:` (strictly forbids `user:`, `allUsers`, `allAuthenticatedUsers`).
2. **IAM Role Allowlist:** Rejects any role outside the bucket allowlist (e.g., `roles/storage.objectAdmin`, `roles/storage.objectViewer`, `roles/storage.objectCreator`; strictly forbids `roles/storage.admin` and legacy bucket owner roles).
3. **Closed Schema (`additionalProperties: false`):** Rejects any field not defined in `gcs_bucket.schema.json#/$defs/requested` (keeps secret-bearing fields out and prevents callers from requesting guardrail-owned fields such as `uniform_bucket_level_access`, `public_access_prevention`, `default_kms_key_name`, `soft_delete_policy`, or `force_destroy`).
4. **Retention vs. Object Versioning Mutual Exclusion:** Rejects requests combining a bucket retention policy with `versioning: true` (mutually exclusive in Google Cloud Storage).
5. **Naming & Region Validation:** Enforces `GCS-NAME-001` (`{lob}-{env}-{app}-{purpose}-{suffix}`), `GCS-NAME-002` (no `goog` prefix or `google`/`g00gle` substring), `GCS-NAME-003` (uniqueness check in `idp.resource` and `storage.buckets.get` 404), `NAM-RSV-001`, and `location == "us-east1"`.

### 2. Gate 2 (`Approved`) Guardrail Rules & Mutations (`guardrail_trace`)

At the `Approved` gate (`approval_gate_key = "gcs_bucket_owner"`), `RequestWorkflow` and OPA apply the following guardrail rules and record each in `idp.approval.guardrail_trace`:

| Rule ID | Field / Path | Requested | Approved Value | Source / Rationale |
| :--- | :--- | :--- | :--- | :--- |
| **`GCS-UBLA-001`** | `/spec/uniform_bucket_level_access` | *(not requestable; legacy form said `false`)* | `true` | Constant (`true`). |
| **`GCS-PAP-001`** | `/spec/public_access_prevention` | — | `"enforced"` | Constant (`"enforced"`). |
| **`GCS-ENC-001` / `002`** | `/spec/kms_key_name` (`default_kms_key_name`) | — | `projects/<lob>-kms-<env>/locations/us-east1/keyRings/<lob>-<env>-use1/cryptoKeys/gcs-default` *(or `projects/microdrive-dev/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>` in `microdrive-dev`)* | **Lookup by `(LOB, environment_type, location="us-east1")`** — never a hardcoded constant (legacy Java constants pointed dev, QA, and prod at the same nonprod KMS key). Key region must match bucket location (`us-east1`). |
| **`GCS-RET-001`** | `/spec/retention_days` (`retention_policy.retention_period`) | `none` | `90` days (`7776000` seconds; `is_locked = false`; `versioning` stays `false`) | Lookup by `data_sensitivity` (`>= 90` days illustrative floor; mutually exclusive with object versioning). |
| **`GCS-SDP-001`** | `/spec/soft_delete_retention_days` (`soft_delete_policy.retention_duration_seconds`) | — | `7` days (`604800` seconds) | Constant (`7` days). |
| **`GCS-DEL-001`** | `/spec/force_destroy` | — | `false` | Constant (`false`). |
| **`LBL-001` / `002`** | `/metadata/labels` | `{"app": "orders"}` | Mandatory 9-label set merged + normalized with user labels (`ADR-GLB-008`) | Computed and normalized (`lowercase`, `[^a-z0-9_-]` → `_`, max 63 chars). |
| **`PRQ-001`** | `/prerequisites` (`idp.lifecycle_task`) | — | `pre_apply` task `ad_group` via directory service for `gcp-<lob>-nonprod-orders-read@example.com` | Derived from `spec.access` group members. |
| **`PRQ-002`** | `/prerequisites` (`idp.lifecycle_task`) | — | `pre_apply` task `vpc_sc_ingress` into `<lob>_nonprod_restricted_perimeter` | Derived from `metadata.data_sensitivity == "restricted"`. |

### 3. Gate 3 (`Expected`) Composed `tfvars` Entry (`gcs_buckets` Collection)

In `projects/<project_id>/expected/rev-NNNNNN/terraform.tfvars.json`, the bucket is rendered under `tfvars_collection = "gcs_buckets"`:

```json
{
  "project": "<lob>-nonprod-orders-svc",
  "name": "<lob>-nonprod-orders-landing-a1b2",
  "location": "us-east1",
  "storage_class": "STANDARD",
  "uniform_bucket_level_access": true,
  "public_access_prevention": "enforced",
  "versioning": false,
  "autoclass": false,
  "default_kms_key_name": "projects/<lob>-kms-nonprod/locations/us-east1/keyRings/<lob>-nonprod-use1/cryptoKeys/gcs-default",
  "retention_policy": {
    "retention_period": 7776000,
    "is_locked": false
  },
  "soft_delete_policy": {
    "retention_duration_seconds": 604800
  },
  "lifecycle_rules": [
    {
      "action": { "type": "Delete" },
      "condition": { "age": 365, "with_state": "ANY" }
    }
  ],
  "labels": {
    "app": "orders",
    "costcenter": "000000",
    "sppappid": "apm0017299",
    "datasensitivity": "restricted",
    "dataclassification": "proprietary",
    "environmentsubtype": "nonprod",
    "environmenttype": "nonprod",
    "idp_resource_id": "9478bcfc-c2cf-583b-8bd8-096476647840",
    "owner": "bucket_owner_example_com",
    "primarylob": "<lob>",
    "provisionedby": "idp",
    "sharedemailaddress": "orders-team_example_com",
    "tenancy": "dedicated"
  },
  "iam_bindings": {
    "roles/storage.objectAdmin": [
      "serviceAccount:orders-pipeline@<lob>-nonprod-orders-svc.iam.gserviceaccount.com"
    ],
    "roles/storage.objectViewer": [
      "group:gcp-<lob>-nonprod-orders-read@example.com"
    ]
  },
  "force_destroy": false
}
```

- **Authoritative Per-Role IAM Bindings:** `iam_bindings` are rendered as authoritative per-role bindings (`google_storage_bucket_iam_binding`), so any member added out of band in GCP Console is detected as drift.

### 4. Gate 4 (`Observed`) Projection & Drift Severity for `gcs_bucket`

- `resource_observed.projection` (`< 2000` bytes; example bucket projection in source is `1,429` bytes) uses the same shape as the `Expected` entry (minus `drift_ignore_paths = ['/force_destroy']`).
- **Drift Severity Mapping (`idp.drift_finding`, Alert-Only):**
  - `critical`: `public_access_prevention` (e.g., switched to `"inherited"` in Console → `guardrail_rule_id = "GCS-PAP-001"`), `uniform_bucket_level_access`, `default_kms_key_name`, or public IAM principal (`allUsers` / `allAuthenticatedUsers`).
  - `high`: `retention_policy` (retention shortened), `soft_delete_policy`.
  - `medium`: `storage_class`, `lifecycle_rules`, non-public `iam_bindings` (e.g., extra group granted out of band).
  - `low`: `labels` (e.g., `owner` label removed).

*(Deferred Note — Legacy Shim Mapping: In the source package §8, a legacy shim mapped ticket `TKT-0000004029` `templatejsondata` fields `storage_bucket_name`/`gcs_bucket_name` -> `spec.name`, `storage_bucket_project` -> `metadata.project_id`, `storage_bucket_location` -> `spec.location`, etc. Per user decision, legacy portal mapping is out of scope for now and retained only as a deferred note in [`docs/source-provenance.md`](../../docs/source-provenance.md).)*

## Requirements

- **REQ-1 (MUST):** The first vertical slice (`kind = "gcs_bucket"`) MUST operate end-to-end via the `ssp-cp` REST API through all four gates (`REQUESTED -> APPROVED -> EXPECTED -> OBSERVED`) with **no UI dependency**.
- **REQ-2 (MUST):** At the `Requested` gate, `ssp-cp` MUST reject IAM members other than `group:` and `serviceAccount:`, roles outside the bucket allowlist, unknown/guardrail-owned fields, `location != "us-east1"`, and retention policy combined with `versioning = true`.
- **REQ-3 (MUST):** At the `Approved` gate, `ssp-cp` MUST enforce and trace `GCS-UBLA-001` (`true`), `GCS-PAP-001` (`"enforced"`), `GCS-ENC-001/002` (lookup by `(LOB, environment_type, "us-east1")`), `GCS-RET-001` (`>= 90` days / `7776000`s when versioning is `false`), `GCS-SDP-001` (`7` days / `604800`s), `GCS-DEL-001` (`force_destroy = false`), `LBL-001/002`, and `PRQ-001/002`, and require approval from `gcs_bucket_owner` (`metadata.owner`, `self_approval = "deny"`).
- **REQ-4 (MUST):** The Terraform module (`ssp-module-gcs-bucket`) MUST render authoritative per-role `iam_bindings`, set `force_destroy = false`, output `cloud_resource_id`, and configure `drift_ignore_paths = ['/force_destroy']`.

## Guardrails

- **GR-1:** Never allow multi-region `"US"` on `gcs_bucket`; `location` MUST be `"us-east1"` in both `nonprod` and `prod`.
- **GR-2:** Never hardcode a single nonprod CMEK key across environments; always resolve `default_kms_key_name` via `(LOB, environment_type, "us-east1")` lookup (`GCS-ENC-001/002`).
- **GR-3:** Never allow `user:`, `allUsers`, `allAuthenticatedUsers`, or `roles/storage.admin` on a managed bucket.
- **GR-4:** Never set `force_destroy = true` (`GCS-DEL-001`) or auto-approve a bucket deletion in `nonprod` or `prod`.

## Consequences

### Positive

- Proves the complete four-gate data model (`idp` schema in AlloyDB + `gs://microdrive-dev-spp-tfstate` in GCS) on a real GCP resource (`gcs_bucket`) with full `guardrail_trace` and authoritative IAM drift detection.

### Negative / Trade-offs

- Because GCS retention policy and Object Versioning are mutually exclusive in Cloud Storage, buckets requiring retention lock/period (`GCS-RET-001`) keep `versioning = false` and rely on `soft_delete_policy` (`7` days, `GCS-SDP-001`) for accidental-delete recovery.

## Acceptance Criteria

- [ ] `ssp-cp` validates `gcs_bucket` requests against `gcs_bucket.schema.json` and `idp.gcp.gcs_bucket` Rego policies.
- [ ] `ssp-module-gcs-bucket` implements the `gcs_buckets` tfvars contract and passes `terraform test` (`mock_provider "google"`) and `opa test`.
- [ ] `idp.resource_kind` seed row for `gcs_bucket` is registered in `specs/data-model/spp_state_model.sql`.

## Success Criteria

- **SC-1:**
  - **Given** a `Requested` payload for `kind = "gcs_bucket"` with `name = "<lob>-nonprod-orders-landing-a1b2"` and `location = "us-east1"`
  - **When** approved by `metadata.owner` (`gcs_bucket_owner` gate) and reconciled by `su-gcp-<project_id>`
  - **Then** `approved_spec` and `guardrail_trace` contain `GCS-UBLA-001`, `GCS-PAP-001`, `GCS-ENC-001/002`, `GCS-RET-001`, `GCS-SDP-001`, `GCS-DEL-001`, `LBL-001`, and `PRQ-001/002`, `terraform.tfvars.json` is written to `gs://microdrive-dev-spp-tfstate`, and `resource_observed.projection` (`< 2000` bytes) is recorded in AlloyDB.
- **SC-2:**
  - **Given** a `gcs_bucket` request containing `user:alice@example.com`, `roles/storage.admin`, `location = "US"`, or `uniform_bucket_level_access = false`
  - **When** validated at the `Requested` gate
  - **Then** `ssp-cp` rejects the request before creating an approval workflow.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-SVC-001` (`gcs_bucket` four-gate contract and `GCS-*` guardrails) |
| `ssp-cp` | Implements `gcs_bucket` schema validation, `GCS-*` guardrail enrichment, and `gcs_bucket_owner` gate |
| `ssp-workers` | Executes `PRQ-001`/`PRQ-002` pre-apply tasks, `tf-<phase>-<20hex>` Jobs, and bucket drift comparison |
| `ssp-module-gcs-bucket` | Implements the `google_storage_bucket` + authoritative IAM Terraform module and `idp.gcp.gcs_bucket` Rego rules |
| `spp-factory-foundation` | Validates `gcs_bucket` schemas, Rego rules, and test vectors in `gates/` |

## Open Questions

- [x] **OQ-1 (CMEK Key URI in `microdrive-dev` / `us-east1` — RESOLVED / USER-SUPPLIED `TODO: vaishnavi4068`):** *Resolved:* In `microdrive-dev`, use placeholder `projects/microdrive-dev/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>` (`owner: vaishnavi4068`); in enterprise 2.0 projects, lookup `projects/<lob>-kms-<env>/locations/us-east1/keyRings/<lob>-<env>-use1/cryptoKeys/gcs-default` by `(LOB, environment_type, "us-east1")`.
- [ ] **OQ-2 (Unverified Source Gaps for `gcs_bucket` Seed Row & Examples — SOURCE GAP [Owner: Manoj]):** **Unverified (source gap):**
  1. In `idp_state_model.sql` lines 649–652, the `idp.resource_kind` seed row for `gcs_bucket` was partially cut off (only the tail `ARRAY['/force_destroy'], 'storage-bucket')` was visible; `tf_address_template = 'module.gcs_bucket["{name}"]'`, `opa_package = 'idp.gcp.gcs_bucket'`, `schema_uri = 'schemas/gcs_bucket.schema.json'`, and `tf_module_source` are inferred from the `spanner_instance` row and `resource-types.md`).
  2. `schemas/gcs_bucket.schema.json` and `examples/gcs_bucket.gates.json` were listed in the source file tree (photo 6548) but `[NOT CAPTURED]` in the photos.

## Related ADRs

- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](../global/ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-008: Label and Tag Standard](../global/ADR-GLB-008-label-and-tag-standard.md)
- [ADR-GLB-009: Resource Kind Registry](../global/ADR-GLB-009-resource-kind-registry.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](ADR-SVC-002-spanner-instance-and-database.md)
