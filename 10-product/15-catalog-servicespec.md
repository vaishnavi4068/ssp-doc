# 15 — Service Catalog and ServiceSpec

One ServiceSpec per service, owned by its `ssp-module-<service>` repo, released as a **catalog bundle**. The platform loads bundles at runtime, so adding a service is a publish, not a redeploy (D-17, SSP-PRIN-007).

## 1. Catalog bundle layout (published to `gs://ssp-catalog-<env>/<service_id>/<version>/`)

```
service.yaml                 ServiceSpec (this document)
request.schema.json          JSON Schema 2020-12 for buyer-settable params
ui.yaml                      step layout, field order, help, widgets (consumed by ssp-ui renderer)
pricing.yaml                 unit rates + formula for the estimate
policy/*.rego  policy/*_test.rego   service rules (request and plan stage)
module.zip                   the Terraform module at this version (mirrored from the repo tag)
docs/README.md               buyer-facing docs (rendered on the SKU page)
CHANGELOG.md
bundle.json                  {service_id, version, module_source, digests{...}, published_at, adr_id}
```

`gs://ssp-catalog-<env>/index.json` lists all services and versions; `ssp-cp` reloads it on Pub/Sub notification (`ssp-catalog-updates`) or `POST /v1/admin/catalog/reload`.

## 2. ServiceSpec — worked example `gcp.spanner-instance`

```yaml
apiVersion: ssp.catalog/v1
kind: ServiceSpec
metadata:
  id: gcp.spanner-instance
  version: 1.2.0
  displayName: Cloud Spanner instance
  category: database
  cloud: gcp
  adr: E-SPAN-0001
  ownerMailbox: ssp-databases@example.com
  tags: [database, relational, global]
spec:
  tenantBoundary: project
  resourceTypes: [google_spanner_instance, google_spanner_database, google_spanner_instance_iam_member, google_kms_crypto_key_iam_member]
  request:
    schema: request.schema.json
    nameField: name                       # stable name; also the Terraform module block key
  context:                                # what the platform supplies to derive rules, policy and rendering
    needs: [apm.tier, apm.data_class, tenant.region_allowlist, lob.cmek_key, tenant.cost_center]
  derive:                                 # evaluated before the form is shown (SSP-PROD-030)
    - field: /config/mode
      when: "apm.tier == 1"
      value: multi-region
      reason: "Tier 1 databases are multi-region (G-0007 §3)"
      requirementId: REQ-E-SPAN-0001-04
    - field: /encryption/kmsKeyName
      value: "{{ lob.cmek_key }}"
      requirementId: REQ-E-SPAN-0001-02
  guardrails:                             # applied at approval (SSP-PROD-020); mode inject|deny|warn
    - id: REQ-E-SPAN-0001-02
      field: /encryption/kmsKeyName
      mode: inject
      value: "{{ lob.cmek_key }}"
    - id: REQ-E-SPAN-0001-05
      field: /labels
      mode: inject
      value: { apm_id: "{{ tenant.apm_id }}", cost_center: "{{ tenant.cost_center }}", lob: "{{ tenant.lob_id }}", env: "{{ tenant.env }}", data_class: "{{ apm.data_class }}", managed_by: ssp }
    - id: REQ-E-SPAN-0001-06
      field: /config/processingUnits
      mode: deny
      when: "params.config.processingUnits < 100 || params.config.processingUnits % 100 != 0"
      message: "Processing units must be a multiple of 100 (minimum 100)"
    - id: REQ-E-SPAN-0001-07
      field: /deletionProtection
      mode: inject
      when: "tenant.env == 'prod'"
      value: true
      relaxable: false
  terraform:
    module: ssp-module-spanner
    source: "gcs::https://www.googleapis.com/storage/v1/ssp-modules-{{ env }}/ssp-module-spanner/1.2.0/module.zip"
    versionConstraint: "~> 1.2"
    inputsFrom: /                         # approved params map 1:1 to module variables (renderer enforces)
    outputs: [instance_id, instance_name, databases, connection_hint]   # non-secret only
    providers: { google: ">= 6.0, < 7.0" }
  secrets: []                             # none for Spanner; services with secrets list {field, generate|reference, secretManagerPath}
  pricing: pricing.yaml
  ui: ui.yaml
  postBuild:
    - step: cmdb.register
      ciClass: cmdb_ci_cloud_database
    - step: monitoring.onboard
    - step: notify.team
  lifecycle:
    holdsData: true
    ownerSignoff: { change: false, decommission: true }
    delete: { mode: soft, retentionDays: 30 }    # soft = enable deletion protection + keep 30d, then remove
    drift: { autoRevert: false, benignAttributes: [labels.last_scan] }
  sla: { provisionP95Minutes: 15 }
  docs: docs/README.md
```

