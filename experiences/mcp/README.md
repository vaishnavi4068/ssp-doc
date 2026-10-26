# MCP Server Experience (`spp-mcp`) — `experiences/mcp/`

- **Governing ADRs:**
  - [`ADR-EXP-002: MCP Server Experience for Self-Service Provisioning`](../../adr/experience/ADR-EXP-002-mcp-server-experience.md) (`Status: Proposed`)
  - [`ADR-AUT-004: Agent Harness ("Jev Model") and Deterministic Temporal Workflow Execution Layer`](../../adr/automation/ADR-AUT-004-agent-harness-and-temporal-workflow-execution.md) (`Status: Proposed`)
  - [`ADR-SVC-001: First Vertical Slice — GCS Bucket (gcs_bucket) End-to-End and Guardrails`](../../adr/endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
  - [`ADR-GLB-003`](../../adr/global/ADR-GLB-003-four-state-model.md), [`ADR-GLB-004`](../../adr/global/ADR-GLB-004-data-model-and-database.md), [`ADR-GLB-005`](../../adr/global/ADR-GLB-005-identity-and-authentication.md), [`ADR-GLB-006`](../../adr/global/ADR-GLB-006-naming-and-labeling-conventions.md), [`ADR-GLB-007`](../../adr/global/ADR-GLB-007-governance-gates-and-policy-rego.md), [`ADR-GLB-008`](../../adr/global/ADR-GLB-008-label-and-tag-standard.md), [`ADR-GLB-009`](../../adr/global/ADR-GLB-009-resource-kind-registry.md), [`ADR-BP-003`](../../adr/business-process/ADR-BP-003-roles-and-approver-governance.md), [`ADR-AUT-001`](../../adr/automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- **Pinned MCP Specification Revision:** **`2026-07-28`** (*Current* protocol revision per [`https://modelcontextprotocol.io/specification/versioning`](https://modelcontextprotocol.io/specification/versioning) and [`https://modelcontextprotocol.io/specification/2026-07-28/changelog`](https://modelcontextprotocol.io/specification/2026-07-28/changelog), superseding `2025-11-25`).
- **Official MCP SDK Versions Supporting Revision `2026-07-28`:**
  - **Python SDK (`modelcontextprotocol/python-sdk`):** **`mcp >= 2.0.0`** (pinned at latest release **`v2.3.0`**, published `2026-10-02`, requiring `httpx2 >= 2.10.0`).
  - **TypeScript SDK (`modelcontextprotocol/typescript-sdk`, for Phase 5 client/host tooling):** **`@modelcontextprotocol/sdk >= 2.0.0`** (latest release **`v2.3.1`**, published `2026-10-05`).
- **First Feature Covered:** Google Cloud Storage Bucket (`kind = "gcs_bucket"`, region `us-east1`, environments `nonprod` and `prod` only).
- **Submission Channel:** `channel = "api"` (or `"chat"` when invoked from an IDE chat host), `source_ref = "mcp:2026-07-28:<tool_name>:<client_name>"`.

---

## 1. Purpose & Shared Architectural Principle

The **MCP Server Experience (`spp-mcp`)** exposes the Self-Service Provisioning Platform (SPP) through the **Model Context Protocol (MCP) revision `2026-07-28`** so IDE and CLI AI coding assistants (Cursor, Claude Code, Gemini CLI) can inspect the SPP service catalog, describe the GCS bucket schema and guardrail rules, dry-run validate requests, submit GCS bucket requests on the user's behalf, inspect 4-gate status and Terraform plans, and list pending approvals.

### Non-Negotiable Core Principles

1. **Same `ssp-cp` API & Same Policy/Approval Path (No Privileged Channel):** `spp-mcp` is a stateless protocol adapter backed exclusively by the `ssp-cp` FastAPI API (via the `spp-sdk` Python client). It has zero direct connectivity to AlloyDB (`spp_platform`), zero direct OPA override access, zero Kubernetes Job launch permissions, and zero GCS state bucket credentials.
2. **1:1 Mapping to Deterministic Temporal Workflows (`ADR-AUT-004`):** In alignment with the **Jev model Agent Harness** ([`../agentic-chat/agent-harness.md`](../agentic-chat/agent-harness.md)), MCP tools never execute side effects directly. Every MCP tool maps **1:1** to the same deterministic Temporal workflows on Temporal namespace **`platform`** (using proposed task queue `spp-agent-actions` for interactive validation/status/plan workflows and existing task queue `spp-gcs-provisioning` for `GcsBucketProvisionWorkflow` / `ApprovalGateWorkflow` / `StateUnitReconcilerWorkflow`), passing an explicit `idempotency_key` and returning deterministic `workflow_id`s in every tool response.
3. **Pinned to MCP Specification Revision `2026-07-28` (`mcp == 2.3.0`):**
   - **Stateless Streamable HTTP (`SEP-2567`, `SEP-2575`):** Exposes a single `POST /mcp` endpoint with **no protocol-level sessions** (no `Mcp-Session-Id` header, no `initialize` / `notifications/initialized` handshake, no `GET` SSE stream). Every request carries `_meta["io.modelcontextprotocol/protocolVersion"] = "2026-07-28"`, `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method`, and (for `tools/call`) `Mcp-Name`.
   - **Mandatory `server/discover` RPC (`SEP-2575`):** Advertises `supportedVersions: ["2026-07-28"]`, capabilities (`tools`, `resources`, and the `io.modelcontextprotocol/tasks` extension), `serverInfo`, `ttlMs`, and `cacheScope`.
   - **Multi Round-Trip Requests (MRTR) & Elicitation (`SEP-2322`):** Uses `resultType: "input_required"` with `inputRequests` (`elicitation/create` in `form` or `url` mode) and AEAD-protected `requestState` for human-in-the-loop confirmation before any state-changing submission.
   - **Official `io.modelcontextprotocol/tasks` Extension (`SEP-2663`):** Maps MCP asynchronous task handles (`resultType: "task"`, `taskId`, `tasks/get`, `tasks/update`, `tasks/cancel`, and `notifications/tasks` over `subscriptions/listen`) directly to SPP's deterministic **Temporal `workflow_id`s**, Temporal `@workflow.query` handlers, and Temporal `@workflow.signal` handlers on namespace `platform`.
4. **Strict Read vs. Write Tool Separation & Human-Only Approvals (`ADR-BP-003`):**
   - **Read tools** (`spp:catalog:read`, `spp:requests:read`, `spp:approvals:read`) are side-effect-free (`readOnlyHint: true`, `openWorldHint: false`).
   - **Write tools** (`spp:requests:write`) require a valid `preview_sha256` from `spp_validate_request`, an `idempotency_key`, and a human confirmation step via MCP Elicitation (`elicitation/create`).
   - **Approvals Stay Strictly Human:** `spp-mcp` exposes **read-only approval inspection (`spp_list_approvals`)** so AI agents cannot autonomously approve infrastructure requests. Any approval decision must be executed by a distinct human approver (`bucket_owner` / `approver` role, `self_approval = "deny"`), and `AUTO_APPROVED` / `auto_approved` is permanently forbidden on all deletes in `nonprod` and `prod`.

---

## 2. Pinned MCP `2026-07-28` Protocol Features & SPP Mapping

| MCP `2026-07-28` Feature | Spec Citation (`2026-07-28`) | How `spp-mcp` (`mcp v2.3.0`) Implements It |
| :--- | :--- | :--- |
| **Stateless Streamable HTTP & Header Validation** | `basic/transports/streamable-http` (`SEP-2567`, `SEP-2575`, `SEP-2243`) | Single `POST /mcp` endpoint (`Origin` validated, `405` on `GET`/`DELETE`, `X-Accel-Buffering: no` on SSE responses). Validates `MCP-Protocol-Version: 2026-07-28`, `Mcp-Method`, `Mcp-Name`, and mirrored `x-mcp-header` parameters (`Mcp-Param-Kind`, `Mcp-Param-Action`, `Mcp-Param-Apm-Id`, `Mcp-Param-Environment`); mismatches return `400 Bad Request` with JSON-RPC error `-32020` (`HeaderMismatch`). |
| **`server/discover` & `CacheableResult`** | `server/discover` (`SEP-2575`), `server/utilities/caching` (`SEP-2549`) | Implements mandatory `server/discover` returning `supportedVersions: ["2026-07-28"]`, `capabilities.tools`, `capabilities.extensions["io.modelcontextprotocol/tasks"]`, `ttlMs: 3600000`, `cacheScope: "public"`. All `tools/list` responses return tools in deterministic alphabetical order with `ttlMs: 300000` and `cacheScope: "private"` (scoped to caller's OAuth scopes). |
| **OAuth 2.1 Resource Server & Protected Resource Metadata** | `basic/authorization` (`RFC 9728`, `RFC 8707`, `RFC 9207`, `SEP-2468`, `SEP-2352`) | `spp-mcp` acts as an OAuth 2.1 Resource Server serving `GET /.well-known/oauth-protected-resource` with `resource: "https://mcp.spp.internal/mcp"` and `scopes_supported: ["spp:catalog:read", "spp:requests:read", "spp:requests:write", "spp:approvals:read"]`. Enforces RFC 8707 audience-bound tokens (`aud == "https://mcp.spp.internal/mcp"`) and returns `401 Unauthorized` with `WWW-Authenticate: Bearer resource_metadata="...", scope="spp:..."` on missing/insufficient scopes. *(Also supports local `stdio` transport for workstation/CI dev sessions using env/keychain session credentials per `basic/authorization` §Protocol Requirements).* |
| **Structured Tool Output (`outputSchema` + `structuredContent`)** | `server/tools` (`SEP-2106`, JSON Schema `2020-12`) | Every tool declares both `inputSchema` and `outputSchema` (JSON Schema Draft 2020-12) and returns `resultType: "complete"` with validated `structuredContent` alongside a serialized JSON `TextContent` block (`content: [{"type": "text", "text": "..."}]`). |
| **Tool Annotations (`ToolAnnotations`)** | `schema` (`ToolAnnotations`: `title`, `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`) | Every tool in `spp-mcp` declares all five standard `ToolAnnotations` fields (`title`, `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint: false`). |
| **Multi Round-Trip Requests (MRTR) & Elicitation** | `basic/patterns/mrtr` (`SEP-2322`), `client/elicitation` (`form` and `url` modes) | When `spp_submit_request` is invoked without a confirmed `inputResponses.confirm_submission` (or for `action == "delete"`), `spp-mcp` returns `resultType: "input_required"` containing an `elicitation/create` request (`mode: "form"` for create/update confirmation of `preview_sha256` and 8 mandatory labels; `mode: "url"` pointing to `https://portal.taxi.growripple.ai/requests/<id>` for out-of-band sensitive/approver interactions) plus an AEAD-encrypted `requestState` bound to `(principal, ttl, preview_sha256, request_digest)`. |
| **Async Tasks Extension (`io.modelcontextprotocol/tasks`) Mapped to Temporal** | `extensions/tasks/overview` (`SEP-2663`) | Long-running operations (waiting for human `gcs_bucket_owner` approval or `GcsBucketProvisionWorkflow` / `StateUnitReconcilerWorkflow` completion) return `CreateTaskResult` (`resultType: "task"`, `taskId = workflow_id` e.g. `"req-<request_id>"`, `status: "working" | "input_required" | "completed" | "failed" | "cancelled"`, `ttlMs`, `pollIntervalMs: 5000`). `tasks/get` maps to Temporal `@workflow.query`, `tasks/update` maps to Temporal `@workflow.signal`, and `tasks/cancel` maps to Temporal `cancel` signal on `req-<request_id>`. |
| **OpenTelemetry Context in `_meta`** | `changelog` (`SEP-414`) | Propagates `_meta.traceparent`, `_meta.tracestate`, and `_meta.baggage` from MCP JSON-RPC requests into `ssp-cp` HTTP headers and Temporal workflow spans. |

---

## 3. MCP Tool Catalog, Annotations & 1:1 Temporal Workflow Mapping (GCS Bucket First)

All 7 tools are returned by `tools/list` in deterministic alphabetical order (`cacheScope: "private"`, `ttlMs: 300000`) and map **1:1** to the deterministic Temporal workflows defined in `ADR-AUT-004` on Temporal namespace **`platform`**:

| # | Tool Name | `title` | Required Scope | `ToolAnnotations` (`2026-07-28` Schema) | `x-mcp-header` Mirrored Params (`Mcp-Param-*`) | `ssp-cp` Endpoint (`REAL` vs. `PROPOSED`) | 1:1 Temporal Workflow on `platform` (`ADR-AUT-004`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **`spp_describe_gcs_bucket_schema`** | Describe GCS Bucket Schema & Guardrails | `spp:catalog:read` | `readOnlyHint: true`<br>`destructiveHint: false`<br>`idempotentHint: true`<br>`openWorldHint: false` | None | **REAL:** `GET /api/v1/kinds` + **PROPOSED:** `GET /api/v1/kinds/gcs_bucket/schema` | `AgentDescribeSchemaWorkflow` (`wf-sch-gcs_bucket-1.0.0` on `spp-agent-actions`) |
| **2** | **`spp_get_request_plan`** | Get GCS Bucket Terraform Plan Summary | `spp:requests:read` | `readOnlyHint: true`<br>`destructiveHint: false`<br>`idempotentHint: true`<br>`openWorldHint: false` | `request_id` -> `Mcp-Param-Request-Id` | **REAL:** `GET /api/v1/requests/{request_id}` + **PROPOSED:** `GET /api/v1/requests/{request_id}/plan` | **`AgentGetPlanWorkflow`** (`wf-pln-<request_id>-<rev>` on `spp-agent-actions`) |
| **3** | **`spp_get_request_status`** | Get 4-Gate Request & Resource Status | `spp:requests:read` | `readOnlyHint: true`<br>`destructiveHint: false`<br>`idempotentHint: true`<br>`openWorldHint: false` | `request_id` -> `Mcp-Param-Request-Id` | **REAL:** `GET /api/v1/requests/{request_id}` & `GET /api/v1/resources/{resource_id}` (`app/main.py:514, 658`) | **`AgentGetStatusWorkflow`** / Temporal Query on `req-<request_id>` & `su-gcp-<project_id>` |
| **4** | **`spp_list_approvals`** | List Pending & Decided Human Approvals | `spp:approvals:read` | `readOnlyHint: true`<br>`destructiveHint: false`<br>`idempotentHint: true`<br>`openWorldHint: false` | `status` -> `Mcp-Param-Status` | **REAL:** `GET /api/v1/approvals` & `GET /api/v1/approvals/{approval_id}` (`app/main.py:529, 544`) | **`AgentListApprovalsWorkflow`** / Temporal Query on `apr-<request_id>` |
| **5** | **`spp_list_catalog`** | List Enabled SPP Resource Kinds | `spp:catalog:read` | `readOnlyHint: true`<br>`destructiveHint: false`<br>`idempotentHint: true`<br>`openWorldHint: false` | `cloud` -> `Mcp-Param-Cloud` | **REAL:** `GET /api/v1/kinds` (`app/main.py:434`) | `AgentListCatalogWorkflow` (`wf-cat-*` on `spp-agent-actions`) |
| **6** | **`spp_submit_request`** | Submit Validated GCS Bucket Request | `spp:requests:write` | `readOnlyHint: false`<br>`destructiveHint: true` *(may request `action="delete"`; additive when `action="create"`)*<br>`idempotentHint: true`<br>`openWorldHint: false` | `kind` -> `Mcp-Param-Kind`<br>`action` -> `Mcp-Param-Action`<br>`metadata.apm_id` -> `Mcp-Param-Apm-Id`<br>`metadata.environment` -> `Mcp-Param-Environment` | **REAL:** `POST /api/v1/requests` (`app/main.py:466`) | **`AgentSubmitRequestWorkflow`** (`wf-sub-<20hex>`) -> creates `req-<request_id>` & `apr-<request_id>` (and returns MCP Task handle `taskId = "req-<request_id>"` when `io.modelcontextprotocol/tasks` is negotiated) |
| **7** | **`spp_validate_request`** | Dry-Run Validate GCS Bucket Request & Preview Guardrails | `spp:requests:read` | `readOnlyHint: true`<br>`destructiveHint: false`<br>`idempotentHint: true`<br>`openWorldHint: false` | `kind` -> `Mcp-Param-Kind`<br>`action` -> `Mcp-Param-Action`<br>`metadata.apm_id` -> `Mcp-Param-Apm-Id`<br>`metadata.environment` -> `Mcp-Param-Environment` | **PROPOSED:** `POST /api/v1/agent/workflows/validate` *(or `POST /api/v1/requests/validate`)* | **`AgentValidateRequestWorkflow`** (`wf-val-<20hex>` on `spp-agent-actions`) |

*(Note: `POST /api/v1/approvals/{approval_id}/decisions` is intentionally NOT exposed as an MCP tool so AI coding agents cannot approve requests. Human approvers execute decisions via the Portal UI `https://portal.taxi.growripple.ai`, the HITL-gated approver view, or out-of-band URL mode elicitation.)*

---

## 4. User Journeys (Under MCP `2026-07-28`)

### Journey 1: Stateless Discovery (`server/discover`), Dry-Run Validation (`spp_validate_request`), and MRTR Elicitation Confirmation (`spp_submit_request`)
1. **Discovery (`server/discover`):** Cursor / Claude Code connects to `https://mcp.spp.internal/mcp` and sends `POST /mcp` (`Mcp-Method: server/discover`, `MCP-Protocol-Version: 2026-07-28`). `spp-mcp` returns `supportedVersions: ["2026-07-28"]`, `capabilities: {"tools": {"listChanged": true}, "extensions": {"io.modelcontextprotocol/tasks": {}}}`, and `ttlMs: 3600000`.
2. **Schema Inspection (`spp_describe_gcs_bucket_schema`):** The client calls `spp_describe_gcs_bucket_schema` and receives `structuredContent` describing the **8 mandatory labels** (`sppappid`, `costcenter`, `environmenttype` in `nonprod`|`prod` with `environmentsubtype` dropped/forbidden, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`), APM ID normalization (`(?i)^APM\d{5}$` -> `^apm\d{5}$`), `location = "us-east1"`, and CMEK URI `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`.
3. **Dry-Run Validation (`spp_validate_request`):** The client sends `tools/call` (`Mcp-Name: spp_validate_request`, `Mcp-Param-Kind: gcs_bucket`, `Mcp-Param-Action: create`, `Mcp-Param-Apm-Id: APM12345`, `Mcp-Param-Environment: dev`). `ssp-cp` runs `AgentValidateRequestWorkflow` (`wf-val-*`) and returns `resultType: "complete"` with `structuredContent` containing the 10-entry `guardrail_trace_preview`, the 8 mandatory labels, and `preview_sha256`.
4. **MRTR Elicitation for Human Submission Confirmation (`spp_submit_request` Call #1):**
   - When the client calls `spp_submit_request` (`id: 10`) with `preview_sha256` and `_meta.io.modelcontextprotocol/clientCapabilities.elicitation.form`, `spp-mcp` responds with **`resultType: "input_required"`** (`InputRequiredResult`):
     - `inputRequests.confirm_gcs_submission`: `method: "elicitation/create"`, `mode: "form"`, prompting the human developer to confirm `confirm_submit: true` and review the bucket name, `us-east1` location, CMEK key, and `gcs_bucket_owner` approval gate.
     - `requestState`: AEAD-sealed token binding `(caller_sub, exp, preview_sha256, idempotency_key)`.
5. **MRTR Retry with `inputResponses` (`spp_submit_request` Call #2):**
   - After the human clicks **Accept** in the MCP host UI, the client retries `tools/call` (`id: 11`, new JSON-RPC `id` per MRTR spec) with the original arguments + `inputResponses.confirm_gcs_submission = {"action": "accept", "content": {"confirm_submit": true}}` + `requestState`.
   - `spp-mcp` verifies the AEAD `requestState` (single-use redemption), invokes `POST /api/v1/requests` on `ssp-cp`, and returns either:
     - `resultType: "complete"` with `structuredContent` (`request_id`, `approval_id`, `temporal_workflow_id = "req-<request_id>"`, `approval_workflow_id = "apr-<request_id>"`), **or**
     - `resultType: "task"` (`CreateTaskResult` with `taskId = "req-<request_id>"`, `status = "input_required"` waiting on human `bucket_owner` sign-off) when the client negotiated `io.modelcontextprotocol/tasks`.

### Journey 2: Tracking Long-Running Approval & Provisioning via MCP Tasks (`io.modelcontextprotocol/tasks` <-> Temporal Workflows)
1. **Task Polling (`tasks/get`):** The MCP client polls `tasks/get` with `taskId = "req-<request_id>"` (`pollIntervalMs = 5000`), or subscribes to `notifications/tasks` via `POST /mcp` (`Mcp-Method: subscriptions/listen`).
2. **Temporal Mapping:**
   - While `idp.approval.status == "PENDING"`, `tasks/get` queries `ApprovalGateWorkflow` (`apr-<request_id>`) and returns `status: "input_required"` with a **URL mode elicitation** (`mode: "url"`, `url: "https://portal.taxi.growripple.ai/approvals/<approval_id>"`) directing the human `bucket_owner` (`bucket.owner@example.com`, `self_approval = "deny"`) to review and approve in the Portal UI.
   - Once `bucket_owner` approves, `ssp-cp` dispatches **`GcsBucketProvisionWorkflow`** (`req-<request_id>` on task queue `spp-gcs-provisioning`). `tasks/get` returns `status: "working"` with status message showing `tf-plan-eba5f9ebf4fafecad8e9` (`plan_summary: +3 ~0 -0`) and `tf-apply-b85d57b4511c03e98373`.
   - When Gate 4 (`OBSERVED`) is reached in `gs://microdrive-dev-spp-tfstate`, `tasks/get` returns `status: "completed"` with the final `< 2000`-byte `observed.projection` (`cloud_resource_id = "projects/_/buckets/..."`).

---

## 5. Architecture & Protocol Flow Diagrams

### 5.1 Component & OAuth 2.1 Resource Server Architecture

```mermaid
flowchart TB
    subgraph Host["MCP Host (Cursor / Claude Code / Gemini CLI — MCP 2026-07-28)"]
        Client["MCP Client (@modelcontextprotocol/sdk v2.3.1 / mcp v2.3.0)\n- Sends MCP-Protocol-Version: 2026-07-28\n- Mirrors Mcp-Method, Mcp-Name, Mcp-Param-*\n- Handles MRTR InputRequiredResult & Tasks (tasks/get)"]
    end

    subgraph AuthServer["Corporate IdP / ssp-cp Auth Server"]
        AS["OAuth 2.1 Authorization Server\n- RFC 8414 / OIDC Discovery\n- Client ID Metadata Documents\n- Issues audience-bound JWT (aud=https://mcp.spp.internal/mcp)\n- Emits RFC 9207 iss in auth response"]
    end

    subgraph HostProject["SPP-factory-host GCP project (SPP VPC / SPP GKE cluster — Region: us-east1)"]
        subgraph MCPServer["SPP MCP Server (spp-mcp — Python mcp v2.3.0 in K8s ns: spp-platform)"]
            PRM["GET /.well-known/oauth-protected-resource (RFC 9728)\nresource: https://mcp.spp.internal/mcp\nscopes_supported: spp:catalog:read, spp:requests:read,\nspp:requests:write, spp:approvals:read"]
            Endpoint["Stateless Streamable HTTP Endpoint (POST /mcp)\n- Validates Origin, MCP-Protocol-Version, Mcp-Method, Mcp-Name, Mcp-Param-*\n- Validates OAuth 2.1 Bearer JWT (RFC 8707 aud + scopes)\n- Verifies AEAD requestState on MRTR retries\n- Secret Scanner (INV-1)"]
            TasksBridge["MCP Tasks Bridge (io.modelcontextprotocol/tasks)\n- taskId == Temporal workflow_id (req-<request_id>)\n- tasks/get -> Temporal @workflow.query\n- tasks/update -> Temporal @workflow.signal\n- tasks/cancel -> Temporal cancel signal"]
            SDK["SPP Python Client SDK (spp-sdk)"]
        end

        subgraph ControlPlane["ssp-cp FastAPI Control Plane (K8s ns: spp-platform)"]
            CPAPI["/api/v1/kinds, /requests, /approvals, /resources, /audit\n+ Proposed /api/v1/agent/workflows/validate & /requests/{id}/plan"]
            OPA["OPA Server (ns: spp-policy :8181)\nidp.gcp.gcs_bucket"]
            AlloyDB[("AlloyDB (spp_platform)\nSchema idp")]
        end

        subgraph Temporal["Temporal Server (ns: spp-temporal, Temporal namespace: platform)"]
            AgentQueue["Task Queue: spp-agent-actions (Proposed)\nAgentValidateRequestWorkflow (wf-val-*)\nAgentSubmitRequestWorkflow (wf-sub-*)\nAgentGetStatusWorkflow / AgentGetPlanWorkflow"]
            GcsQueue["Task Queue: spp-gcs-provisioning (Existing)\nGcsBucketProvisionWorkflow (req-<request_id>)\nApprovalGateWorkflow (apr-<request_id>)\nStateUnitReconcilerWorkflow (su-gcp-<project_id>)"]
        end
    end

    Client <-->|"1. 401 WWW-Authenticate -> RFC 9728 Discovery"| PRM
    Client <-->|"2. OAuth 2.1 PKCE + resource=https://mcp.spp.internal/mcp"| AS
    Client <-->|"3. POST /mcp (Bearer JWT + MCP-Protocol-Version: 2026-07-28)"| Endpoint
    Endpoint --> TasksBridge
    Endpoint --> SDK
    TasksBridge --> SDK
    SDK --> CPAPI
    CPAPI --> OPA
    CPAPI --> AlloyDB
    CPAPI <--> AgentQueue
    CPAPI <--> GcsQueue
```

### 5.2 MRTR Elicitation (`SEP-2322`) & Async Tasks (`SEP-2663`) Sequence

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer (Requester)
    participant Client as MCP Client (2026-07-28)
    participant MCP as spp-mcp (POST /mcp)
    participant CP as ssp-cp FastAPI API
    participant Temp as Temporal (ns: platform)
    actor Owner as Bucket Owner (Approver)

    Client->>MCP: POST /mcp (Mcp-Method: tools/call, Mcp-Name: spp_validate_request)
    MCP->>CP: POST /api/v1/agent/workflows/validate
    CP->>Temp: Run AgentValidateRequestWorkflow (wf-val-*)
    Temp-->>CP: normalized_spec + 8 labels + 10 guardrail_trace + preview_sha256
    CP-->>MCP: ValidationResult
    MCP-->>Client: 200 OK (resultType: "complete", structuredContent: {preview_sha256, ...})

    Client->>MCP: POST /mcp (id: 2, Mcp-Name: spp_submit_request, preview_sha256)
    Note over MCP: Missing inputResponses.confirm_gcs_submission -> trigger MRTR Elicitation
    MCP-->>Client: 200 OK (resultType: "input_required", inputRequests: {confirm_gcs_submission: elicitation/create (mode: form)}, requestState: "<AEAD>")
    Client->>Dev: Render Elicitation Form (Confirm bucket creation in us-east1 with CMEK & 8 labels?)
    Dev-->>Client: Accept (confirm_submit: true)

    Client->>MCP: POST /mcp (id: 3, Mcp-Name: spp_submit_request, inputResponses: {confirm_gcs_submission}, requestState: "<AEAD>")
    Note over MCP: Verify AEAD requestState (principal, TTL, preview_sha256, single-use)
    MCP->>CP: POST /api/v1/requests (Idempotency-Key, channel="api", source_ref="mcp:2026-07-28:spp_submit_request")
    CP-->>MCP: 201 Created (request_id, approval_id, workflow_id="req-<request_id>")
    MCP-->>Client: 200 OK (resultType: "task", taskId: "req-<request_id>", status: "input_required", pollIntervalMs: 5000)

    Client->>MCP: POST /mcp (Mcp-Method: tasks/get, taskId: "req-<request_id>")
    MCP-->>Client: Task (status: "input_required", inputRequests: {owner_approval: elicitation/create (mode: "url", url: "https://portal.taxi.growripple.ai/approvals/<approval_id>")})
    Owner->>CP: Approve via Portal UI (POST /api/v1/approvals/<approval_id>/decisions)
    CP->>Temp: Start GcsBucketProvisionWorkflow (id="req-<request_id>", queue="spp-gcs-provisioning")

    Client->>MCP: POST /mcp (Mcp-Method: tasks/get, taskId: "req-<request_id>")
    MCP->>CP: GET /api/v1/requests/<request_id> & GET /api/v1/resources/<resource_id>
    MCP-->>Client: Task (status: "completed", result: {gate: "OBSERVED", cloud_resource_id: "projects/_/buckets/..."})
```

---

## 6. OAuth 2.1 Authorization & Scope Mapping (`2026-07-28` Spec)

Per the MCP `2026-07-28` Authorization specification (`https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization`):

### 6.1 OAuth 2.0 Protected Resource Metadata (`RFC 9728`)
`spp-mcp` serves `GET /.well-known/oauth-protected-resource`:

```json
{
  "resource": "https://mcp.spp.internal/mcp",
  "authorization_servers": [
    "https://auth.spp.internal"
  ],
  "scopes_supported": [
    "spp:catalog:read",
    "spp:requests:read",
    "spp:requests:write",
    "spp:approvals:read"
  ],
  "bearer_methods_supported": [
    "header"
  ],
  "resource_documentation": "https://github.com/vaishnavi4068/ssp-doc/tree/main/experiences/mcp"
}
```

### 6.2 Client Registration, `resource` Indicator (`RFC 8707`), and `iss` Validation (`RFC 9207`)
1. **Client ID Metadata Documents (`draft-ietf-oauth-client-id-metadata-document-00`):** Preferred client registration mechanism in MCP `2026-07-28` (Dynamic Client Registration `RFC 7591` is deprecated in `2026-07-28` and kept only as a fallback).
2. **Audience-Bound Tokens (`RFC 8707`):** Clients MUST include `resource=https%3A%2F%2Fmcp.spp.internal%2Fmcp` on both the authorization request and token request. `spp-mcp` validates that every `Authorization: Bearer <jwt>` token carries `aud == "https://mcp.spp.internal/mcp"` and rejects any token issued for another audience with `401 Unauthorized`.
3. **Issuer Identification (`RFC 9207`, `SEP-2468`):** The authorization server sets `authorization_response_iss_parameter_supported: true` and returns `iss` on every authorization callback.
4. **Step-Up `WWW-Authenticate` Scope Challenge (`RFC 6750`):**
   - Unauthenticated calls or calls with expired tokens return `401 Unauthorized`:
     ```http
     HTTP/1.1 401 Unauthorized
     WWW-Authenticate: Bearer resource_metadata="https://mcp.spp.internal/.well-known/oauth-protected-resource", scope="spp:catalog:read spp:requests:read"
     ```
   - Calling `spp_submit_request` with only read scopes returns `403 Forbidden` with `WWW-Authenticate: Bearer error="insufficient_scope", scope="spp:requests:write"`.
5. **Local `stdio` Transport Exception (`basic/authorization` §Protocol Requirements):**
   - Per the MCP `2026-07-28` spec (*"Implementations using an STDIO transport SHOULD NOT follow this specification, and instead retrieve credentials from the environment"*), when `spp-mcp` runs locally over `stdio`, it authenticates to `ssp-cp` via `POST /api/v1/auth/login` (Argon2id local login, holding `__Host-spp_cp_session` and `X-CSRF-Token` in process memory and checking `must_change_password == false` via `GET /api/v1/me`).

---

## 7. Complete Tool Definitions (`inputSchema`, `outputSchema`, `annotations`, `x-mcp-header`)

Below is the canonical `2026-07-28` tool definition and response envelope for `spp_validate_request` and `spp_submit_request` (all 7 tools follow this exact structure):

### 7.1 `spp_validate_request` Tool Definition (`tools/list` Entry)

```json
{
  "name": "spp_validate_request",
  "title": "Dry-Run Validate GCS Bucket Request & Preview Guardrails",
  "description": "Executes deterministic Temporal workflow AgentValidateRequestWorkflow (wf-val-*) on namespace 'platform' via ssp-cp to normalize inputs (APM ID ^APM\\d{5}$ -> ^apm\\d{5}$, env -> nonprod|prod), validate against closed JSON Schema and OPA package idp.gcp.gcs_bucket, compute the 8 mandatory labels (no environmentsubtype), resolve CMEK key projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek, and return preview_sha256.",
  "annotations": {
    "title": "Dry-Run Validate GCS Bucket Request",
    "readOnlyHint": true,
    "destructiveHint": false,
    "idempotentHint": true,
    "openWorldHint": false
  },
  "inputSchema": {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": false,
    "required": ["idempotency_key", "kind", "action", "metadata", "spec"],
    "properties": {
      "idempotency_key": { "type": "string", "minLength": 1, "maxLength": 128 },
      "kind": {
        "type": "string",
        "enum": ["gcs_bucket"],
        "x-mcp-header": "Kind"
      },
      "action": {
        "type": "string",
        "enum": ["create", "update", "delete"],
        "x-mcp-header": "Action"
      },
      "metadata": {
        "type": "object",
        "additionalProperties": false,
        "required": ["apm_id", "project_id", "environment", "lob", "owner"],
        "properties": {
          "apm_id": {
            "type": "string",
            "pattern": "^(?i)APM[0-9]{5}$",
            "x-mcp-header": "Apm-Id"
          },
          "project_id": { "type": "string", "minLength": 1 },
          "environment": {
            "type": "string",
            "x-mcp-header": "Environment"
          },
          "lob": { "type": "string", "minLength": 2, "maxLength": 6 },
          "data_sensitivity": { "type": "string", "default": "restricted" },
          "data_classification": { "type": "string", "default": "proprietary" },
          "owner": { "type": "string", "format": "email" },
          "shared_mailbox": { "type": "string" },
          "cost_center": { "type": "string", "default": "000000" },
          "tenancy": { "type": "string", "enum": ["dedicated", "shared"], "default": "dedicated" },
          "labels": {
            "type": "object",
            "additionalProperties": { "type": "string" }
          }
        }
      },
      "spec": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "name": { "type": "string", "maxLength": 63 },
          "purpose_token": { "type": "string", "minLength": 2, "maxLength": 20 },
          "purpose": { "type": "string" },
          "location": { "type": "string", "const": "us-east1", "default": "us-east1" },
          "storage_class": {
            "type": "string",
            "enum": ["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"],
            "default": "STANDARD"
          },
          "versioning": { "type": "boolean", "default": false },
          "lifecycle_rules": { "type": "array", "default": [] },
          "access": { "type": "array", "default": [] }
        }
      }
    }
  },
  "outputSchema": {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "additionalProperties": false,
    "required": [
      "workflow_id",
      "temporal_namespace",
      "task_queue",
      "decision",
      "violations",
      "normalized_requested_spec",
      "computed_labels",
      "resolved_kms_key",
      "guardrail_trace_preview",
      "approval_gate_required",
      "preview_sha256"
    ],
    "properties": {
      "workflow_id": { "type": "string", "pattern": "^wf-val-[0-9a-f]{20}$" },
      "temporal_namespace": { "type": "string", "const": "platform" },
      "task_queue": { "type": "string", "const": "spp-agent-actions" },
      "decision": { "type": "string", "enum": ["allow", "deny", "allow_with_mutations"] },
      "violations": { "type": "array" },
      "normalized_requested_spec": { "type": "object" },
      "computed_labels": {
        "type": "object",
        "required": [
          "sppappid",
          "costcenter",
          "environmenttype",
          "primarylob",
          "datasensitivity",
          "owner",
          "provisionedby",
          "idp_resource_id"
        ]
      },
      "resolved_kms_key": {
        "type": "string",
        "const": "projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek"
      },
      "guardrail_trace_preview": { "type": "array" },
      "approval_gate_required": { "type": "object" },
      "preview_sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" }
    }
  }
}
```

### 7.2 `spp_validate_request` Call & Structured Response (`2026-07-28` Wire Format)

**HTTP POST Request:**
```http
POST /mcp HTTP/1.1
Host: mcp.spp.internal
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
Content-Type: application/json
Accept: application/json, text/event-stream
MCP-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Name: spp_validate_request
Mcp-Param-Kind: gcs_bucket
Mcp-Param-Action: create
Mcp-Param-Apm-Id: APM12345
Mcp-Param-Environment: dev

{
  "jsonrpc": "2.0",
  "id": "val-1",
  "method": "tools/call",
  "params": {
    "name": "spp_validate_request",
    "arguments": {
      "idempotency_key": "mcp-val-20261021-001",
      "kind": "gcs_bucket",
      "action": "create",
      "metadata": {
        "apm_id": "APM12345",
        "project_id": "retail-nonprod-orders-svc",
        "environment": "dev",
        "lob": "retail",
        "data_sensitivity": "restrict",
        "data_classification": "proprietary",
        "owner": "bucket.owner@example.com",
        "shared_mailbox": "retail-orders-team@example.com",
        "cost_center": "000000",
        "tenancy": "dedicated",
        "labels": { "app": "orders" }
      },
      "spec": {
        "purpose_token": "landing",
        "purpose": "Landing zone for order events",
        "location": "us-east1",
        "storage_class": "STANDARD",
        "versioning": false,
        "lifecycle_rules": [],
        "access": [
          {
            "role": "roles/storage.objectViewer",
            "members": ["group:gcp-retail-nonprod-orders-read@example.com"]
          }
        ]
      }
    },
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientInfo": {
        "name": "Cursor",
        "version": "2.0.0"
      },
      "io.modelcontextprotocol/clientCapabilities": {
        "elicitation": { "form": {}, "url": {} },
        "extensions": { "io.modelcontextprotocol/tasks": {} }
      },
      "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    }
  }
}
```

**HTTP Response (`resultType: "complete"`, `structuredContent` + `TextContent`):**
```json
{
  "jsonrpc": "2.0",
  "id": "val-1",
  "result": {
    "resultType": "complete",
    "content": [
      {
        "type": "text",
        "text": "{\"workflow_id\":\"wf-val-8a4f19c20d3e71b4a901\",\"decision\":\"allow_with_mutations\",\"preview_sha256\":\"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"}"
      }
    ],
    "structuredContent": {
      "workflow_id": "wf-val-8a4f19c20d3e71b4a901",
      "temporal_namespace": "platform",
      "task_queue": "spp-agent-actions",
      "decision": "allow_with_mutations",
      "violations": [],
      "normalized_requested_spec": {
        "api_version": "idp.spp/v1",
        "kind": "gcs_bucket",
        "action": "create",
        "metadata": {
          "apm_id": "apm12345",
          "project_id": "retail-nonprod-orders-svc",
          "environment": "nonprod",
          "lob": "retail",
          "data_sensitivity": "restricted",
          "data_classification": "proprietary",
          "owner": "bucket.owner@example.com",
          "shared_mailbox": "retail-orders-team@example.com",
          "requested_by": "requester@example.com",
          "cost_center": "000000",
          "tenancy": "dedicated",
          "labels": { "app": "orders" }
        },
        "spec": {
          "name": "retail-nonprod-orders-landing-a1b2",
          "location": "us-east1",
          "storage_class": "STANDARD",
          "versioning": false,
          "lifecycle_rules": [],
          "access": [
            {
              "role": "roles/storage.objectViewer",
              "members": ["group:gcp-retail-nonprod-orders-read@example.com"]
            }
          ],
          "purpose": "Landing zone for order events"
        }
      },
      "computed_labels": {
        "app": "orders",
        "costcenter": "000000",
        "dataclassification": "proprietary",
        "datasensitivity": "restricted",
        "environmenttype": "nonprod",
        "idp_resource_id": "<assigned-on-submit>",
        "owner": "bucket_owner_example_com",
        "primarylob": "retail",
        "provisionedby": "idp",
        "sharedemailaddress": "retail-orders-team_example_com",
        "sppappid": "apm12345",
        "tenancy": "dedicated"
      },
      "resolved_kms_key": "projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek",
      "guardrail_trace_preview": [
        {"rule_id": "GCS-UBLA-001", "path": "/spec/uniform_bucket_level_access", "from": null, "to": true},
        {"rule_id": "GCS-PAP-001", "path": "/spec/public_access_prevention", "from": null, "to": "enforced"},
        {"rule_id": "GCS-ENC-001", "path": "/spec/kms_key_name", "from": null, "to": "projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek"},
        {"rule_id": "GCS-RET-001", "path": "/spec/retention_days", "from": null, "to": 90},
        {"rule_id": "GCS-RET-003", "path": "/spec/retention_locked", "from": null, "to": false},
        {"rule_id": "GCS-SDP-001", "path": "/spec/soft_delete_retention_days", "from": null, "to": 7},
        {"rule_id": "GCS-DEL-001", "path": "/spec/force_destroy", "from": null, "to": false},
        {"rule_id": "LBL-001", "path": "/metadata/labels", "from": {"app": "orders"}, "to": "(12 normalized labels, no environmentsubtype)"},
        {"rule_id": "PRQ-001", "path": "/prerequisites/0", "from": null, "to": "ad_group"},
        {"rule_id": "PRQ-002", "path": "/prerequisites/1", "from": null, "to": "vpc_sc_ingress"}
      ],
      "approval_gate_required": {
        "gate_key": "gcs_bucket_owner",
        "gate_version": 1,
        "approver_key": "bucket_owner",
        "approver_identity": "bucket.owner@example.com",
        "self_approval": "deny"
      },
      "preview_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    },
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "spp-mcp",
        "version": "1.0.0"
      }
    }
  }
}
```

---

## 8. Approval & No-Delete Rules (`ADR-BP-003`, `ADR-GLB-007`)

- **Approvals Remain 100% Human:** `spp-mcp` does not expose an autonomous approval-writing tool (`POST /api/v1/approvals/{approval_id}/decisions`). When a task in `io.modelcontextprotocol/tasks` waits on `gcs_bucket_owner`, it surfaces a **URL mode elicitation** (`mode: "url"`, `url: "https://portal.taxi.growripple.ai/approvals/<approval_id>"`) so the human `bucket_owner` signs in and approves out-of-band (`self_approval = "deny"`).
- **No Delete or Replace Without Explicit Human Approval in ANY Environment:**
  - Submitting `action = "delete"` via `spp_submit_request` triggers an MRTR `elicitation/create` prompt requiring the user to type the exact bucket name to confirm submitting the delete request, and creates a `PENDING` approval row in `idp.approval`.
  - `AUTO_APPROVED` / `auto_approved` is strictly rejected for `action = "delete"` and for any plan with `destroy > 0` or `replace > 0` across both `nonprod` and `prod`.
  - `force_destroy` is locked to `false` (`GCS-DEL-001`), and `retention_locked` is locked to `false` (`GCS-RET-003`).

---

## 9. Observability & Audit

- **W3C Trace Context in `_meta` (`SEP-414`):** `spp-mcp` extracts `traceparent`, `tracestate`, and `baggage` from `_meta` on every JSON-RPC request and forwards them to `ssp-cp` and OpenTelemetry collector spans.
- **Mirrored Header Inspection (`SEP-2243`):** GKE ingress / gateways and audit middleware can inspect `MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`, `Mcp-Param-Kind`, `Mcp-Param-Action`, `Mcp-Param-Apm-Id`, and `Mcp-Param-Environment` without parsing the JSON body, while `spp-mcp` enforces body equality (`-32020 HeaderMismatch` on mismatch).
- **Control-Plane Audit Trail:** `ssp-cp` records `actor_username`, `actor_role`, `source_ip`, and `source_ref = "mcp:2026-07-28:<tool_name>:<client_name>"` in `idp.cp_audit_log` and `idp.submission`, queryable via `GET /api/v1/audit`.

---

## 10. MVP Scope vs. Later Phases

| Area | MVP Scope (GCS Bucket First Slice — MCP `2026-07-28`) | Later Phases |
| :--- | :--- | :--- |
| **Protocol & SDK** | **MCP `2026-07-28`** implemented with official Python SDK **`mcp == 2.3.0`** (`httpx2 >= 2.10.0`), supporting stateless **Streamable HTTP (`POST /mcp`)** and local `stdio` | TypeScript MCP client/host helpers (`@modelcontextprotocol/sdk >= 2.3.1`) in `ssp-ui` / CLI |
| **Authorization** | OAuth 2.1 Resource Server (`RFC 9728` Protected Resource Metadata, `RFC 8707` audience-bound tokens, `spp:*` scopes) for Streamable HTTP; Argon2id session login for local `stdio` | Enterprise IdP Client ID Metadata Document federation across all LOBs |
| **Resource Kinds** | `gcs_bucket` (`us-east1`, `nonprod`/`prod`) | `spanner_instance`, `spanner_database` (`ADR-SVC-002`), GCE VM, BigQuery dataset |
| **MCP Capabilities** | `server/discover`, **Tools** (7 tools with `outputSchema`, `structuredContent`, `ToolAnnotations`, `x-mcp-header`), **MRTR Elicitation** (`form` & `url`), and **`io.modelcontextprotocol/tasks`** mapped to Temporal workflows | **Resources** (`spp://schemas/gcs_bucket`, `spp://adrs/ADR-SVC-001`), `subscriptions/listen` push streams, and **Skills over MCP** |

---

## 11. Open Questions

- [ ] **OQ-EXP-MCP-1 (OAuth 2.1 Authorization Server Endpoint for Streamable HTTP — [Owner: Manoj / Raju]):** Confirm whether `ssp-cp` itself hosts the OAuth 2.1 Authorization Server endpoints (`/.well-known/oauth-authorization-server`) in `<spp-factory-host-project-id>` or delegates directly to the corporate OIDC IdP while `spp-mcp` serves `/.well-known/oauth-protected-resource`.
- [ ] **OQ-EXP-MCP-2 (Backward-Compatibility Shim for `2025-11-25` MCP Clients — [Owner: Manoj / Dwayne]):** Confirm whether `spp-mcp` (`mcp v2.3.0`) should accept legacy `2025-11-25` `initialize`-handshake clients in `mode="auto"` during transition or strictly require `MCP-Protocol-Version: 2026-07-28`.
