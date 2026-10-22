# SPP Experience Lines (`experiences/`)

This directory defines the user- and automation-facing **experience lines** for the **Self-Service Provisioning Platform (SPP)** on **Google Cloud Platform (GCP)** (`us-east1`, environments `nonprod` and `prod` only). Every experience line starts with the **first vertical slice: Google Cloud Storage Bucket (`kind = "gcs_bucket"`, `ADR-SVC-001`)**.

---

## 1. Shared Architectural Principle: One Control Plane, Zero Privileged Channels

Across SPP, **every channel is a thin client over the same `ssp-cp` FastAPI Control Plane API, the same deterministic Temporal workflows on namespace `platform`, the same OPA/Rego policy gates (`requested`, `approved`, `plan`), and the same human approval gate (`gcs_bucket_owner` v1)**:

1. **No Privileged or Backdoor Path:** Neither the Portal UI (`ssp-ui`), the Agentic Chatbot ("Jev model" assistant), the MCP Server, nor the Client SDK ever connects directly to AlloyDB (`spp_platform`), the OPA sidecar (`http://spp-opa.spp-policy.svc.cluster.local:8181`), the Temporal frontend (`temporal-frontend.spp-temporal.svc.cluster.local:7233`), or the GCS state bucket (`gs://microdrive-dev-spp-tfstate`).
2. **Deterministic Temporal Execution Layer (`ADR-AUT-004`):** Agents and MCP tools never perform side effects directly. The LLM / agent emits **intent + typed parameters only**; every action (`validate`, `submit`, `status`, `plan retrieval`, `approval requests`) is executed as a deterministic Temporal workflow on Temporal namespace `platform` (with existing GCS provisioning on task queue `spp-gcs-provisioning` via `GcsBucketProvisionWorkflow` and agent-facing orchestration proposed on task queue `spp-agent-actions`) invoked through the `ssp-cp` REST API with explicit `idempotency_key`s, returning deterministic `workflow_id`s to the conversation and supporting Temporal queries/signals for status.
3. **Caller Identity Propagation:** Every channel authenticates as the human or authorized service principal (`ADR-GLB-005`) and propagates the caller's identity (`requested_by`, `submitted_by`, `on_behalf_of`) and `channel` (`ui`, `chat`, `api`) into `idp.submission`, `idp.gate_event`, and `idp.cp_audit_log`.
4. **Identical GCS Bucket Schema & Guardrails (`ADR-SVC-001`, `ADR-GLB-006..008`):**
   - **APM ID:** Matches `(?i)^APM\d{5}$` on intake (e.g., `APM12345`) and normalizes to lowercase `^apm\d{5}$` (`apm12345`) in `metadata.apm_id` and the `sppappid` label (`NAM-APM-001`).
   - **Environment:** Normalizes legacy codes (`sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod`) to `nonprod` (no hyphen) or `prod` (`GLB-ENV-001`); `environmentsubtype` is dropped and forbidden everywhere.
   - **8 Mandatory Labels (`LBL-001` & `LBL-002`):** `sppappid`, `costcenter`, `environmenttype` (`nonprod` | `prod`), `primarylob`, `datasensitivity`, `owner`, `provisionedby` (`"idp"`), and `idp_resource_id` (plus metadata-derived `dataclassification`, `sharedemailaddress`, `tenancy`).
   - **CMEK Key (`GCS-ENC-001`):** `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek` in `us-east1` (`location = "us-east1"` only).
   - **Guardrail Trace (`stage = 'approved'`):** `GCS-UBLA-001` (`true`), `GCS-PAP-001` (`"enforced"`), `GCS-ENC-001`, `GCS-RET-001` (`90` days), `GCS-RET-003` (`retention_locked = false`), `GCS-SDP-001` (`7` days), `GCS-DEL-001` (`force_destroy = false`), `LBL-001`, `PRQ-001` (`ad_group`), and `PRQ-002` (`vpc_sc_ingress`).
5. **Non-Bypassable Human Approvals & Universal No-Delete Rule (`ADR-BP-003`, `ADR-GLB-007`):**
   - Every `gcs_bucket` request requires human approval via `gcs_bucket_owner` v1 (`bucket_owner` resolved from `/metadata/owner`).
   - Self-approval is strictly denied (`self_approval = "deny"`).
   - No deletion (`action = "delete"`), destroy, or replacement (`destroy > 0` or `replace > 0`) may ever be auto-approved (`AUTO_APPROVED` / `auto_approved` is forbidden) in **any** environment (`nonprod` or `prod`).

---

## 2. Experience Lines Matrix

