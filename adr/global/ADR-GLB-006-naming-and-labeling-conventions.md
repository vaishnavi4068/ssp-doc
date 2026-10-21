# ADR-GLB-006: Naming and Labeling Conventions

- **ADR ID:** ADR-GLB-006
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-architecture@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define deterministic naming patterns and mandatory governance labels/tags across all cloud resources, Kubernetes execution Jobs, and Terraform state paths so that every resource provisioned by SPP is traceable to an application (`apm_id`), cost center, environment, owner, and data classification.

## Context

In the design discussion (`uploads/design-digest.md`) and the factory gate (`spp-factory-foundation/gates/policies/spp_gate.rego` and `gates/schemas/resource-request.schema.json`):

1. **Business Context via `apm_id`:** Manoj described SPP as a "business control plane for applications": given an `apm_id`, the platform resolves the application's tier (e.g., Tier 1 requires active-active databases), cost center, and security defaults.
2. **Mandatory Governance Labels:** Every resource in `Requested` and `Approved` state and every Terraform module must carry a standardized label/tag set (`apm_id`, `cost_center`, `environment`, `owner`, `data_classification`, plus `managed_by = "spp"`) to satisfy operations, CMDB registration, cost attribution, and Raju's security scanner.
3. **Deterministic Naming:** Both cloud resources and Kubernetes execution Jobs (`tf-op-<operation_id>` in `spp-platform`, `factory-wi-<work_item_id>-<station>[-attempt]` in `spp-factory`) require deterministic, collision-free naming. As noted in `uploads/design-digest.md` (§11) and `spp-factory-foundation/docs/context/factory-thinking.md` (§6.1), the enterprise 2.0 resource naming standard was referenced indirectly in the transcript, so the factory gate currently enforces a canonical placeholder pattern (`^(gcp|aws|azr)-[a-z0-9]+-(sandbox|dev|nonprod|prod)-[a-z0-9-]+$`) pending final enterprise naming sign-off.

## Decision

1. **Cloud Resource Naming Convention (2.0 Standard Placeholder):**
   - Pattern: `<cloud>-<lob>-<env>-<resource-slug>`
   - Enforced regex (aligned with `spp-factory-foundation/gates/policies/spp_gate.rego`):
     `^(gcp|aws|azr)-[a-z0-9]+-(sandbox|dev|nonprod|prod)-[a-z0-9-]+$` (length `3..63` characters, lowercase alphanumeric and hyphens).
   - Example: `gcp-retail-dev-orders-archive-01`.
2. **Mandatory Governance Labels / Tags (All Clouds):**
   Every `Requested` and `Approved` payload and every provisioned cloud resource MUST apply the following key-value labels/tags:

   | Label / Tag Key | Format / Allowed Values | Example | Purpose |
   | :--- | :--- | :--- | :--- |
   | `apm_id` | `^apm-[0-9]{4,8}$` (label) / `^APM-[0-9]{4,8}$` (top-level field) | `apm-1042` (`APM-1042`) | Links resource to enterprise application portfolio, tier, and CMDB CI |
   | `cost_center` | `^cc-[0-9]{3,8}$` | `cc-4410` | Financial chargeback and Day-2 cost attribution |
   | `environment` | `sandbox \| dev \| nonprod \| prod` | `dev` | Drives ServiceNow CR requirements (`prod`) and policy rules |
   | `owner` | Non-empty string (`>= 2` chars, lowercase/hyphen for GCP labels) | `platform-storage-team` | Accountable engineering/operations team |
   | `data_classification` | `public \| internal \| confidential \| restricted \| phi \| pii` | `confidential` | Drives CMEK, retention, and residency controls |
   | `managed_by` | `"spp"` (injected automatically in `Approved` / module) | `spp` | Identifies resource as managed by SPP 2.0 control plane |

3. **Platform & Execution Identifier Conventions:**
   - **Request ID:** `req-<alphanumeric-or-ulid>` (`^req-[a-z0-9-]+$`, e.g., `req-20261021-gcs-0001`).
   - **Operation ID:** `op-<alphanumeric-or-ulid>` (`^op-[a-z0-9-]+$`, e.g., `op-20261021-0001`).
   - **Terraform Runner Kubernetes Job Name (in `spp-platform`):** `tf-op-<operation_id>` (truncated/hashed deterministically if `> 63` chars to satisfy RFC 1123 DNS label limits).
   - **Factory Coding-Agent Kubernetes Job Name (in `spp-factory`):** `factory-wi-<work_item_id>-<station>-<attempt>`.
   - **GCS State Object Keys:** `expected/<project_id>/terraform.tfstate` and `observed/<project_id>/terraform.tfstate`.

## Requirements

