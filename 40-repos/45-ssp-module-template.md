# 45 — `ssp-module-<service>` Template (worked example: `ssp-module-spanner`)

One repository per Terraform service module (D-18). Each repo is a complete, self-describing **catalog bundle source**: the module, its ServiceSpec, request schema, UI template, pricing, policies, import mapping, tests and docs. The platform learns about a service only through the published bundle.

```
ssp-module-spanner/
├── AGENTS.md  .cursor/rules/  CODEOWNERS  Makefile  CHANGELOG.md  README.md (buyer docs; copied to bundle docs/)
├── catalog/
│   ├── service.yaml                 ServiceSpec (15-catalog-servicespec.md §2) — metadata.id gcp.spanner-instance
│   ├── request.schema.json          buyer-settable params (§3)
│   ├── ui.yaml                      steps, widgets, receipt lines, presets (§4)
│   └── pricing.yaml                 estimate model (§5)
├── policy/
│   ├── request.rego                 package ssp.request.svc.spanner_instance
│   ├── plan.rego                    package ssp.plan.svc.spanner_instance   (verifies every MUST guardrail on plan JSON)
│   └── *_test.rego                  ≥ 90 % coverage; allow + deny fixtures per rule
├── import/
│   └── mapping.yaml                 asset type → module address + attribute → param extraction (used by ssp-migrate)
├── main.tf  variables.tf  outputs.tf  versions.tf   the module (root of repo so `source` points at the repo/zip)
├── examples/{minimal,prod-multi-region}/           used by tests and docs
├── tests/
│   ├── unit.tftest.hcl              plan-only assertions (labels, CMEK, deletion protection, PU multiple of 100)
│   ├── apply.tftest.hcl             real apply in the sandbox project (nightly, not on every PR)
│   └── corpus/                      sanitized state snapshots for the blast-radius gate (pulled from ssp-corpus bucket in CI)
└── .github/workflows/
    ├── ci.yml                       fmt, validate, tflint, trivy config, terraform test (unit), opa test, regal, catalogctl validate, blast-radius, policy-impact
    └── release.yml                  on tag v*: zip module → ssp-modules-<env>; publish bundle → ssp-catalog-<env>/<id>/<ver>/; update index.json; notify Pub/Sub
```

## Module contract

- SSP-MOD-001 Module variables are exactly the request schema properties (same names, compatible types) plus platform-provided: `project_id`, `labels` (map), `kms_key_name` (when `encryption` is declared), `name`. `catalogctl validate` enforces by inspecting the module.
- SSP-MOD-002 The module creates only resource types listed in `spec.resourceTypes`; policy rule SSP-POL-202 denies anything else at plan time.
- SSP-MOD-003 Outputs listed in `spec.terraform.outputs` are non-secret; any output marked `sensitive = true` is never listed and never captured.
- SSP-MOD-004 No provider blocks inside the module (the rendered root module supplies `google` with `impersonate_service_account`); `versions.tf` declares `required_providers` constraints only.
- SSP-MOD-005 Every resource sets `labels = var.labels` (merged with service labels); `deletion_protection` follows `var.deletion_protection`.
- SSP-MOD-006 Breaking changes (resource address changes) ship `moved` blocks; destroy/replace of existing resources requires a CHANGELOG `BREAKING` entry and makes the release T3.
- SSP-MOD-007 Semantic versioning; bundle version = git tag; `CHANGELOG.md` keeps a `## [x.y.z]` section per release with `Added/Changed/Guardrails/Breaking`.

## Spanner example (excerpts)

`variables.tf`
```hcl
variable "project_id" { type = string }
variable "name"       { type = string }
variable "labels"     { type = map(string) }
variable "kms_key_name" { type = string }
variable "config" {
  type = object({ mode = string, region = optional(string), multiRegionConfig = optional(string), processingUnits = number })
  validation { condition = var.config.processingUnits >= 100 && var.config.processingUnits % 100 == 0
               error_message = "processingUnits must be a multiple of 100 (REQ-E-SPAN-0001-06)." }
}
variable "databases" { type = list(object({ name = string, dialect = optional(string, "GOOGLE_STANDARD_SQL"), versionRetentionPeriod = optional(string, "7d") })) }
variable "deletionProtection" { type = bool, default = true }
```

`main.tf`
```hcl
locals { spanner_config = var.config.mode == "regional" ? "regional-${var.config.region}" : var.config.multiRegionConfig }

resource "google_spanner_instance" "this" {
  project          = var.project_id
  name             = var.name
  display_name     = var.name
  config           = local.spanner_config
  processing_units = var.config.processingUnits
  labels           = var.labels
  force_destroy    = false
  lifecycle { prevent_destroy = false }   # protection is enforced by deletion_protection on databases and by policy
}

resource "google_spanner_database" "db" {
  for_each                 = { for d in var.databases : d.name => d }
  project                  = var.project_id
  instance                 = google_spanner_instance.this.name
  name                     = each.key
  database_dialect         = each.value.dialect
  version_retention_period = each.value.versionRetentionPeriod
  deletion_protection      = var.deletionProtection
  encryption_config { kms_key_name = var.kms_key_name }     # REQ-E-SPAN-0001-02
}
```

`import/mapping.yaml`
```yaml
assets:
  - assetType: spanner.googleapis.com/Instance
    moduleAddress: "google_spanner_instance.this"
    id: "{{ .name }}"                                     # projects/<p>/instances/<i>
    params:
      name: "{{ .resource.data.displayName | default (last .name) }}"
      config.processingUnits: "{{ .resource.data.processingUnits }}"
      config.mode: "{{ if hasPrefix .resource.data.config \"regional-\" }}regional{{ else }}multi-region{{ end }}"
  - assetType: spanner.googleapis.com/Database
    moduleAddress: "google_spanner_database.db[\"{{ last .name }}\"]"
    id: "{{ .name }}"
    params:
      databases[].name: "{{ last .name }}"
```

`tests/unit.tftest.hcl`
```hcl
run "labels_and_cmek" {
  command = plan
  variables { project_id = "p", name = "claims-ledger", labels = { apm_id = "APM-1" }, kms_key_name = "projects/p/locations/us/keyRings/k/cryptoKeys/c",
              config = { mode = "regional", region = "us-central1", processingUnits = 100 }, databases = [{ name = "ledger" }] }
  assert { condition = google_spanner_database.db["ledger"].encryption_config[0].kms_key_name == var.kms_key_name
           error_message = "REQ-E-SPAN-0001-02: CMEK must be set" }
  assert { condition = google_spanner_instance.this.labels["apm_id"] == "APM-1"
           error_message = "REQ-E-SPAN-0001-05: labels must propagate" }
}
```

## Second service to add next: `ssp-module-gcs-bucket` (`gcp.gcs-bucket`)

Smallest possible slice for end-to-end testing: one resource type, guardrails CMEK + public access prevention + retention by data class, `holdsData: true`, soft delete. Use it to validate the reconciler, runner and UI renderer before Spanner's multi-step form.
