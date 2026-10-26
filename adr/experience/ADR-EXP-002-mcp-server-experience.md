# ADR-EXP-002: MCP Server Experience for Self-Service Provisioning (Pinned to MCP Specification `2026-07-28`)

- **ADR ID:** ADR-EXP-002
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-experience@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the **Model Context Protocol (MCP) Server Experience (`spp-mcp`, `experiences/mcp/`)** pinned to the latest **MCP specification revision `2026-07-28`** (implemented with official Python SDK **`mcp >= 2.3.0`**), exposing SPP's 7 tools (`spp_list_catalog`, `spp_describe_gcs_bucket_schema`, `spp_validate_request`, `spp_submit_request`, `spp_get_request_status`, `spp_get_request_plan`, `spp_list_approvals`) over **stateless Streamable HTTP (`POST /mcp`)**, **OAuth 2.1 Resource Server authorization** (`RFC 9728` Protected Resource Metadata, `RFC 8707` audience-bound tokens, `spp:*` scopes), **structured tool output (`outputSchema` + `structuredContent`)**, **tool annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`)**, **Multi Round-Trip Request (MRTR) Elicitation (`elicitation/create`)** for human confirmations, and the **`io.modelcontextprotocol/tasks` extension** mapped **1:1** to SPP's deterministic Temporal workflows (`ADR-AUT-004`, namespace `platform`), while keeping all resource approvals strictly human.

## Context

