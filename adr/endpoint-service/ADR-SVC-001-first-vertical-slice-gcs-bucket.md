# ADR-SVC-001: First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails

- **ADR ID:** ADR-SVC-001
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-storage-gcp@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-gcs-bucket` (`ssp-module-gcs`), `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the end-to-end four-gate contract (`Requested` → `Approved` → `Expected` → `Observed`), intake value normalization, schema rejections, guardrail rules (`GCS-UBLA-001`, `GCS-PAP-001`, `GCS-ENC-001/002`, `GCS-RET-001`, `GCS-RET-003`, `GCS-SDP-001`, `GCS-DEL-001`, `GCS-NAME-001..003`, `LBL-001/002`, `PRQ-001/002`), optional user-configurable object lifecycle rules (default **NONE**), human approval gate (`gcs_bucket_owner` v1), `tfvars` entry shape (`gcs_buckets`, `module.gcs_bucket["{name}"]`, seconds conversions, `autoclass = false`), projection-hash change detection, and out-of-band drift example for SPP's **first vertical slice**: provisioning a **Google Cloud Storage bucket (`kind = "gcs_bucket"`, `google_storage_bucket`)** in region **`us-east1`** into `gs://microdrive-dev-spp-tfstate`, with **no UI**.

## Context

From the design session (`uploads/design-digest.md`), build order (`ADR-BP-002`), the sanitized four-gate design package (`resource-types.md` §6, `gates.md` §6, and `specs/examples/gcs_bucket.gates.json`; see [`docs/source-provenance.md`](../../docs/source-provenance.md)), and user overrides:

1. **Why `gcs_bucket` Is the First Vertical Slice:** Exercises every layer of the four-gate architecture (intake submission + value normalization, closed JSON Schema validation, `RequestWorkflow` `req-<request_id>`, `ApprovalGateWorkflow` with `gcs_bucket_owner` v1 by `bucket_owner`, OPA guardrail mutations + `guardrail_trace`, `pre_apply`/`post_apply` tasks, `StateUnitReconcilerWorkflow` `su-gcp-<project_id>`, deterministic K8s Jobs `tf-plan-<20hex>` / `tf-apply-<20hex>` in `spp-platform`, `Expected` revision in `gs://microdrive-dev-spp-tfstate/projects/<project_id>/expected/rev-NNNNNN/`, and `<= 2 KB` `Observed` projection in AlloyDB with projection-hash upsert-on-change) with **no UI**.
2. **User Overrides Applied to `gcs_bucket`:**
   - **Region `us-east1` Only (No Multi-Region `US`):** Although the source example showed `"location": "US"` and CMEK key path in `locations/us`, SPP's locked override restricts all GCP resources (including `prod`) to single region **`us-east1`** (`"location": "us-east1"`, CMEK key in `locations/us-east1`).
   - **Environment Token `nonprod` & Dropping `environmentsubtype`:** Only `nonprod` (no hyphen) and `prod` exist; the `environmentsubtype` label is **dropped entirely everywhere**, leaving `environmenttype` (`nonprod` | `prod`) as one of the **8 mandatory labels** (`ADR-GLB-008`).
   - **Single State Bucket Retaining Folder Layout:** Uses `gs://microdrive-dev-spp-tfstate` with the folder layout `projects/<project_id>/{expected/rev-N, logs, observed/scan-*, default.tfstate}`.
   - **Runner Namespace `spp-platform`:** Terraform Jobs run in `spp-platform` (not `idp-runners`).
   - **Object Lifecycle Rules Default to NONE (`[]`):** The source example included a default 365-day object auto-delete rule (`{"action": {"type": "Delete"}, "condition": {"age_days": 365, "with_state": "ANY"}}`). **User decision overrides this:** object `lifecycle_rules` default to **NONE (`[]`)** and are exposed as **optional user-configurable options** on the `gcs_bucket` request (e.g., delete objects after `N` days, transition storage class after `N` days, delete noncurrent versions after `N` days / `num_newer_versions`), validated by policy at request time, and approved through the normal `gcs_bucket_owner` approval gate. Bucket resource deletion (`action = "delete"`) still always requires explicit human approval in any environment.
   - **Out-of-Scope Items Skipped:** Legacy shim/FormData (`channel = "legacy_shim"`), `legacy_equivalent` section, CMDB (`cmdb_register`), data-portal registration (`dataportal_register`), and external group-provisioning provider details are out of scope and omitted.