- **REQ-1 (MUST):** Every `Requested` and `Approved` payload MUST include non-empty `labels.apm_id`, `labels.cost_center`, `labels.environment`, `labels.owner`, and `labels.data_classification` conforming to `gates/schemas/resource-request.schema.json`.
- **REQ-2 (MUST):** Every Terraform module in `ssp-module-<type>` MUST merge `managed_by = "spp"` into the effective resource labels/tags applied to the underlying cloud resource.
- **REQ-3 (MUST):** `resource_name` MUST match `^(gcp|aws|azr)-[a-z0-9]+-(sandbox|dev|nonprod|prod)-[a-z0-9-]+$` and be between 3 and 63 characters until superseded by a resource-specific enterprise naming ADR.
- **REQ-4 (MUST):** During `Requested -> Approved` enrichment, `ssp-cp` MUST normalize or auto-populate `labels.managed_by = "spp"` and verify that `labels.environment` matches the top-level `environment` attribute.
- **REQ-5 (SHOULD):** When a user provides `apm_id` in the UI or API, `ssp-cp` SHOULD automatically populate or validate `cost_center`, `application_tier`, and default `data_classification` from the application portfolio metadata so developers do not have to enter redundant fields manually.

## Guardrails

- **GR-1:** No resource may be provisioned in GCP, AWS, or Azure without the five required governance labels (`apm_id`, `cost_center`, `environment`, `owner`, `data_classification`).
- **GR-2:** Never embed sensitive data, PII, or secrets inside resource names or label values.
- **GR-3:** Never use random or non-deterministic suffixes for Kubernetes Job names (`tf-op-<operation_id>`); Job names must be a pure function of `operation_id` so Temporal retries reattach cleanly.

## Consequences

### Positive

- 100% compatibility with the existing JSON Schema (`gates/schemas/resource-request.schema.json`) and OPA policy gate (`gates/policies/spp_gate.rego`) in `spp-factory-foundation`.
- Every cloud resource can be queried by `apm_id`, `cost_center`, and `managed_by = "spp"` for billing, CMDB reconciliation, and Raju security audits.

### Negative / Trade-offs

- Global namespaces such as GCS bucket names (`google_storage_bucket.name`) and AWS S3 bucket names must be globally unique across the entire cloud provider; the `<resource-slug>` portion must include project/unique disambiguation where required by the CSP.

## Acceptance Criteria

- [ ] `ssp-cp` validates resource names and mandatory labels on all `Requested` and `Approved` payloads using the schema and Rego rules defined here.
- [ ] Every `ssp-module-<type>` module applies `apm_id`, `cost_center`, `environment`, `owner`, `data_classification`, and `managed_by = "spp"` to all taggable resources.
- [ ] Positive and negative OPA unit tests verify label presence, non-empty values, and `resource_name` regex compliance.

## Success Criteria

- **SC-1:**
  - **Given** a `Requested` payload missing `labels.cost_center` or using `resource_name = "my_bucket"`
  - **When** evaluated by `ssp-cp` or the factory CI gate (`validate_schema.py` and `conftest`)
  - **Then** validation fails with an explicit error citing `ADR-GLB-006`.
- **SC-2:**
  - **Given** a compliant `Approved` payload for `resource_name = "gcp-retail-dev-orders-archive-01"` with all 5 required labels
  - **When** the Terraform module renders the resource plan
  - **Then** the planned resource carries all 5 labels plus `managed_by = "spp"`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the global naming and labeling contract |
| `ssp-cp` | Enforces naming/label validation and auto-enriches `managed_by = "spp"` and APM metadata |
| `ssp-workers` | Uses deterministic `tf-op-<operation_id>` Job naming and `expected/<project_id>/terraform.tfstate` keys |
| `ssp-ui` | Auto-fills `apm_id`-derived labels and previews the generated resource name |
| `ssp-module-<type>` | Applies `local.effective_labels` to all provisioned cloud resources |
| `spp-factory-foundation` | Enforces label and naming rules in `gates/schemas/resource-request.schema.json` and `gates/policies/spp_gate.rego` |

## Open Questions

- [ ] **OQ-1 (Enterprise 2.0 Naming Standard):** What is the final enterprise naming convention per resource type (e.g., character limits for Windows VMs, storage accounts in Azure that disallow hyphens, or globally unique GCS/S3 buckets) to replace or refine the placeholder regex `^(gcp|aws|azr)-<lob>-<env>-<name>$`?
- [ ] **OQ-2 (Authoritative APM ID Lookup Source):** Which internal API or database table maps `APM-XXXX` (`apm_id`) to `application_tier`, `cost_center`, and `owner` during `Requested -> Approved` enrichment?

## Related ADRs

- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](ADR-GLB-003-four-state-model.md)
- [ADR-GLB-007: Governance Gates and Policy (Rego)](ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-AUT-001: Terraform Execution via Kubernetes Jobs](../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-BP-001: Ownership Map and Stakeholder Governance](../business-process/ADR-BP-001-ownership-map-and-governance.md)
