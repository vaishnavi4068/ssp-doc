# ADR-GLB-007: Governance Gates and Policy (Rego)

- **ADR ID:** ADR-GLB-007
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-policy@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security], Allen / Karen [Operations])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Establish a clean-slate Open Policy Agent (`OPA` / `Rego`) governance framework and deterministic verification gate architecture—with zero policy reuse from legacy "taxi"—that enforces security defaults (CMEK, `>= 90`-day retention, Raju baseline, no secrets), approved GCP regions (`us-east1`), naming/labeling rules, the non-bypassable Operations Gate, and the hard guardrail prohibiting any resource deletion/replacement without explicit human-in-the-loop approval both in CI (`spp-factory-foundation/gates/`) and at runtime (`ssp-cp` and `ssp-workers`).

## Context

From the design discussion (`uploads/design-digest.md`) and `spp-factory-foundation`:

1. **Clean-Slate OPA Rules:** The team explicitly decided: "We definitely would do our own OPA rules" evaluated against SPP's own JSON Schema, reusing nothing from legacy "taxi".
2. **Preventing Raju Auto-Deletions via `Approved` State Enrichment:** Today, Raju's security compliance system deletes non-compliant cloud resources without warning. SPP prevents this by injecting Raju's security baseline—including Customer-Managed Encryption Keys (`CMEK`), `>= 90`-day retention (`retention_days >= 90`), and `public_access_prevention = "enforced"`—into the `Approved` state and verifying compliance with OPA before Terraform executes.
3. **Operations Cannot Be Bypassed & Human-in-the-Loop Deletion Gate:** Allen set the non-negotiable organizational rule (championed by Norm and Karen) that **operations cannot be bypassed**. Every `Approved` payload must satisfy the Operations Gate (`operations_gate.approved == true`, `operations_gate.bypass_allowed == false`). Furthermore, **no deletion or destructive replacement of any resource is permitted without explicit human-in-the-loop approval**: Rego policies must deny any request or Terraform plan (`resource_changes[*].change.actions`) containing a `delete` or `replace` (`["delete", "create"]` / `["create", "delete"]`) action unless an explicit human approval record is present (`ADR-AUT-002`). *(Note: ServiceNow and CMDB fields are retained as non-blocking schema placeholders for future post-MVP integration and are out of scope as active gates in the `microdrive-dev` MVP, per `ADR-BP-001`.)*
4. **7-Stage Automated Factory Gate with Bounded Rework:** In `spp-factory-foundation`, every ADR, schema, policy, and module PR must pass the 7-stage verification gate (`gates/scripts/run_gate.sh`). If a gate check fails during a factory run, the agent may retry at most **3 times** before the work item transitions to **`BLOCKED`** for human escalation.

## Decision

1. **Dual-Point Policy Enforcement (CI Gate + Runtime Control Plane & Runner Plan Gate):**
   - **Build-Time (Factory CI Gate in `spp-factory-foundation/gates/`):** Every PR across `ssp-doc`, `ssp-cp`, and `ssp-module-<type>` runs:
     1. YAML workflow lint (`yamllint` / PyYAML)
     2. ADR structural & ownership lint (`lint_adrs.py`)
     3. Canonical JSON Schema validation (`validate_schema.py` against `gates/schemas/resource-request.schema.json`)
     4. OPA Rego unit tests (`opa test gates/policies/ <repo>/policies/ -v`)
     5. Conftest policy evaluation against `examples/requested.json` and `examples/approved.json`
     6. Terraform format, offline validation, and `mock_provider` plan tests (`terraform fmt -check`, `terraform validate`, `terraform test`)
     7. Static security scan (`tfsec`)
   - **Runtime (`ssp-cp` Approval Gate + `ssp-workers` Pre-Apply Plan Gate):**
     1. Before `ssp-cp` persists an `Approved` spec or starts a Temporal workflow in `platform`, it enriches the request with security/operational defaults and evaluates the canonical JSON Schema + OPA policy bundle.
     2. Inside the `tf-op-<operation_id>` runner Job (`ssp-workers`), `terraform plan -out=tfplan && terraform show -json tfplan > tfplan.json` is evaluated by OPA/Rego before `terraform apply` runs. Any `deny` blocks execution immediately.