1. **Pinning the Exact Current MCP Specification Revision (`2026-07-28`):**
   - Per [`https://modelcontextprotocol.io/specification/versioning`](https://modelcontextprotocol.io/specification/versioning) and [`https://modelcontextprotocol.io/specification/2026-07-28/changelog`](https://modelcontextprotocol.io/specification/2026-07-28/changelog), the current MCP specification revision is **`2026-07-28`** (superseding `2025-11-25`).
   - Official SDK support for revision `2026-07-28` is provided by **`modelcontextprotocol/python-sdk` `v2.x` (`mcp == 2.3.0`, requiring `httpx2 >= 2.10.0`)** and **`modelcontextprotocol/typescript-sdk` `v2.x` (`@modelcontextprotocol/sdk == 2.3.1`)**.
2. **Key Architectural Improvements in MCP `2026-07-28` Exploited by `spp-mcp`:**
   - **Stateless Streamable HTTP (`SEP-2567`, `SEP-2575`, `SEP-2243`):** Removes protocol-level sessions (`Mcp-Session-Id`), removes the `initialize` handshake, adds mandatory `server/discover`, and requires `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method`, `Mcp-Name`, and validated `Mcp-Param-*` headers (`x-mcp-header`, rejecting mismatches with `-32020 HeaderMismatch`). This allows `spp-mcp` pods in GKE namespace `spp-platform` to scale horizontally behind standard load balancers with zero sticky sessions.
   - **OAuth 2.1 Resource Server (`RFC 9728`, `RFC 8707`, `RFC 9207`, `SEP-2468`, `SEP-2352`):** Standardizes `GET /.well-known/oauth-protected-resource`, `WWW-Authenticate` scope challenges (`spp:catalog:read`, `spp:requests:read`, `spp:requests:write`, `spp:approvals:read`), Client ID Metadata Documents (deprecating `RFC 7591` Dynamic Client Registration), and `RFC 8707` `resource`-bound audience validation.
   - **Multi Round-Trip Requests (MRTR) & Elicitation (`SEP-2322`):** Replaces stateful server-initiated requests on SSE streams with stateless `InputRequiredResult` (`resultType: "input_required"`, `inputRequests` containing `elicitation/create` in `form` or `url` mode, and AEAD-protected `requestState`), providing a cryptographic human-in-the-loop confirmation gate before `spp_submit_request` executes.
   - **Official Tasks Extension (`io.modelcontextprotocol/tasks`, `SEP-2663`):** Standardizes durable async handles (`resultType: "task"`, `taskId`, `tasks/get`, `tasks/update`, `tasks/cancel`, and `notifications/tasks` over `subscriptions/listen`), which map 1:1 to SPP's Temporal `workflow_id`s (`req-<request_id>`, `apr-<request_id>`, `su-gcp-<project_id>`), Temporal queries, and Temporal signals on namespace `platform`.

## Decision

### 1. Protocol Revision, Transport, and Official SDK Pin

- **MCP Protocol Version:** `2026-07-28` (`MCP-Protocol-Version: 2026-07-28` and `_meta["io.modelcontextprotocol/protocolVersion"] = "2026-07-28"`).
- **Official SDK:** Python `mcp >= 2.3.0` (`modelcontextprotocol/python-sdk`, `httpx2 >= 2.10.0`) in `spp-mcp`; TypeScript `@modelcontextprotocol/sdk >= 2.3.1` for Phase 5 client/host integrations.
- **Primary Transport:** Stateless **Streamable HTTP** at `POST /mcp` (`Origin` header validated; `GET` and `DELETE` on `/mcp` return `405 Method Not Allowed`; `X-Accel-Buffering: no` set on SSE streams; `server/discover` and `subscriptions/listen` supported). Local `stdio` transport is also supported for developer workstation CLI use.

### 2. OAuth 2.1 Resource Server & `spp:*` Scope Mapping

- `spp-mcp` acts as an OAuth 2.1 Resource Server serving `GET /.well-known/oauth-protected-resource` (`RFC 9728`) advertising `resource: "https://mcp.spp.internal/mcp"` and `scopes_supported: ["spp:catalog:read", "spp:requests:read", "spp:requests:write", "spp:approvals:read"]`.
- Every `Authorization: Bearer <token>` on `POST /mcp` is validated for issuer, expiry, `RFC 8707` audience (`aud == "https://mcp.spp.internal/mcp"`), and tool scope. Missing/invalid tokens return `401 Unauthorized` with `WWW-Authenticate: Bearer resource_metadata="...", scope="..."`.
- Client ID Metadata Documents (`draft-ietf-oauth-client-id-metadata-document-00`) and `RFC 9207` `iss` response validation (`SEP-2468`) are enforced on OAuth flows.

### 3. Seven-Tool Catalog, `ToolAnnotations`, `outputSchema`, and 1:1 Temporal Workflow Mapping

All 7 tools are returned by `tools/list` in deterministic alphabetical order (`ttlMs: 300000`, `cacheScope: "private"`), declare JSON Schema 2020-12 `inputSchema` and `outputSchema` (returning both `structuredContent` and a serialized JSON `TextContent` block with `resultType: "complete"`), and map **1:1** to the deterministic Temporal workflows in `ADR-AUT-004` (`namespace = "platform"`):

| # | MCP Tool Name | Scope | `ToolAnnotations` (`readOnlyHint` / `destructiveHint` / `idempotentHint` / `openWorldHint`) | `x-mcp-header` (`Mcp-Param-*`) | `ssp-cp` Endpoint (`REAL` vs. `PROPOSED`) | 1:1 Temporal Workflow (`namespace = "platform"`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **`spp_describe_gcs_bucket_schema`** | `spp:catalog:read` | `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`, `openWorldHint: false` | — | **REAL:** `GET /api/v1/kinds` + **PROPOSED:** `GET /api/v1/kinds/gcs_bucket/schema` | `AgentDescribeSchemaWorkflow` (`wf-sch-gcs_bucket-1.0.0` on `spp-agent-actions`) |
| **2** | **`spp_get_request_plan`** | `spp:requests:read` | `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`, `openWorldHint: false` | `Request-Id` | **REAL:** `GET /api/v1/requests/{request_id}` + **PROPOSED:** `GET /api/v1/requests/{request_id}/plan` | `AgentGetPlanWorkflow` (`wf-pln-<request_id>-<rev>` on `spp-agent-actions`) |
| **3** | **`spp_get_request_status`** | `spp:requests:read` | `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`, `openWorldHint: false` | `Request-Id` | **REAL:** `GET /api/v1/requests/{request_id}` & `GET /api/v1/resources/{resource_id}` | `AgentGetStatusWorkflow` / Query on `req-<request_id>` & `su-gcp-<project_id>` |
| **4** | **`spp_list_approvals`** | `spp:approvals:read` | `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`, `openWorldHint: false` | `Status` | **REAL:** `GET /api/v1/approvals` & `GET /api/v1/approvals/{approval_id}` | `AgentListApprovalsWorkflow` / Query on `apr-<request_id>` |
| **5** | **`spp_list_catalog`** | `spp:catalog:read` | `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`, `openWorldHint: false` | `Cloud` | **REAL:** `GET /api/v1/kinds` | `AgentListCatalogWorkflow` (`wf-cat-*` on `spp-agent-actions`) |
| **6** | **`spp_submit_request`** | `spp:requests:write` | `readOnlyHint: false`, `destructiveHint: true`, `idempotentHint: true`, `openWorldHint: false` | `Kind`, `Action`, `Apm-Id`, `Environment` | **REAL:** `POST /api/v1/requests` | `AgentSubmitRequestWorkflow` (`wf-sub-<20hex>`) -> `req-<request_id>` & `apr-<request_id>` |
| **7** | **`spp_validate_request`** | `spp:requests:read` | `readOnlyHint: true`, `destructiveHint: false`, `idempotentHint: true`, `openWorldHint: false` | `Kind`, `Action`, `Apm-Id`, `Environment` | **PROPOSED:** `POST /api/v1/agent/workflows/validate` | `AgentValidateRequestWorkflow` (`wf-val-<20hex>` on `spp-agent-actions`) |

### 4. MRTR Elicitation (`SEP-2322`) & Async Tasks (`io.modelcontextprotocol/tasks`, `SEP-2663`) Mapped to Temporal

1. **MRTR Elicitation for Human Submission Confirmation:**
   - When `spp_submit_request` is invoked without a verified `inputResponses.confirm_gcs_submission` (and when the client declares `_meta.io.modelcontextprotocol/clientCapabilities.elicitation`), `spp-mcp` returns `InputRequiredResult` (`resultType: "input_required"`) containing an `elicitation/create` (`mode: "form"`) request displaying the normalized bucket name, `us-east1` region, the 8 mandatory labels, the CMEK key (`projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`), and `preview_sha256`, along with an AEAD-encrypted `requestState` bound to `(principal, ttl, preview_sha256, request_digest)`.
   - Only when the client retries `spp_submit_request` (with a new JSON-RPC `id`) supplying `inputResponses.confirm_gcs_submission.action == "accept"` and the valid single-use `requestState` does `spp-mcp` invoke `POST /api/v1/requests`.
2. **Async Tasks Extension (`io.modelcontextprotocol/tasks`) <-> Temporal Workflows:**
   - When the client declares `_meta.io.modelcontextprotocol/clientCapabilities.extensions["io.modelcontextprotocol/tasks"]`, `spp_submit_request` returns `CreateTaskResult` (`resultType: "task"`, `taskId = "req-<request_id>"`, `status = "input_required"`, `pollIntervalMs = 5000`).
   - `tasks/get` queries the Temporal workflows (`apr-<request_id>`, `req-<request_id>`, `su-gcp-<project_id>`) via `ssp-cp`:
     - While awaiting human `gcs_bucket_owner` approval, `tasks/get` returns `status: "input_required"` with a **URL mode elicitation** (`mode: "url"`, `url: "https://portal.taxi.growripple.ai/approvals/<approval_id>"`) so the human `bucket_owner` signs off out-of-band in the Portal UI (`self_approval = "deny"`).
     - During `GcsBucketProvisionWorkflow` execution (`tf-plan-<20hex>`, `tf-apply-<20hex>`), `tasks/get` returns `status: "working"`.
     - Upon Gate 4 (`OBSERVED`), `tasks/get` returns `status: "completed"` with the final structured resource projection.
   - `tasks/cancel` sends a cooperative Temporal `cancel` signal to `req-<request_id>` (if still in `REQUESTED` / `APPROVED` before `tf-apply-*` starts).

## Requirements

- **REQ-1 (MUST):** `spp-mcp` MUST implement **MCP specification revision `2026-07-28`** using the official Python SDK **`mcp >= 2.3.0`** (`httpx2 >= 2.10.0`), exposing `server/discover` and stateless Streamable HTTP (`POST /mcp`), validating `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method`, `Mcp-Name`, and `Mcp-Param-*` headers, and returning `400 Bad Request` with JSON-RPC error `-32020` (`HeaderMismatch`) on any header/body mismatch.
- **REQ-2 (MUST):** On Streamable HTTP, `spp-mcp` MUST act as an **OAuth 2.1 Resource Server** (`RFC 9728` `/.well-known/oauth-protected-resource`), validate `RFC 8707` audience-bound Bearer tokens (`aud == "https://mcp.spp.internal/mcp"`), enforce the four scopes (`spp:catalog:read`, `spp:requests:read`, `spp:requests:write`, `spp:approvals:read`), and forward the caller's identity to `ssp-cp`.
- **REQ-3 (MUST):** Every tool in `spp-mcp` MUST map **1:1** to the deterministic Temporal workflows in `ADR-AUT-004` (`namespace = "platform"`), declare JSON Schema 2020-12 `inputSchema` and `outputSchema`, return `structuredContent` validated against `outputSchema` (plus a serialized JSON `TextContent` block), and declare accurate `ToolAnnotations` (`title`, `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint: false`).
- **REQ-4 (MUST):** `spp_describe_gcs_bucket_schema` and `spp_validate_request` MUST enforce and surface the 8 mandatory labels (`LBL-001`, with `environmentsubtype` forbidden), APM ID normalization (`(?i)^APM\d{5}$` -> `^apm\d{5}$`), `location = "us-east1"`, and CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek` (`GCS-ENC-001`).
- **REQ-5 (MUST):** `spp_submit_request` MUST use MCP `2026-07-28` Multi Round-Trip Request (MRTR) Elicitation (`resultType: "input_required"`, `elicitation/create`, and AEAD-protected single-use `requestState` bound to caller principal, TTL, and `preview_sha256`) to obtain explicit human confirmation when the client supports elicitation, and MUST support `io.modelcontextprotocol/tasks` (`taskId = "req-<request_id>"`) mapped to Temporal queries/signals.
- **REQ-6 (MUST):** Resource approvals (`gcs_bucket_owner` v1, `self_approval = "deny"`, and mandatory human approval on all deletes in `nonprod` and `prod`) MUST remain strictly human; `spp-mcp` MUST NOT expose an autonomous approval-decision tool, and MUST use URL mode elicitation (`mode: "url"`) to direct human approvers to `https://portal.taxi.growripple.ai`.

## Guardrails

- **GR-1:** Never adopt deprecated MCP features removed or deprecated in `2026-07-28` (`HTTP+SSE` `2024-11-05` transport, `Mcp-Session-Id` stateful headers, `Last-Event-ID` SSE resumption, `roots`, `sampling`, or `logging/setLevel`).
- **GR-2:** Never mark sensitive fields (tokens, passwords, PII) with `x-mcp-header` (`Mcp-Param-*`), and never trust unverified `requestState` blobs on MRTR retries without AEAD verification of principal, TTL, and request digest.
- **GR-3:** Never allow an MCP tool to approve a request autonomously or allow `AUTO_APPROVED` / `auto_approved` on any `delete` request or destructive plan in `nonprod` or `prod`.
- **GR-4 (`INV-1`):** Never store or transmit plaintext secrets or GCP service account JSON keys in MCP tool arguments, `requestState`, or `structuredContent`.

## Consequences

### Positive

- Fully stateless Streamable HTTP (`2026-07-28`) enables effortless horizontal scaling of `spp-mcp` pods in `spp-platform` with zero session affinity.
- Native `outputSchema` + `structuredContent`, `ToolAnnotations`, MRTR `elicitation/create`, and `io.modelcontextprotocol/tasks` map cleanly onto SPP's `preview_sha256` confirmation gate and Temporal `workflow_id` lifecycle.

### Negative / Trade-offs

- Clients running pre-`2026-07-28` MCP SDKs (`1.x` / `2025-11-25`) require either upgrading to `mcp >= 2.3.0` / `@modelcontextprotocol/sdk >= 2.3.1` or enabling `mcp v2.3.0` backward-compatibility negotiation.

## Acceptance Criteria

- [ ] [`experiences/mcp/README.md`](../../experiences/mcp/README.md) and `ADR-EXP-002` pin MCP specification revision **`2026-07-28`** and official SDK **`mcp >= 2.3.0`** (`@modelcontextprotocol/sdk >= 2.3.1`).
- [ ] All 7 tools specify `inputSchema` (with `x-mcp-header` where applicable), `outputSchema` (`structuredContent`), `ToolAnnotations` (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`), OAuth 2.1 `spp:*` scopes, MRTR elicitation flows, and 1:1 Temporal workflow / `io.modelcontextprotocol/tasks` mapping.

## Success Criteria

- **SC-1:**
  - **Given** a `2026-07-28` MCP client calling `POST /mcp` (`Mcp-Method: tools/call`, `Mcp-Name: spp_validate_request`, `MCP-Protocol-Version: 2026-07-28`) with a valid audience-bound OAuth 2.1 token (`aud == "https://mcp.spp.internal/mcp"`, scope `spp:requests:read`)
  - **When** `spp-mcp` validates the `Mcp-Param-*` headers against the body and executes `AgentValidateRequestWorkflow` via `ssp-cp`
  - **Then** `spp-mcp` returns `resultType: "complete"` with `structuredContent` matching `outputSchema` (`workflow_id = "wf-val-*"`, 8 mandatory labels with `sppappid = "apm12345"`, CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`, and `preview_sha256`).
- **SC-2:**
  - **Given** a `2026-07-28` MCP client calling `spp_submit_request` (`id: 1`) with elicitation and `io.modelcontextprotocol/tasks` capabilities enabled
  - **When** `spp-mcp` first returns `resultType: "input_required"` (`elicitation/create` + AEAD `requestState`) and the client retries (`id: 2`) with `inputResponses` confirming submission
  - **Then** `spp-mcp` verifies the single-use `requestState`, submits the request to `ssp-cp`, and returns `CreateTaskResult` (`resultType: "task"`, `taskId = "req-<request_id>"`, `status = "input_required"`) whose subsequent `tasks/get` polls map 1:1 to the Temporal workflow state on namespace `platform`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-EXP-002` and [`experiences/mcp/README.md`](../../experiences/mcp/README.md) pinned to MCP `2026-07-28` |
| `ssp-cp` | Serves `/api/v1/*` endpoints, OAuth 2.1 / session verification, and Temporal workflow dispatch/query bridge |
| `ssp-workers` | Executes the 1:1 mapped Temporal workflows on namespace `platform` (`spp-agent-actions` and `spp-gcs-provisioning`) |
| `spp-factory-foundation` | Validates `ADR-EXP-002` via `lint_adrs.py` and MCP `2026-07-28` schema/header/MRTR contract tests |

## Open Questions

- [ ] **OQ-1 (OAuth 2.1 Authorization Server Hosting in `<spp-factory-host-project-id>` — [Owner: Manoj / Raju]):** Confirm whether `ssp-cp` exposes the OAuth 2.1 Authorization Server metadata (`/.well-known/oauth-authorization-server`) in `<spp-factory-host-project-id>` or delegates token issuance to the corporate OIDC IdP while `spp-mcp` hosts `/.well-known/oauth-protected-resource`.
- [ ] **OQ-2 (Legacy `2025-11-25` Client Fallback Mode — [Owner: Manoj / Dwayne]):** Confirm whether `spp-mcp` (`mcp v2.3.0`) should enable `2025-11-25` handshake fallback for older IDE clients or strictly enforce `MCP-Protocol-Version: 2026-07-28`.

## Related ADRs

- [ADR-AUT-004: Agent Harness ("Jev Model") and Deterministic Temporal Workflow Execution Layer](../automation/ADR-AUT-004-agent-harness-and-temporal-workflow-execution.md)
- [ADR-EXP-001: Agentic Chatbot Experience for Self-Service Provisioning](ADR-EXP-001-agentic-chatbot-experience.md)
- [ADR-EXP-003: Client SDK Experience (Python First, TypeScript Later)](ADR-EXP-003-client-sdk-experience.md)
- [ADR-EXP-004: Portal UI Experience (`ssp-ui` Storefront on IDP Design Variant 17)](ADR-EXP-004-portal-ui-experience.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-008: Label and Tag Standard](../global/ADR-GLB-008-label-and-tag-standard.md)
- [ADR-GLB-009: Resource Kind Registry](../global/ADR-GLB-009-resource-kind-registry.md)