| Experience Line | Folder | Governing ADR(s) | Submission `channel` | Primary Persona(s) | First Feature Covered | Summary |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Portal UI Experience** *(existing baseline)* | [`../10-product/16-ui-spec.md`](../10-product/16-ui-spec.md) (`ssp-ui`, `WI-006`) | [`ADR-GLB-002`](../adr/global/ADR-GLB-002-languages-and-technology-stack.md), [`ADR-BP-002`](../adr/business-process/ADR-BP-002-build-order-and-phasing.md) | `ui` | Developer (`requester`), `bucket_owner`, `approver`, `operations` | `gcs_bucket` (`ADR-SVC-001`) | Template-driven React + TypeScript storefront form -> `ssp-cp` FastAPI API -> OPA intake policy -> human approval -> Temporal workflow -> Terraform plan -> apply gate. |
| **1. Agentic Chatbot Experience ("Jev Model" Assistant)** | [`agentic-chat/`](agentic-chat/) ([`README.md`](agentic-chat/README.md), [`agent-harness.md`](agentic-chat/agent-harness.md)) | [`ADR-EXP-001`](../adr/experience/ADR-EXP-001-agentic-chatbot-experience.md), [`ADR-AUT-004`](../adr/automation/ADR-AUT-004-agent-harness-and-temporal-workflow-execution.md) | `chat` | Developer (`requester`), `bucket_owner`, `approver` | `gcs_bucket` (`ADR-SVC-001`) | Conversational agent governed by the **Jev model Agent Harness**: gathers GCS bucket parameters via chat, outputs strictly intent + typed parameters, invokes deterministic Temporal workflows (`platform` namespace) via `ssp-cp` on the user's behalf, renders OPA policy results, `guardrail_trace`, and Terraform plan summaries, and enforces human-in-the-loop checkpoints without ever bypassing human approval gates. |
| **2. MCP Server Experience** | [`mcp/`](mcp/) ([`README.md`](mcp/README.md)) | [`ADR-EXP-002`](../adr/experience/ADR-EXP-002-mcp-server-experience.md), [`ADR-AUT-004`](../adr/automation/ADR-AUT-004-agent-harness-and-temporal-workflow-execution.md) | `chat` or `api` (`source_ref = "mcp:<tool>"`) | IDE / CLI AI assistants (Cursor, Claude Code, Gemini CLI) acting for a human developer or approver | `gcs_bucket` (`ADR-SVC-001`) | Model Context Protocol (MCP) server exposing read vs. write separated SPP tools (`spp_list_catalog`, `spp_describe_gcs_bucket_schema`, `spp_validate_request`, `spp_submit_request`, `spp_get_request_status`, `spp_get_request_plan`, `spp_list_approvals`) backed by `ssp-cp` and mapping **1:1** to the same deterministic Temporal workflows on `platform`; approvals remain strictly human. |
| **3. Client SDK Experience** | [`sdk/`](sdk/) ([`README.md`](sdk/README.md)) | [`ADR-EXP-003`](../adr/experience/ADR-EXP-003-client-sdk-experience.md) | `api` (`source_ref = "sdk:python/<ver>"`) | Platform engineers, application automation scripts, CI pipelines, and the Agentic Chat / MCP runtimes | `gcs_bucket` (`ADR-SVC-001`) | Typed **Python** (`spp-sdk`, Pydantic v2 + `httpx`, sync/async) client SDK over the `ssp-cp` REST API (with **TypeScript** `@spp/sdk` noted for Phase 5 alongside `ssp-ui`), providing auth/CSRF handling, client-side pre-validation of `GcsBucketRequest`, idempotent submit/status/wait helpers, Temporal `workflow_id` tracking, and RFC 9457 / structured rule error handling. |

---

## 3. Unified Architecture Across All Four Experience Lines

```mermaid
flowchart TB
    subgraph Channels["SPP Experience Lines (Zero Privileged Paths)"]
        UI["Portal UI (ssp-ui)\nchannel = 'ui'"]
        Chat["1. Agentic Chatbot ('Jev Model' Harness)\nexperiences/agentic-chat/\nchannel = 'chat'"]
        MCP["2. MCP Server (spp-mcp)\nexperiences/mcp/\n1:1 Tool-to-Workflow Mapping"]
        SDK["3. Client SDK (Python spp-sdk / TS later)\nexperiences/sdk/\nchannel = 'api'"]
    end

    subgraph CP["Control Plane API (ssp-cp FastAPI in K8s ns spp-platform)"]
        Auth["Auth & RBAC Middleware\nArgon2id Session + X-CSRF-Token\n(Future: OIDC/SSO Bearer JWT)"]
        Endpoints["Real ssp-cp Endpoints (/api/v1/*)\n+ Proposed Agent/Dry-Run Workflow Endpoints"]
        OPA["OPA Policy Service (ns spp-policy :8181)\nidp.common, idp.naming, idp.labels,\nidp.gcp.gcs_bucket"]
        DB[("AlloyDB for PostgreSQL (spp_platform)\nSchema idp (18 tables + v_resource_status)\nZero Secrets (INV-1)")]
    end

    subgraph Temporal["Temporal Cluster (ns spp-temporal, Temporal namespace: platform)"]
        AgentTQ["Proposed Task Queue: spp-agent-actions\nAgentValidateRequestWorkflow (wf-val-*)\nAgentSubmitRequestWorkflow (wf-sub-*)\nAgentGetStatusWorkflow / Queries\nAgentApprovalRequestWorkflow (wf-apr-req-*)"]
        GcsTQ["Existing Task Queue: spp-gcs-provisioning\nGcsBucketProvisionWorkflow (req-<request_id>)\nApprovalGateWorkflow (apr-<request_id>)\nStateUnitReconcilerWorkflow (su-gcp-<project_id>)"]
    end

    subgraph Execution["Isolated Runner & State (K8s ns spp-platform / us-east1)"]
        Jobs["Deterministic K8s Jobs\ntf-plan-<20hex> / tf-apply-<20hex>\n(Workload Identity -> Per-Project SA)"]
        GCS[("Single State Bucket\ngs://microdrive-dev-spp-tfstate\nprojects/<project_id>/{expected,observed,logs}")]
    end

    UI --> Auth
    Chat --> SDK
    MCP --> SDK
    SDK --> Auth
    Chat --> Auth
    MCP --> Auth

    Auth --> Endpoints
    Endpoints --> OPA
    Endpoints --> DB
    Endpoints --> AgentTQ
    Endpoints --> GcsTQ
    AgentTQ --> GcsTQ
    GcsTQ --> Jobs
    Jobs --> GCS
```