2. **Mandatory Global Rego Policy Rules (`gates/policies/spp_gate.rego`):**
   - **State, Cloud & 2.0 Scope:** `state` in `{"requested", "approved"}`; `cloud == "gcp"`; `layout_version == "2.0"`; `resource_type != "google_bigquery_table"` (BigQuery datasets only).
   - **Zero Secrets:** Reject any key matching `password`, `passwd`, `secret`, `private_key`, `api_key`, `apikey`, `access_token`, `auth_token`, `bearer_token`, `client_secret`, `connection_string`, `credentials`, or values matching private key / token / credential regexes.
   - **Required Labels:** `apm_id`, `cost_center`, `environment`, `owner`, `data_classification` present and non-empty.
   - **Naming Convention:** `resource_name` matches `^gcp-[a-z0-9]+-(sandbox|dev|nonprod|prod)-[a-z0-9-]+$`.
   - **Approved GCP Regions:** `approved_regions.gcp = {"us-east1"}` (`us-east1` only for now).
   - **`Approved`-State Security Baseline:** `security.cmek_enabled == true`, non-empty `security.cmek_key_id` (using `projects/microdrive-dev/locations/us-east1/keyRings/<TODO>/cryptoKeys/<TODO>` in `microdrive-dev`, owner: `vaishnavi4068`, per `ADR-SVC-001`), `security.retention_days >= 90`, `security.public_access_prevention == "enforced"`, `security.raju_baseline_applied == true`.
   - **`Approved`-State Storage & Identity:** `state_backend.expected_key == "expected/<project_id>/terraform.tfstate"`, `state_backend.observed_key == "observed/<project_id>/terraform.tfstate"`, and `service_account_email` contains `project_id`.
   - **`Approved`-State Operations Gate:** `operations_gate.approved == true` and `operations_gate.bypass_allowed == false` (with `servicenow` and `cmdb` blocks carried only as static schema placeholders in the MVP; live ServiceNow/CMDB gating is deferred post-MVP per `ADR-BP-001`).
   - **No Delete or Replace Without Explicit Human-in-the-Loop Approval (`ADR-AUT-002`):** Rego MUST deny any `decommission` request or any Terraform plan (`input.resource_changes[_].change.actions[_] == "delete"`) unless an explicit human approval record (`input.human_approval.approved == true`, non-empty `input.human_approval.approver`, `input.human_approval.approval_id`, and `input.human_approval.reason`) is present.

## Requirements

- **REQ-1 (MUST):** All Rego policies MUST be written from scratch for SPP (`import rego.v1`) and validated against `gates/schemas/resource-request.schema.json`.
- **REQ-2 (MUST):** Every Rego policy rule in `gates/policies/` and in per-resource `ssp-module-<type>/policies/` MUST have unit tests (`*_test.rego`) covering both passing (`0` denials) and failing (`deny`) scenarios.
- **REQ-3 (MUST):** Per-resource repositories (`ssp-module-<type>`) MAY add stricter service-specific Rego rules in their local `policies/` directory, but MUST NOT weaken, override, or disable global rules in `gates/policies/spp_gate.rego`.
- **REQ-4 (MUST):** `ssp-cp` MUST evaluate the global and service-specific Rego policies on every `Approved` payload before dispatching a Temporal provisioning or Day-2 workflow.
- **REQ-5 (MUST):** Neither human engineers nor factory agents may bypass the Operations Gate (`operations_gate.approved == true`, `operations_gate.bypass_allowed == false`).
- **REQ-6 (MUST):** Rego policies MUST evaluate Terraform plan JSON (`resource_changes[*].change.actions`) and `decommission` payloads, and MUST deny any plan or operation containing a `delete` or `replace` action unless an explicit human-in-the-loop approval record (`human_approval.approved == true`, `approver`, `approval_id`, `reason`) is attached.
- **REQ-7 (MUST):** Factory coding-agent runs that fail any stage of `gates/scripts/run_gate.sh` MUST halt and transition to `BLOCKED` after at most **3 rework attempts**.

## Guardrails

