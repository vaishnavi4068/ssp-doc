# ADR-EXP-002: MCP Server Experience for Self-Service Provisioning

- **ADR ID:** ADR-EXP-002
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-experience@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the **Model Context Protocol (MCP) Server Experience (`spp-mcp`, `experiences/mcp/`)** exposing SPP tools (`spp_list_catalog`, `spp_describe_gcs_bucket_schema`, `spp_validate_request`, `spp_submit_request`, `spp_get_request_status`, `spp_get_request_plan`, `spp_list_approvals`) backed exclusively by the `ssp-cp` FastAPI API and mapped **1:1** to the deterministic Temporal workflows in `ADR-AUT-004` (`platform` namespace), with explicit caller authentication, scope enforcement, read vs. write tool separation, and strictly human approvals.

## Context

1. **Developer IDE & CLI AI Assistant Integration:**
   - Engineers increasingly interact with internal platforms from MCP-capable hosts (Cursor, Claude Code, Gemini CLI). Providing an official SPP MCP server (`experiences/mcp/`) allows developers to discover the `gcs_bucket` schema, validate requests against OPA (`idp.gcp.gcs_bucket`), submit requests, and inspect 4-gate status and Terraform plans directly from their IDE.
2. **1:1 Alignment with the Jev Model Agent Harness (`ADR-AUT-004`) and `ssp-cp`:**
   - To guarantee that no channel has a privileged path and that AI clients never perform direct side effects, every MCP tool in `spp-mcp` maps **1:1** to the same deterministic Temporal workflows on namespace `platform` (`spp-agent-actions` and `spp-gcs-provisioning`) and calls the same `ssp-cp` REST endpoints via the `spp-sdk` Python client (`ADR-EXP-003`).
3. **Human-Only Approvals (`ADR-BP-003`):**
   - AI coding assistants must never be able to autonomously approve infrastructure requests or bypass deletion controls. Approvals remain strictly human (`bucket_owner` / `approver` role, `self_approval = "deny"`, no `AUTO_APPROVED` deletes in `nonprod` or `prod`).

## Decision

1. **MCP Tool Catalog & Read vs. Write Separation (1:1 Workflow Mapping):**

   | MCP Tool Name | Mode | Required Scope | `ssp-cp` Endpoint (`REAL` vs. `PROPOSED`) | 1:1 Temporal Workflow (`namespace = "platform"`) |
   | :--- | :--- | :--- | :--- | :--- |
   | **`spp_list_catalog`** | `read` (`readOnlyHint: true`) | `spp:catalog:read` | **REAL:** `GET /api/v1/kinds` (`app/main.py:434`) | `AgentListCatalogWorkflow` (`wf-cat-*`) |
   | **`spp_describe_gcs_bucket_schema`** | `read` (`readOnlyHint: true`) | `spp:catalog:read` | **REAL:** `GET /api/v1/kinds` + **PROPOSED:** `GET /api/v1/kinds/gcs_bucket/schema` | `AgentDescribeSchemaWorkflow` (`wf-sch-gcs_bucket-1.0.0`) |
   | **`spp_validate_request`** | `read` / dry-run (`readOnlyHint: true`) | `spp:requests:read` | **PROPOSED:** `POST /api/v1/agent/workflows/validate` | `AgentValidateRequestWorkflow` (`wf-val-<20hex>`) |
   | **`spp_submit_request`** | `write` (`readOnlyHint: false`, `idempotentHint: true`) | `spp:requests:write` | **REAL:** `POST /api/v1/requests` (`app/main.py:466`) | `AgentSubmitRequestWorkflow` (`wf-sub-<20hex>`) -> `req-<request_id>` & `apr-<request_id>` |
   | **`spp_get_request_status`** | `read` (`readOnlyHint: true`) | `spp:requests:read` | **REAL:** `GET /api/v1/requests/{request_id}` & `GET /api/v1/resources/{resource_id}` | `AgentGetStatusWorkflow` / Query on `req-<request_id>` & `su-gcp-<project_id>` |
   | **`spp_get_request_plan`** | `read` (`readOnlyHint: true`) | `spp:requests:read` | **REAL:** `GET /api/v1/requests/{request_id}` + **PROPOSED:** `GET /api/v1/requests/{request_id}/plan` | `AgentGetPlanWorkflow` (`wf-pln-<request_id>-<rev>`) |
   | **`spp_list_approvals`** | `read` (`readOnlyHint: true`) | `spp:approvals:read` | **REAL:** `GET /api/v1/approvals` & `GET /api/v1/approvals/{approval_id}` | `AgentListApprovalsWorkflow` / Query on `apr-<request_id>` |

