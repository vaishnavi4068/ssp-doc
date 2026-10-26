# ADR-EXP-003: Client SDK Experience (Python First, TypeScript Later)

- **ADR ID:** ADR-EXP-003
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-experience@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-ui`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the **Client SDK Experience (`spp-sdk` in Python `3.11+` now, with `@spp/sdk` in TypeScript `5.x` planned for Phase 5 alongside `ssp-ui`, `experiences/sdk/`)** over the `ssp-cp` FastAPI REST API—covering authentication and CSRF management, typed Pydantic v2 models for the `gcs_bucket` vertical slice, deterministic submit/status/wait helpers, structured error handling, and semantic versioning—so that automation scripts, the Jev model Agent Harness (`ADR-EXP-001`), and the MCP Server (`ADR-EXP-002`) share one tested client layer with zero privileged paths.

## Context

1. **Unified Client Layer Aligned with `ADR-GLB-002` and `ADR-BP-002`:**
   - Per `ADR-GLB-002`, SPP standardizes on **Python `3.11+` (`FastAPI`, `Pydantic v2`, `httpx`)** for `ssp-cp` and `ssp-workers`, and **TypeScript `5.x` (`React`, `Vite`)** for `ssp-ui` (scheduled for Phase 5 per `ADR-BP-002` and `WI-006`).
   - Delivering the **Python Client SDK (`spp-sdk`) first** immediately supports headless GCS bucket provisioning (`Phase 3` & `Phase 4`), CI/CD integration tests, the Jev model Agent Harness (`experiences/agentic-chat/`), and the MCP Server (`experiences/mcp/`), while noting the **TypeScript Client SDK (`@spp/sdk`)** for Phase 5 alongside `ssp-ui`.
2. **Client-Side Pre-Validation Paired with Authoritative Server Gate:**
   - Sharing Pydantic v2 validation logic between `ssp-cp` (`app/schemas.py`, `app/naming.py`) and `spp-sdk` catches malformed APM IDs, invalid regions, forbidden `environmentsubtype` labels, and secret keys (`INV-1`) immediately in the caller's process, while `ssp-cp` and OPA (`idp.gcp.gcs_bucket`) remain the authoritative server-side enforcement point.

## Decision

1. **Python SDK First (`spp-sdk`), TypeScript SDK Later (`@spp/sdk` in Phase 5):**
   - **MVP (`spp-sdk`, Python `3.11+`):** Built on `Pydantic v2` and `httpx`, providing both synchronous (`SppClient`) and asynchronous (`AsyncSppClient`) clients over `/api/v1/*`.
   - **Later (`@spp/sdk`, TypeScript `5.x` in Phase 5):** Generated from `ssp-cp`'s OpenAPI 3.1 specification using `openapi-typescript` when `ssp-ui` (`WI-006`) is built in Phase 5.
2. **Authentication & Session/CSRF Handling (`ADR-GLB-005`):**
   - `client.login(username, password)` calls `POST /api/v1/auth/login`, stores the `__Host-spp_cp_session` cookie, caches `UserProfileResponse.csrf_token`, and automatically attaches `X-CSRF-Token` on all `POST`, `PUT`, `PATCH`, and `DELETE` calls.
   - If `must_change_password == true`, raises `SppPasswordChangeRequiredError` until `client.change_password()` (`POST /api/v1/auth/change-password`) succeeds.
   - Supports pluggable `bearer_token` configuration for future corporate OIDC/SSO integration (`ADR-GLB-005 REQ-5`).
3. **Typed GCS Bucket Models & Pre-Validators (`ADR-SVC-001`, `ADR-GLB-006..008`):**
   - `GcsBucketRequest`, `RequestMetadata`, `GcsBucketSpec`, `AccessBinding`, and `LifecycleRule` enforce:
     - `apm_id` matching `(?i)^APM\d{5}$` and normalized to lowercase `^apm\d{5}$` (`NAM-APM-001`).
     - `environment` normalized to `nonprod` (no hyphen) or `prod` (`GLB-ENV-001`); `environmentsubtype` rejected (`LBL-001`).
     - `compute_canonical_labels(resource_id)` previewing all **8 mandatory labels** (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`) + metadata-derived labels.
     - `location == "us-east1"` (`GLB-REG-001`), `lifecycle_rules` defaulting to `[]` (`ADR-SVC-001 REQ-3`), IAM principal/role allowlists (`GCS-IAM-001..002`), rejection of guardrail-owned fields (`GCS-GRD-001`), and `DEFAULT_CMEK_KEY_URI = "projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek"` (`GCS-ENC-001`).
     - Pre-flight `scan_for_secrets()` (`INV-1`).
4. **Submit, Status, Approval, and Deterministic Wait Helpers:**
   - Maps to real `ssp-cp` endpoints (`POST /api/v1/requests`, `GET /api/v1/requests/{id}`, `GET /api/v1/approvals`, `POST /api/v1/approvals/{id}/decisions`, `GET /api/v1/resources/{id}`, `GET /api/v1/audit`, `POST /api/v1/state-units/{id}/freeze`) and proposed dry-run/plan endpoints (`POST /api/v1/agent/workflows/validate`, `GET /api/v1/requests/{id}/plan`).
   - Provides `wait_for_approval(request_id)` and `wait_for_observed(resource_id)` with configurable timeout and jittered backoff, returning Temporal `workflow_id` receipts (`req-<request_id>`, `apr-<request_id>`, `su-gcp-<project_id>`).

## Requirements

- **REQ-1 (MUST):** The Python Client SDK (`spp-sdk`) MUST use Python `3.11+`, `Pydantic v2`, and `httpx` (`ADR-GLB-002`) and communicate exclusively with the `ssp-cp` REST API (`/api/v1/*`) using the caller's authenticated credentials and `X-CSRF-Token`.
- **REQ-2 (MUST):** `GcsBucketRequest` in `spp-sdk` MUST validate and normalize `apm_id` (`(?i)^APM\d{5}$` -> `^apm\d{5}$`), `environment` (`-> nonprod | prod`), `location == "us-east1"`, the 8 mandatory labels (`LBL-001`, rejecting `environmentsubtype`), CMEK key preview (`projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`), and zero secret keys (`INV-1`) identically to `ssp-cp`.
- **REQ-3 (MUST):** Every mutating SDK call (`submit`, `decide`, `freeze`, `unfreeze`) MUST attach an `Idempotency-Key` (or `payload.idempotency_key`) and `X-CSRF-Token`, and set `source_ref = "sdk:python/<version>"`.
- **REQ-4 (MUST):** `client.approvals.decide()` MUST enforce client-side and server-side that `self_approval = "deny"` and that `status = "auto_approved"` is forbidden on any `delete` request in `nonprod` and `prod` (`ADR-BP-003`).
- **REQ-5 (SHOULD):** The TypeScript Client SDK (`@spp/sdk`) SHOULD be generated from `ssp-cp`'s OpenAPI 3.1 schema in Phase 5 (`ADR-BP-002`) so `ssp-ui` consumes the exact same API contract.

## Guardrails

- **GR-1:** Never allow `spp-sdk` to connect directly to AlloyDB (`spp_platform`), OPA (`:8181`), Temporal (`:7233`), or `gs://microdrive-dev-spp-tfstate`.
- **GR-2 (`INV-1`):** Never accept or serialize secret keys (`password`, `passwd`, `client_secret`, `private_key`, `secret_value`, `api_key`, `token`) inside `GcsBucketRequest` payloads.
- **GR-3:** Never bypass human approval (`gcs_bucket_owner` v1) or allow `auto_approved` on resource deletions in any environment.

## Consequences

### Positive

- Eliminates boilerplate HTTP/CSRF/retry code across CLI tools, CI tests, the Jev model Agent Harness (`ADR-EXP-001`), and the MCP Server (`ADR-EXP-002`).
- Catches schema, naming, label, and secret errors client-side in milliseconds before hitting `ssp-cp`.

### Negative / Trade-offs

- `spp-sdk` model versions must stay synchronized with `ssp-cp/app/schemas.py` and `ssp-cp/app/naming.py` via CI contract tests.

## Acceptance Criteria

- [ ] [`experiences/sdk/README.md`](../../experiences/sdk/README.md) documents purpose, user journeys, mermaid architecture, real vs. proposed `ssp-cp` endpoint mapping, typed GCS models, submit/status/wait helpers, error hierarchy, versioning, security/identity, approval/no-delete rules, observability, MVP vs. later scope (including TypeScript `@spp/sdk`), and open questions.
- [ ] `spp-sdk` models match `vaishnavi4068/ssp-cp` (`app/schemas.py` and `app/naming.py`) 100%.

## Success Criteria

- **SC-1:**
  - **Given** a Python caller constructing a `GcsBucketRequest` with `apm_id = "APM12345"`, `environment = "dev"`, and `owner = "bucket.owner@example.com"` and calling `client.requests.submit(req)`
  - **When** `spp-sdk` validates and sends `POST /api/v1/requests` to `ssp-cp`
  - **Then** `apm_id` is normalized to `"apm12345"`, `environment` is `"nonprod"`, all 8 mandatory labels are computed without `environmentsubtype`, `X-CSRF-Token` and `idempotency_key` are sent, and `RequestDetail` is returned with `request_id`, `approval_id`, and `temporal_workflow_id = "req-<request_id>"`.
- **SC-2:**
  - **Given** a `GcsBucketRequest` containing `environmentsubtype` in `labels`, `location = "US"`, a secret key `api_key`, or an approver attempting `status = "auto_approved"` on a `delete` request
  - **When** validated by `spp-sdk` (and `ssp-cp`)
  - **Then** `spp-sdk` raises a typed `ValidationError` / `SppPolicyViolationError` / `SppAuthorizationError` citing the violated rule ID (`LBL-001`, `GLB-REG-001`, `INV-001`, or `ADR-BP-003`).

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-EXP-003` and [`experiences/sdk/README.md`](../../experiences/sdk/README.md) |
| `ssp-cp` | Provides the upstream FastAPI REST endpoints and Pydantic/naming rules mirrored by `spp-sdk` |
| `ssp-ui` | Consumes the Phase 5 TypeScript SDK (`@spp/sdk`) generated from `ssp-cp` OpenAPI |
| `spp-factory-foundation` | Validates `ADR-EXP-003` via `lint_adrs.py` and SDK contract tests |

## Open Questions

- [ ] **OQ-1 (Python Package Repository Layout — [Owner: Manoj / Norm]):** Confirm whether `spp-sdk` is packaged inside `ssp-cp/sdk/python/` or in a dedicated repository `github.com/vaishnavi4068/ssp-sdk`.
- [ ] **OQ-2 (TypeScript `@spp/sdk` Phase 5 Delivery — [Owner: Dwayne / Manoj]):** Confirm generating `@spp/sdk` from `ssp-cp` OpenAPI in Phase 5 (`WI-006`) alongside `ssp-ui`.

## Related ADRs

- [ADR-EXP-001: Agentic Chatbot Experience for Self-Service Provisioning](ADR-EXP-001-agentic-chatbot-experience.md)
- [ADR-EXP-002: MCP Server Experience for Self-Service Provisioning](ADR-EXP-002-mcp-server-experience.md)
- [ADR-AUT-004: Agent Harness ("Jev Model") and Deterministic Temporal Workflow Execution Layer](../automation/ADR-AUT-004-agent-harness-and-temporal-workflow-execution.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-GLB-002: Languages and Technology Stack](../global/ADR-GLB-002-languages-and-technology-stack.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](../global/ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-008: Label and Tag Standard](../global/ADR-GLB-008-label-and-tag-standard.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