## Decision

### 1. Intake Value Normalization & Gate 1 (`Requested`) Contract

1. **Intake Value Normalization:**
   Before or during mapping to the canonical `Requested` document (`idp.request.requested_spec`), intake normalizes raw caller inputs:
   - `data_sensitivity`: `"restrict"` → `"restricted"`
   - `apm_id`: `"APM0017299"` (uppercase) → `"apm0017299"` (lowercase `^apm[0-9]{7}$`)
   - `lob`: `"<LOB>"` (uppercase) → `"<lob>"` (lowercase `^[a-z][a-z0-9]{1,5}$`)
   - `environment`: `"sandbox" | "dev" | "qa" | "test" | "pdev" | "pqa" | "preprod"` → `"nonprod"`; `"prod"` → `"prod"`
2. **Canonical `Requested` Document (`specs/examples/gcs_bucket.gates.json`):**
   - `request_id = "22120aab-3834-51d3-b631-0f7d3c43f56e"`, `submission_id = "b764125e-fcae-55bd-b6b7-10cf882fcc8d"`, `resource_id = "9478bcfc-c2cf-583b-8bd8-096476647840"`, `temporal_workflow_id = "req-22120aab-3834-51d3-b631-0f7d3c43f56e"`.

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
    "shared_mailbox": "<lob>-orders-team@example.com",
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
    "lifecycle_rules": [],
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