- **GR-1:** Never import or reuse legacy "taxi" OPA policies or schemas.
- **GR-2:** Never allow a resource to reach `Approved` state with `retention_days < 90`, `cmek_enabled != true`, `public_access_prevention != "enforced"`, or `raju_baseline_applied != true`.
- **GR-3:** Never allow a request to proceed with `operations_gate.approved != true` or `operations_gate.bypass_allowed != false`.
- **GR-4 (No Deletion Without Explicit Human-in-the-Loop Approval):** Never allow any resource deletion or destructive replacement (`delete` or `replace` action in a Terraform plan or `decommission` operation) without an explicit human-in-the-loop approval record verified by Rego.
- **GR-5:** Never skip or weaken a gate check in CI to force a PR to pass.

## Consequences

### Positive

- Identical policy logic governs offline CI checks in `spp-factory-foundation` and live API request approval in `ssp-cp`.
- Eliminates compliance drift, prevents Raju's scanner from deleting SPP-provisioned resources, and guarantees via Rego that no resource can be deleted or force-replaced without an explicit human approval record.
- Codifies operations requirements upfront in Rego so standard 2.0 requests auto-verify without manual ticket bottlenecks.

### Negative / Trade-offs

- Any new resource attribute added to `Requested` or `Approved` payloads requires updating `gates/schemas/resource-request.schema.json` (which sets `additionalProperties: false` at the top level) and passing all Rego unit tests.

## Acceptance Criteria

- [ ] `opa test` passes 100% on global and per-service Rego suites, including positive and negative tests for the `delete`/`replace` human-approval rule.
- [ ] `ssp-cp` integrates schema validation and Rego policy evaluation into the `Requested -> Approved` transition pipeline, and `ssp-workers` evaluates the Terraform plan JSON against Rego before `terraform apply`.
- [ ] Negative test cases prove that payloads with secrets, missing CMEK, `< 90`-day retention, unapproved regions (`!= "us-east1"`), `operations_gate.bypass_allowed == true`, or `delete`/`replace` plan actions without `human_approval.approved == true` are rejected.

## Success Criteria

- **SC-1:**
  - **Given** an `Approved` payload with `retention_days = 30` or missing `security.cmek_key_id`
  - **When** `ssp-cp` or `conftest` evaluates `spp_gate.rego`
  - **Then** policy evaluation fails and returns the explicit `ADR-GLB-004` / `ADR-GLB-007` denial message.
- **SC-2:**
  - **Given** a Terraform plan containing a `delete` or `replace` action without `human_approval.approved == true`, or a provisioning request with `operations_gate.approved = false`
  - **When** evaluated by the Rego policy gate
  - **Then** the gate denies the operation and no destructive `terraform apply` or `terraform destroy` is executed.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the global Rego policy, verification gate architecture, and human-approval deletion guardrail |
| `ssp-cp` | Evaluates JSON Schema and Rego policies during `Requested -> Approved` enrichment and records `human_approval` |
| `ssp-workers` | Evaluates `terraform show -json tfplan` against Rego prior to `terraform apply` in `tf-op-<operation_id>` Jobs |
| `ssp-module-<type>` | Supplies service-specific `policies/<service>.rego` and `policies/<service>_test.rego` |
| `spp-factory-foundation` | Hosts the master `gates/policies/spp_gate.rego`, `resource-request.schema.json`, and `run_gate.sh` |

## Open Questions

- [x] **OQ-1 (Approved GCP Regions — RESOLVED 2026-10-21):** *Resolved:* `approved_regions.gcp` is **`{"us-east1"}` only** for now (replacing `us-east4` and `us-central1`).
- [ ] **OQ-2 (Complete Raju Security Rule Catalog):** Has Raju's team provided the exhaustive list of resource-specific compliance rules beyond CMEK, `>= 90`-day retention, uniform bucket-level access, and public access prevention?
- [x] **OQ-3 (Cost Gate Thresholds — RESOLVED 2026-10-21):** *Resolved:* Active cost calculation and budget threshold gates are **out of scope for the MVP**; the MVP enforces the mandatory `cost_center` label only (`ADR-AUT-002 OQ-5`).

## Related ADRs

- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](ADR-GLB-003-four-state-model.md)
- [ADR-GLB-005: Identity and Authentication](ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-006: Naming and Labeling Conventions](ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-BP-001: Ownership Map and Stakeholder Governance](../business-process/ADR-BP-001-ownership-map-and-governance.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket End-to-End (No UI)](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-AUT-002: Day-2 Operations Scope](../automation/ADR-AUT-002-day-2-operations-scope.md)