2. **Authentication, Identity Propagation, and Scopes (`ADR-GLB-005`):**
   - `spp-mcp` authenticates as the human developer via `POST /api/v1/auth/login` (`__Host-spp_cp_session` cookie + `X-CSRF-Token` in memory; future OIDC Bearer JWT) and verifies `must_change_password == false` via `GET /api/v1/me`.
   - Sets `channel = "api"` (or `"chat"`), `source_ref = "mcp:<tool_name>"`, and forwards `Idempotency-Key` on every write call.
3. **Human Approval & No-Delete Enforcement (`ADR-BP-003`, `ADR-GLB-007`):**
   - `spp-mcp` exposes approval inspection (`spp_list_approvals`) as read-only by default; human approvals are executed by the human `bucket_owner` / `approver` (`self_approval = "deny"`).
   - For `action = "delete"`, `spp_submit_request` sets `destructiveHint = true`, requires `base_approval_id`, and `ssp-cp` forbids `AUTO_APPROVED` / `auto_approved` in both `nonprod` and `prod`.

## Requirements

- **REQ-1 (MUST):** `spp-mcp` MUST call `ssp-cp` exclusively via the REST API (using `spp-sdk`) with the caller's authenticated identity and MUST NOT connect directly to AlloyDB, OPA, Temporal, Kubernetes, or `gs://microdrive-dev-spp-tfstate`.
- **REQ-2 (MUST):** Every tool exposed by `spp-mcp` MUST map 1:1 to the deterministic Temporal workflows defined in `ADR-AUT-004` on Temporal namespace `platform` and return the `workflow_id` in its structured output.
- **REQ-3 (MUST):** `spp-mcp` MUST enforce strict separation between read-only tools (`spp:catalog:read`, `spp:requests:read`, `spp:approvals:read` with `readOnlyHint = true`) and write tools (`spp:requests:write` with `readOnlyHint = false`), requiring a valid `preview_sha256` from `spp_validate_request` and an `idempotency_key` before `spp_submit_request` executes.
- **REQ-4 (MUST):** `spp_describe_gcs_bucket_schema` and `spp_validate_request` MUST enforce and surface the 8 mandatory labels (`LBL-001`, no `environmentsubtype`), APM ID normalization (`(?i)^APM\d{5}$` -> `^apm\d{5}$`), `location = "us-east1"`, and CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek` (`GCS-ENC-001`).
- **REQ-5 (MUST):** Approvals MUST remain strictly human (`gcs_bucket_owner` v1, `self_approval = "deny"`, no `AUTO_APPROVED` deletes in `nonprod` or `prod`); `spp-mcp` MUST NOT expose an un-gated autonomous approval tool.

## Guardrails

- **GR-1:** Never allow an MCP tool to approve a request (`POST /api/v1/approvals/{approval_id}/decisions`) autonomously on behalf of an AI agent.
- **GR-2:** Never allow `spp_submit_request` to bypass `spp_validate_request` (`preview_sha256`) or omit `idempotency_key`.
- **GR-3 (`INV-1`):** Never store or transmit plaintext passwords, session secrets, or GCP service account JSON keys in MCP configuration files (`.mcp.json`) or tool outputs.

## Consequences

### Positive

- Developers in Cursor, Claude Code, and Gemini CLI gain first-class, schema-validated access to SPP GCS bucket provisioning with zero duplicated policy logic.
- Read/write tool annotations and human-only approvals prevent autonomous agent misfires.

### Negative / Trade-offs

- Requires the proposed dry-run validation (`POST /api/v1/agent/workflows/validate`) and plan summary (`GET /api/v1/requests/{request_id}/plan`) endpoints in `ssp-cp` for complete pre-submit and post-approval visibility.

## Acceptance Criteria

- [ ] [`experiences/mcp/README.md`](../../experiences/mcp/README.md) documents purpose, user journeys, mermaid architecture, real vs. proposed `ssp-cp` endpoint mapping, 1:1 Temporal workflow mapping, scopes, read vs. write tool schemas, approval/no-delete rules, observability, MVP vs. later scope, and open questions.
- [ ] All 7 MCP tools map 1:1 to the workflows in `ADR-AUT-004` and enforce `ADR-SVC-001` GCS bucket guardrails.

## Success Criteria

- **SC-1:**
  - **Given** an MCP client invoking `spp_validate_request` followed by `spp_submit_request` for a `gcs_bucket` in `us-east1` with `apm_id = "APM12345"`
  - **When** processed by `spp-mcp` and `ssp-cp`
  - **Then** `spp_validate_request` returns `workflow_id = "wf-val-*"`, `preview_sha256`, the 8 mandatory labels (`sppappid = "apm12345"`), and the CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`, and `spp_submit_request` creates the `PENDING_APPROVAL` request in `ssp-cp` with `source_ref = "mcp:spp_submit_request"`.