## 3. `request.schema.json` (excerpt)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ssp/catalog/gcp.spanner-instance/1.2.0/request.schema.json",
  "type": "object",
  "required": ["name", "config", "databases"],
  "additionalProperties": false,
  "properties": {
    "name": {"type": "string", "pattern": "^[a-z][a-z0-9-]{2,28}$", "title": "Instance name"},
    "config": {
      "type": "object", "required": ["mode", "processingUnits"],
      "properties": {
        "mode": {"type": "string", "enum": ["regional", "multi-region"], "title": "Configuration"},
        "region": {"type": "string", "title": "Region", "x-ssp-enumFrom": "tenant.region_allowlist"},
        "multiRegionConfig": {"type": "string", "enum": ["nam3", "nam6", "nam-eur-asia1"], "title": "Multi-region config"},
        "processingUnits": {"type": "integer", "minimum": 100, "maximum": 10000, "multipleOf": 100, "default": 100}
      },
      "allOf": [
        {"if": {"properties": {"mode": {"const": "regional"}}}, "then": {"required": ["region"]}},
        {"if": {"properties": {"mode": {"const": "multi-region"}}}, "then": {"required": ["multiRegionConfig"]}}
      ]
    },
    "databases": {
      "type": "array", "minItems": 1, "maxItems": 20,
      "items": {"type": "object", "required": ["name", "dialect"],
        "properties": {"name": {"type": "string", "pattern": "^[a-z][a-z0-9_-]{1,29}$"},
                       "dialect": {"type": "string", "enum": ["GOOGLE_STANDARD_SQL", "POSTGRESQL"], "default": "GOOGLE_STANDARD_SQL"},
                       "versionRetentionPeriod": {"type": "string", "default": "7d"}}}
    },
    "encryption": {"type": "object", "properties": {"kmsKeyName": {"type": "string", "readOnly": true}}, "x-ssp-derived": true},
    "deletionProtection": {"type": "boolean", "default": true},
    "labels": {"type": "object", "additionalProperties": {"type": "string"}, "x-ssp-derived": true},
    "ops": {"type": "object", "x-ssp-persona": "operator", "properties": {"forceDestroy": {"type": "boolean", "default": false}}}
  }
}
```

Vendor extensions: `x-ssp-derived` (shown read-only with reason), `x-ssp-persona` (field visible/settable only for that persona; SSP-PROD-101), `x-ssp-enumFrom` (options from context), `x-ssp-secret` (accept only `secretmanager://` references), `x-ssp-widget` (UI hint).

## 4. `ui.yaml` (excerpt)

```yaml
steps:
  - id: basics
    title: Basics
    description: Name the instance and choose where it runs.
    fields: [/name, /config/mode, /config/region, /config/multiRegionConfig]
  - id: capacity
    title: Capacity
    fields: [/config/processingUnits]
    summary: "{{ params.config.processingUnits }} PU · {{ params.config.mode }}"
  - id: databases
    title: Databases
    fields: [/databases]
    widget: { /databases: table }
  - id: protection
    title: Protection & encryption
    fields: [/encryption/kmsKeyName, /deletionProtection]
  - id: review
    title: Review
receipt:
  title: Infrastructure Order Summary
  lines: [compute, storage, backup]        # keys from pricing.yaml
  showCode: true                           # View as code tab (D-17)
frequentPresets:
  - { label: "Dev regional 100 PU", params: { config: { mode: regional, processingUnits: 100 } } }
  - { label: "Prod multi-region 1000 PU", params: { config: { mode: multi-region, multiRegionConfig: nam3, processingUnits: 1000 } } }
```

## 5. `pricing.yaml` (excerpt)

```yaml
version: 2026-10
currency: USD
lines:
  compute: { label: "Processing units", unit: "100 PU-month", quantity: "params.config.processingUnits / 100",
             rate: { regional: 65.70, multi-region: 270.0 }, rateKey: "params.config.mode" }
  storage: { label: "Storage (est. 100 GB)", unit: "GB-month", quantity: "100", rate: 0.30 }
  backup:  { label: "Backup (est. 100 GB)", unit: "GB-month", quantity: "100", rate: 0.10 }
disclaimer: "Estimate from list prices; actuals billed by cloud provider to cost center."
```

## 6. Validation rules

- SSP-CAT-001 `service.yaml` validates against `15-service-spec.schema.json`; `request.schema.json` compiles; every `derive`/`guardrail` field exists in the schema; every `ui.yaml` field exists; every `pricing` expression references existing params.
- SSP-CAT-002 `resourceTypes` is exhaustive: the plan-stage rule SSP-POL-202 denies anything else.
- SSP-CAT-003 Module variables = request schema properties (names and types) plus platform-injected `labels`, `project_id`, `kms_key_name` where declared; `catalogctl validate` runs `terraform-config-inspect` to enforce.
- SSP-CAT-004 A bundle version is immutable; fixes are new versions. Deprecation sets `deprecated: true` and a `successor` version; buyers see the latest non-deprecated version.
- SSP-CAT-005 Secrets: if `spec.secrets` is non-empty, each entry is `{field, mode: generate|reference, path: "secretmanager://projects/{{tenant.project}}/secrets/<name>"}`; the renderer passes only the reference to Terraform (`ephemeral`/write-only attributes where the provider supports them).