3. **Optional User-Configurable Object `lifecycle_rules` (Default `[]` / NONE):**
   - By default, `spec.lifecycle_rules` is `[]` (no automatic object deletion or transition; the source's default 365-day auto-delete is removed).
   - Callers MAY optionally supply one or more `lifecycle_rules` at request time:
     - **Delete objects after `N` days:** `{"action": {"type": "Delete"}, "condition": {"age_days": <N>, "with_state": "ANY" | "LIVE" | "ARCHIVED"}}` (where `age_days >= retention_days` when a retention policy is active).
     - **Transition storage class after `N` days:** `{"action": {"type": "SetStorageClass", "storage_class": "NEARLINE" | "COLDLINE" | "ARCHIVE"}, "condition": {"age_days": <N>}}`.
     - **Delete noncurrent object versions:** `{"action": {"type": "Delete"}, "condition": {"days_since_noncurrent_time": <N>, "num_newer_versions": <K>, "with_state": "ARCHIVED"}}` (when `versioning: true`).
   - All user-requested `lifecycle_rules` are validated by schema and OPA policy at the `Requested` and `Approved` gates and approved by `bucket_owner` through the standard `gcs_bucket_owner` approval gate.
4. **Schema & Policy Rejections at the `Requested` Gate:**
   - Rejects IAM members other than `group:` and `serviceAccount:` (no `user:`, `allUsers`, `allAuthenticatedUsers`).
   - Rejects IAM roles outside the bucket allowlist (no `roles/storage.admin`, no legacy owner roles).
   - Rejects unknown or guardrail-owned fields (`uniform_bucket_level_access`, `public_access_prevention`, `kms_key_name`, `retention_days`, `retention_locked`, `soft_delete_retention_days`, `force_destroy`) so callers cannot weaken guardrails or inject secret-bearing fields.
   - Rejects combining a bucket retention policy with `versioning: true` (mutually exclusive in Cloud Storage).
   - Enforces `GCS-NAME-001..003`, `NAM-RSV-001`, and `location == "us-east1"`.

### 2. Gate 2 (`Approved`) Guardrail Rules, `guardrail_trace`, and Approval Gate (`gcs_bucket_owner` v1)

At the `Approved` gate (`approval_id = "761d8bf8-d23e-5da3-8e52-02e6eb6c2afb"`, `gate_key = "gcs_bucket_owner"`, `gate_version = 1`, `policy_bundle_revision = "3f9a1c2"`):
- `metadata.resolved` is populated: `{"app_tier": "2", "environment_type": "nonprod", "vpc_sc_perimeter": "<lob>_nonprod_restricted_perimeter", "cost_center_validated": true, "resolved_at": "2026-10-21T14:02:13Z"}`.
- `bucket_owner` (`bucket.owner@example.com`, resolved from `/metadata/owner`) approves via `ApprovalGateWorkflow` (`self_approval = "deny"`).
- `guardrail_trace` records every enforced guardrail rule:

| Rule ID | Path | `from` → `to` | Verbatim / Adapted Reason in `guardrail_trace` |
| :--- | :--- | :--- | :--- |
| **`GCS-UBLA-001`** | `/spec/uniform_bucket_level_access` | `null` → `true` | `"Uniform bucket-level access is mandatory. Legacy form value 'false' was not car[ried...]"` |
| **`GCS-PAP-001`** | `/spec/public_access_prevention` | `null` → `"enforced"` | *Unverified (source gap: lines 332–335 not captured in photo; `"enforced"` confirmed from `approved.document.spec.public_access_prevention`).* |
| **`GCS-ENC-001` (`002`)** | `/spec/kms_key_name` | `null` → `"projects/<lob>-kms-nonprod/locations/us-east1/keyRings/<lob>-nonprod-use1/cryptoKeys/gcs-default"` *(or `projects/<spp-factory-host-project-id>/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>`)* | `"CMEK resolved by (lob=<lob>, environment_type=nonprod, location=us-east1); key location 'us-east1' matches buc[ket...]"` *(overridden from `US` to `us-east1`)*. |
| **`GCS-RET-001`** | `/spec/retention_days` | `null` → `90` | `"Retention floor for restricted data (illustrative value; set by the GCS ADR). Versioning stays off [...]"` |
| **`GCS-RET-003`** | `/spec/retention_locked` | `null` → `false` | `"Locks are irreversible and only applied on an explicit records-management request."` |
| **`GCS-SDP-001`** | `/spec/soft_delete_retention_days` | `null` → `7` | `"Soft-delete window for accidental deletes."` |
| **`GCS-DEL-001`** | `/spec/force_destroy` | `null` → `false` | `"The platform never force-destroys a bucket with objects in it."` |
| **`LBL-001` (`002`)** | `/metadata/labels` | `{"app": "orders"}` → effective 12-key label map (8 mandatory + `app`, `dataclassification`, `sharedemailaddress`, `tenancy`) | `"Mandatory labels merged with user labels; one key set for every kind."` (`@` and `.` in `owner` and `sharedemailaddress` normalized to `_`; `environmentsubtype` dropped per override). |
| **`PRQ-001`** | `/prerequisites/0` | `null` → `"ad_group"` (`target = "group:gcp-<lob>-nonprod-orders-read@example.com"`) | `"The read group must exist before the IAM binding [truncated]"` |
| **`PRQ-002`** | `/prerequisites/1` | `null` → `"vpc_sc_ingress"` (`target = "group:gcp-<lob>-nonprod-orders-read@example.com"`, `params.perimeter = "<lob>_nonprod_restricted_perimeter"`) | *Unverified (source gap: lines 384–428 not captured in photo; prerequisite confirmed from `approved.document.prerequisites`).* |

- **Materialized `idp.lifecycle_task` Rows:**
  - `pre_apply`: `ad_group:group:gcp-<lob>-nonprod-orders-read@example.com` (`PRQ-001`) and `vpc_sc_ingress:group:gcp-<lob>-nonprod-orders-read@example.com` (`PRQ-002`).
  - `post_apply`: `notify_owner:bucket.owner@example.com` (`status = "SUCCEEDED"`). *(Note: out-of-scope `dataportal_register` and `cmdb_register` tasks shown in the source photo are skipped per user override.)*

### 3. Gate 3 (`Expected`) Composed `tfvars` Entry, Conversions, and Operations

In `gs://microdrive-dev-spp-tfstate/projects/<lob>-nonprod-orders-svc/expected/rev-000001/terraform.tfvars.json` (`revision_id = "fa5d29a6-b406-5b66-81f2-8e45d24fb019"`, `state_unit_id = "af42f828-3378-5ee2-8e9b-2378d2314f97"`, `revision_no = 1`, `plan_summary = {"add": 3, "change": 0, "destroy": 0, "replace": 0}`):
- **Collection & Address:** `tfvars_collection = "gcs_buckets"`, `tfvars_key = "<lob>-nonprod-orders-landing-a1b2"`, `tf_address = "module.gcs_bucket[\"<lob>-nonprod-orders-landing-a1b2\"]"` (confirming `tf_address_template = 'module.gcs_bucket["{name}"]'`).
- **Unit & Field Conversions (`Approved` → `Expected` `tfvars`):**
  - `retention_days: 90` + `retention_locked: false` → `retention_policy: {"retention_period": 7776000, "is_locked": false}` (`90 * 86400 = 7776000` seconds).
  - `soft_delete_retention_days: 7` → `soft_delete_policy: {"retention_duration_seconds": 604800}` (`7 * 86400 = 604800` seconds).
  - If optional `lifecycle_rules` are present, `condition.age_days` converts to `condition.age` (integer days for the Terraform provider); default is `lifecycle_rules: []`.
  - `kms_key_name` → `default_kms_key_name`.
  - `autoclass: false` is explicitly added.
  - `access` array → authoritative per-role `iam_bindings` map.
- **Terraform Runner Operations (`idp.tf_operation` in namespace `spp-platform`):**
  - **Plan:** `operation_id = "op:af42f828-3378-5ee2-8e9b-2378d2314f97:r1:plan:1"`, `k8s_job_name = "tf-plan-eba5f9ebf4fafecad8e9"`, `status = "SUCCEEDED"`, `tf_exit_code = 2`, `state_serial_before = 0`, `state_serial_after = 0`, `logs_uri = "gs://microdrive-dev-spp-tfstate/projects/<lob>-nonprod-orders-svc/logs/tf-plan-eba5f9ebf4fafecad8e9.log"`.
  - **Apply:** `operation_id = "op:af42f828-3378-5ee2-8e9b-2378d2314f97:r1:apply:1"`, `k8s_job_name = "tf-apply-b85d57b4511c03e98373"`, `status = "SUCCEEDED"`, `tf_exit_code = 0`, `state_serial_before = 0`, `state_serial_after = 3`.

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
  "lifecycle_rules": [],
  "labels": {
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

### 4. Gate 4 (`Observed`) Projection, Upsert-on-Change, and Critical PAP Drift Example

1. **Post-Apply Observation & Projection-Hash Change Detection:**
   - `idp.observation` (`observation_id = "f75d522f-53ab-5026-8eca-7150ab0cb0cb"`, `source = "post_apply"`, `operation_id = "op:af42f828-3378-5ee2-8e9b-2378d2314f97:r1:apply:1"`, `state_uri = "gs://microdrive-dev-spp-tfstate/projects/<lob>-nonprod-orders-svc/default.tfstate"`, `state_serial = 3`, `drift_detected = false`).
   - `idp.resource_observed` stores `cloud_resource_id = "projects/_/buckets/<lob>-nonprod-orders-landing-a1b2"`, `exists_in_cloud = true`, and `projection` (`< 2000` bytes, including `self_link`, `url`, `time_created`, and all bucket attributes minus `/force_destroy`).
   - **Upsert-on-Change Behavior:** When a subsequent revision (`rev-000002`, which adds Spanner to the same project) applies and re-observes this bucket, `ssp-workers` computes `projection_sha256`, finds it identical to `ro.projection_sha256`, and **writes nothing** (`WHERE ro.projection_sha256 IS DISTINCT FROM EXCLUDED.projection_sha256`).
2. **Out-of-Band Drift Example (`public_access_prevention` Flipped to `"inherited"`):**
   - **Scenario:** Someone switches `public_access_prevention` from `"enforced"` to `"inherited"` in the GCP Console.
   - **Refresh Scan Job (`tf_operation`):** `operation_id = "op:af42f828-3378-5ee2-8e9b-2378d2314f97:r2:refresh_plan:2026-10-23T06"`, `revision_id = "77b88e4c-84fe-5050-a395-060f012d17f0"`, `phase = "refresh_plan"`, `run_key = "2026-10-23T06"`, `k8s_namespace = "spp-platform"`, `k8s_job_name = "tf-refresh-plan-415a15a935cbd63f95e1"`, `tf_exit_code = 2`, `state_serial_before = 6`, `state_serial_after = 6`.
   - **Observation Row (`idp.observation`):** `observation_id = "58f1ad89-2e29-5b67-97f9-67bde1276ac4"`, `source = "refresh_plan"`, `snapshot_uri = "gs://microdrive-dev-spp-tfstate/projects/<lob>-nonprod-orders-svc/observed/scan-2026-10-23T06/plan.json"`, `drift_detected = true`.
   - **Drift Finding Row (`idp.drift_finding` — Alert-Only):**
     ```json
     {
       "drift_id": "bc02e690-5151-57ea-b6e1-115e926402c0",
       "resource_id": "9478bcfc-c2cf-583b-8bd8-096476647840",
       "observation_id": "58f1ad89-2e29-5b67-97f9-67bde1276ac4",
       "revision_id": "77b88e4c-84fe-5050-a395-060f012d17f0",
       "drift_kind": "out_of_band_change",
       "attribute_path": "/public_access_prevention",
       "expected_value": "enforced",
       "observed_value": "inherited",
       "severity": "critical",
       "guardrail_rule_id": "GCS-PAP-001",
       "status": "OPEN",
       "detected_at": "2026-10-23T06:03:27Z"
     }
     ```
   - Because `GCS-PAP-001` is a security guardrail, `guardrail_rule_id = "GCS-PAP-001"` and `severity = "critical"`, with `status = "OPEN"` (**alert-only**, never auto-reapplied).

## Requirements

- **REQ-1 (MUST):** The first vertical slice (`kind = "gcs_bucket"`) MUST operate end-to-end via the `ssp-cp` REST API through all four gates (`REQUESTED -> APPROVED -> EXPECTED -> OBSERVED`) with **no UI dependency**, matching the contract in [`specs/examples/gcs_bucket.gates.json`](../../specs/examples/gcs_bucket.gates.json).
- **REQ-2 (MUST):** At intake and the `Requested` gate, `ssp-cp` MUST normalize input values (`"restrict" -> "restricted"`, `"APM..." -> "apm..."`, `"<LOB>" -> "<lob>"`, env codes -> `"nonprod" | "prod"`), reject IAM members other than `group:` and `serviceAccount:`, reject roles outside the bucket allowlist, reject unknown/guardrail-owned fields, enforce `location == "us-east1"`, and reject retention policy combined with `versioning = true`.
- **REQ-3 (MUST):** Object `lifecycle_rules` on `gcs_bucket` MUST default to **`[]` (NONE)** (no default 365-day auto-delete), and MAY be supplied as optional user-configurable rules (e.g., object `Delete` after `age_days`, `SetStorageClass` after `age_days`, noncurrent version `Delete` after `days_since_noncurrent_time` / `num_newer_versions`), validated by policy at `Requested`/`Approved` and approved through `gcs_bucket_owner`.
- **REQ-4 (MUST):** At the `Approved` gate, `ssp-cp` MUST enforce and record in `guardrail_trace`: `GCS-UBLA-001` (`true`), `GCS-PAP-001` (`"enforced"`), `GCS-ENC-001` (CMEK lookup by `(lob, environment_type, location="us-east1")`), `GCS-RET-001` (`90` days when versioning is `false`), `GCS-RET-003` (`retention_locked = false` unless an explicit records-management request is approved), `GCS-SDP-001` (`7` days), `GCS-DEL-001` (`force_destroy = false`), `LBL-001/002` (8 mandatory labels merged and normalized, without `environmentsubtype`), and `PRQ-001/002`, gated by `gcs_bucket_owner` v1 (`bucket_owner`, `self_approval = "deny"`).
- **REQ-5 (MUST):** When rendering `Expected` `tfvars` (`tfvars_collection = "gcs_buckets"`, `tf_address = "module.gcs_bucket[\"{name}\"]"`), `ssp-workers` MUST convert `retention_days` (`90`) to `retention_policy.retention_period` (`7776000` seconds), `soft_delete_retention_days` (`7`) to `soft_delete_policy.retention_duration_seconds` (`604800` seconds), `age_days` to `age`, set `autoclass = false`, and render authoritative per-role `iam_bindings`.
- **REQ-6 (MUST):** `ssp-workers` MUST record `post_apply` and `refresh_plan` observations in `idp.observation`, upsert `idp.resource_observed` (`cloud_resource_id = "projects/_/buckets/<name>"`) only when `projection_sha256` changes, and record out-of-band `public_access_prevention` changes as `critical` `OPEN` findings (`guardrail_rule_id = "GCS-PAP-001"`, alert-only).

## Guardrails

- **GR-1:** Never allow multi-region `"US"` on `gcs_bucket`; `location` MUST be `"us-east1"` in both `nonprod` and `prod`, and CMEK key location MUST be `us-east1` (`GCS-ENC-001`).
- **GR-2 (`GCS-RET-003`):** Never set `retention_policy.is_locked = true` (`retention_locked = true`) unless explicitly requested and approved via a records-management workflow, because GCS retention locks are irreversible.
- **GR-3 (`GCS-DEL-001`):** Never set `force_destroy = true`, never inject an unrequested default object auto-delete lifecycle rule, and never allow bucket resource deletion (`action = "delete"`) without explicit human approval in any environment.
- **GR-4:** Never emit the dropped `environmentsubtype` label on any resource.

## Consequences

### Positive

- Full alignment with [`specs/examples/gcs_bucket.gates.json`](../../specs/examples/gcs_bucket.gates.json), proving every table in `idp` (`submission`, `request`, `approval`, `lifecycle_task`, `expected_revision`, `expected_revision_member`, `tf_operation`, `observation`, `resource_observed`, `drift_finding`) on `gcs_bucket`.
- Removing the silent 365-day object auto-delete default prevents unexpected data deletion while still allowing application teams to configure explicit object lifecycle rules (`Delete`, `SetStorageClass`, noncurrent cleanup) through normal policy and owner approval.
- `GCS-RET-003` (`retention_locked = false`) prevents irreversible bucket lock-in from routine provisioning requests.

### Negative / Trade-offs

- Requires a valid Cloud KMS CryptoKey in `us-east1` before live `terraform apply` can succeed in `<spp-factory-host-project-id>`.

## Acceptance Criteria

- [ ] `specs/examples/gcs_bucket.gates.json` is committed in `ssp-doc` with `us-east1`, `spp-platform`, `gs://microdrive-dev-spp-tfstate/projects/<project>/...`, no `environmentsubtype` label, `lifecycle_rules: []` default, `GCS-RET-003`, and the `GCS-PAP-001` critical drift scenario.
- [ ] `ssp-cp` validates `gcs_bucket` requests (including optional `lifecycle_rules`) and populates `guardrail_trace` (`GCS-UBLA-001`, `GCS-PAP-001`, `GCS-ENC-001`, `GCS-RET-001`, `GCS-RET-003`, `GCS-SDP-001`, `GCS-DEL-001`, `LBL-001`, `PRQ-001/002`).
- [ ] `ssp-module-gcs-bucket` implements `module.gcs_bucket["{name}"]` consuming the `gcs_buckets` tfvars shape and passes `terraform test` and `opa test`.

## Success Criteria

- **SC-1:**
  - **Given** a `gcs_bucket` create request for `<lob>-nonprod-orders-landing-a1b2` in `us-east1` with no `lifecycle_rules` specified
  - **When** approved by `bucket_owner` (`gcs_bucket_owner` v1) and applied by `tf-apply-b85d57b4511c03e98373` in namespace `spp-platform`
  - **Then** `lifecycle_rules` is `[]`, `retention_policy` is `{"retention_period": 7776000, "is_locked": false}` (`GCS-RET-001`, `GCS-RET-003`), `soft_delete_policy` is `{"retention_duration_seconds": 604800}` (`GCS-SDP-001`), `autoclass` is `false`, `cloud_resource_id` is `"projects/_/buckets/<lob>-nonprod-orders-landing-a1b2"`, and a subsequent unchanged revision (`rev-000002`) performs zero writes to `idp.resource_observed`.
- **SC-2:**
  - **Given** an out-of-band console change switching `public_access_prevention` from `"enforced"` to `"inherited"` on `<lob>-nonprod-orders-landing-a1b2`
  - **When** the scheduled refresh scan Job `tf-refresh-plan-415a15a935cbd63f95e1` runs
  - **Then** `idp.observation` records `drift_detected = true` and `idp.drift_finding` records `drift_kind = "out_of_band_change"`, `attribute_path = "/public_access_prevention"`, `expected_value = "enforced"`, `observed_value = "inherited"`, `severity = "critical"`, `guardrail_rule_id = "GCS-PAP-001"`, and `status = "OPEN"` without auto-reapplying.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-SVC-001` and `specs/examples/gcs_bucket.gates.json` |
| `ssp-cp` | Implements intake normalization, `gcs_bucket` validation, optional `lifecycle_rules` validation, `GCS-*` guardrail enrichment, and `gcs_bucket_owner` v1 gate |
| `ssp-workers` | Executes `PRQ-001`/`PRQ-002` pre-apply tasks, `tf-<phase>-<20hex>` Jobs in `spp-platform`, projection-hash upsert-on-change, and bucket drift comparison |
| `ssp-module-gcs-bucket` | Implements `module.gcs_bucket["{name}"]` (`gcs_buckets` tfvars shape) and `idp.gcp.gcs_bucket` Rego policies |
| `spp-factory-foundation` | Validates `specs/examples/gcs_bucket.gates.json`, `k8s_job_name` derivations, and Rego rules in `gates/` |

## Open Questions

- [x] **OQ-1 (CMEK Key URI in `<spp-factory-host-project-id>` / `us-east1` — RESOLVED / USER-SUPPLIED `TODO: vaishnavi4068`):** *Resolved:* In `<spp-factory-host-project-id>`, use placeholder `projects/<spp-factory-host-project-id>/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>`; in enterprise 2.0 projects, lookup `projects/<lob>-kms-<env>/locations/us-east1/keyRings/<lob>-<env>-use1/cryptoKeys/gcs-default` by `(lob, environment_type, location="us-east1")`.
- [x] **OQ-2 (Object Lifecycle Rules Default vs. Optional — OVERRIDDEN BY USER DECISION 2026-10-21):** *Resolved:* Object `lifecycle_rules` default to **NONE (`[]`)** (removing the source's 365-day auto-delete default) and are exposed as optional user-configurable options on the `gcs_bucket` request, validated by policy and approved via `gcs_bucket_owner`.
- [x] **OQ-3 (Retention Lock Rule `GCS-RET-003` — CONFIRMED FROM SOURCE 2026-10-21):** *Resolved:* `GCS-RET-003` sets `/spec/retention_locked = false` (`retention_policy.is_locked = false`) because locks are irreversible and only applied on an explicit records-management request.
- [ ] **OQ-4 (Unverified Source Gaps in `examples/gcs_bucket.gates.json` & `gcs_bucket.schema.json` — SOURCE GAP [Owner: Manoj]):** **Unverified (source gap):**
  1. In `examples/gcs_bucket.gates.json` (~85% captured across photos `IMG_6593..6610`, with `IMG_6601` missing), line ranges `~47-51`, `91-101`, `145-149`, `193-196`, `240-243`, `288-290`, `332-335` (`GCS-PAP-001` trace reason), `384-428` (`PRQ-002` trace and `pre_apply` `lifecycle_task` rows), `562-566` (`apply` `state_serial_after`), `650-655` (`resource_observed` tail), and `788-888` were `[NOT CAPTURED]`.
  2. Whether a rule `GCS-RET-002` exists between `GCS-RET-001` and `GCS-RET-003` is unverified (not present in the captured `guardrail_trace`).
  3. `schemas/gcs_bucket.schema.json` was listed in the source file tree (`IMG_6548`) but `[NOT CAPTURED]` in either photo bundle.

## Related ADRs

- [ADR-GLB-003: Four-Gate Provisioning State Model and Storage Layout](../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-004: Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL)](../global/ADR-GLB-004-data-model-and-database.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](../global/ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-008: Label and Tag Standard](../global/ADR-GLB-008-label-and-tag-standard.md)
- [ADR-GLB-009: Resource Kind Registry](../global/ADR-GLB-009-resource-kind-registry.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](ADR-SVC-002-spanner-instance-and-database.md)