- **SC-2:**
  - **Given** an MCP session attempting to invoke `spp_submit_request` without `spp:requests:write` scope or without a matching `preview_sha256`, or attempting to approve a request via MCP
  - **When** evaluated by `spp-mcp` and `ssp-cp`
  - **Then** the call is rejected before any state change occurs.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-EXP-002` and [`experiences/mcp/README.md`](../../experiences/mcp/README.md) |
| `ssp-cp` | Serves `/api/v1/kinds`, `/api/v1/requests`, `/api/v1/approvals`, `/api/v1/resources`, `/api/v1/audit`, and proposed validate/plan routes |
| `ssp-workers` | Executes the 1:1 mapped Temporal workflows on namespace `platform` |
| `spp-factory-foundation` | Validates `ADR-EXP-002` via `lint_adrs.py` and MCP contract tests |

## Open Questions

- [ ] **OQ-1 (Local `stdio` vs. Remote Streamable HTTP Deployment in `spp-platform` — [Owner: Manoj / Dwayne]):** Confirm whether MVP ships `spp-mcp` strictly as a local `stdio` server packaged with `spp-sdk` or also deploys an internal Streamable HTTP service in GKE namespace `spp-platform`.
- [ ] **OQ-2 (Schema Endpoint `GET /api/v1/kinds/{kind}/schema` in `ssp-cp` — [Owner: Manoj]):** Confirm adding `GET /api/v1/kinds/{kind}/schema` to `ssp-cp` so `spp_describe_gcs_bucket_schema` can fetch the JSON Schema dynamically alongside `GET /api/v1/kinds`.

## Related ADRs

- [ADR-AUT-004: Agent Harness ("Jev Model") and Deterministic Temporal Workflow Execution Layer](../automation/ADR-AUT-004-agent-harness-and-temporal-workflow-execution.md)
- [ADR-EXP-001: Agentic Chatbot Experience for Self-Service Provisioning](ADR-EXP-001-agentic-chatbot-experience.md)
- [ADR-EXP-003: Client SDK Experience (Python First, TypeScript Later)](ADR-EXP-003-client-sdk-experience.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-008: Label and Tag Standard](../global/ADR-GLB-008-label-and-tag-standard.md)
- [ADR-GLB-009: Resource Kind Registry](../global/ADR-GLB-009-resource-kind-registry.md)
