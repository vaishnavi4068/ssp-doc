# ADR-AUT-004: Agent Harness ("Jev Model") and Deterministic Temporal Workflow Execution Layer

- **ADR ID:** ADR-AUT-004
- **Level:** automation
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-automation@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the **Agent Harness ("Jev Model" conversational assistant experience)** and its **deterministic Temporal workflow execution layer** on Temporal namespace `platform` so that neither the conversational agent (`experiences/agentic-chat/`) nor the MCP server (`experiences/mcp/`) ever performs side effects directly: the LLM emits **only structured intent and typed parameters**, and every action (`validate`, `submit`, `status`, `plan retrieval`, `approval requests`) is invoked as a deterministic Temporal workflow via the `ssp-cp` FastAPI API with idempotency keys, `workflow_id`s returned to the conversation, and Temporal signals/queries for status and human-in-the-loop (HITL) checkpoints.

## Context

From the SPP design decisions (`ADR-GLB-001..009`, `ADR-BP-001..003`, `ADR-SVC-001`, `ADR-AUT-001..003`), the `ssp-cp` implementation (`app/main.py`, `app/services.py`, `app/temporal_bridge.py`, `app/config.py`), and the user's experience-line requirements:

1. **Why an Explicit Agent Harness Is Required:**
   - Conversational LLMs are non-deterministic text generators. Allowing an LLM to directly execute database writes, bypass OPA policy stages, or trigger cloud provisioning introduces hallucinated parameters, prompt-injection vulnerabilities, and un-audited state changes.
   - The user specified a **"Jev model"**-like assistant experience (treated as the user's name for the conversational assistant experience and tracked in `OQ-1` below to formalize the exact model/persona definition) governed by a strict **Agent Harness** ([`experiences/agentic-chat/agent-harness.md`](../../experiences/agentic-chat/agent-harness.md)) covering: system prompt/role, tool registry, context/memory, session state, guardrails, evaluation suite and replay tests, tracing/observability, and human-in-the-loop checkpoints.
2. **HARD RULE — Zero Direct Side Effects from the Agent:**
   - The agent never performs side effects directly.
   - Every action (`validate`, `submit`, `status`, `plan retrieval`, `approval requests`) is invoked as a deterministic Temporal workflow on Temporal namespace **`platform`** via the `ssp-cp` API, carrying an explicit `idempotency_key`, returning the deterministic `workflow_id` to the conversation, and using Temporal signals/queries for status.
   - In `vaishnavi4068/ssp-cp` (`app/config.py`), the existing GCS provisioning workflow is **`GcsBucketProvisionWorkflow`** (workflow ID `req-<request_id>`) running on Temporal namespace **`platform`** (`temporal-frontend.spp-temporal.svc.cluster.local:7233`) and task queue **`spp-gcs-provisioning`**.
   - To keep sub-second interactive agent actions (dry-run validation, status queries, plan inspection) isolated from long-running Kubernetes Job polling on `spp-gcs-provisioning`, this ADR proposes a dedicated agent-facing Temporal task queue **`spp-agent-actions`** in the same `platform` namespace while preserving `spp-gcs-provisioning` for `GcsBucketProvisionWorkflow`, `ApprovalGateWorkflow` (`apr-<request_id>`), and `StateUnitReconcilerWorkflow` (`su-gcp-<project_id>`).
3. **1:1 Parity Between the Agent Harness and MCP Server (`experiences/mcp/`, MCP Specification `2026-07-28`):**
   - The MCP Server (`ADR-EXP-002`, pinned to MCP specification revision **`2026-07-28`** and official Python SDK **`mcp >= 2.3.0`**) exposes the exact same 7-tool registry (`spp_list_catalog`, `spp_describe_gcs_bucket_schema`, `spp_validate_request`, `spp_submit_request`, `spp_get_request_status`, `spp_get_request_plan`, `spp_list_approvals`) mapped **1:1** to the same deterministic Temporal workflows via `ssp-cp`.
   - Under MCP `2026-07-28`, human submission confirmation uses **Multi Round-Trip Request (MRTR) Elicitation** (`resultType: "input_required"`, `elicitation/create`, and AEAD-protected `requestState` per `SEP-2322`), while long-running workflow tracking uses the official **`io.modelcontextprotocol/tasks` extension** (`SEP-2663`, where `taskId = "req-<request_id>"`, `tasks/get` maps to Temporal `@workflow.query`, `tasks/update` maps to `@workflow.signal`, and `tasks/cancel` maps to the Temporal `cancel` signal).

## Decision

### 1. The Eight Pillars of the Jev Model Agent Harness

| Pillar | Specification in `experiences/agentic-chat/agent-harness.md` |
| :--- | :--- |
| **1. System Prompt & Role** | Locked system prompt restricting the model to **intent + typed parameters (`IntentEnvelope`)** for `gcs_bucket` in `us-east1` (`nonprod`\|`prod`), enforcing `(?i)^APM\d{5}$` -> `^apm\d{5}$`, the **8 mandatory labels** (`LBL-001`, no `environmentsubtype`), CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek` (`GCS-ENC-001`), and untrusted-input rules. |
| **2. Tool Registry (1:1 with MCP)** | Closed tool catalog (`spp_list_catalog`, `spp_describe_gcs_bucket_schema`, `spp_validate_request`, `spp_submit_request`, `spp_get_request_status`, `spp_get_request_plan`, `spp_list_approvals`, plus HITL-gated `spp_submit_approval_decision`). No ad-hoc shell, SQL, or HTTP tools exist. |
| **3. Context & Memory** | Assembled deterministically per turn from `GET /api/v1/me` (caller identity & role), active session slot state, active Temporal `workflow_id` receipts, and read-only RAG snippets from `ssp-doc` ADRs and `specs/`. |
| **4. Session State Machine** | Explicit state machine (`IDLE -> SLOT_FILLING -> VALIDATING -> AWAITING_SUBMIT_CONFIRMATION -> SUBMITTED_PENDING_APPROVAL -> APPROVED_PROVISIONING -> OBSERVED_COMPLETE`) persisted in AlloyDB (`spp_platform`) with zero secrets (`INV-1`). |
| **5. Mechanical Guardrails** | Pre-LLM and post-LLM `scan_for_secrets()` (`INV-1`), intake normalization (`app/naming.py`), OPA `stage = 'requested'` and dry-run `stage = 'approved'` verification, `preview_sha256` hash binding (any slot edit invalidates the preview), `self_approval = "deny"`, and universal prohibition on `AUTO_APPROVED` deletes. |
| **6. Human-in-the-Loop (HITL) Checkpoints** | **Checkpoint 1 (Submission):** Requires single-use human `confirmation_token` bound to `preview_sha256` before `spp_submit_request` can execute. **Checkpoint 2 (Approval):** Requires a distinct human approver (`bucket_owner` / `approver` role) to confirm `spp_submit_approval_decision` (`self_approval = "deny"`, no auto-approved deletes in `nonprod` or `prod`). |
| **7. Evaluation Suite & Replay Tests** | Three automated eval suites (`eval_slot_filling.py`, `eval_redteam.py`, `eval_groundedness.py`) plus `temporalio.worker.Replayer` deterministic workflow history replay tests in CI. |
| **8. Tracing & Observability** | OpenTelemetry spans (`jev.chat.turn`) + `idp.cp_audit_log` + `idp.gate_event` recording `session_id`, `turn_id`, `idempotency_key`, `workflow_id`, `request_id`, and `actor_username`. |

### 2. Deterministic Temporal Workflow Mapping (`namespace = "platform"`)

All agent and MCP tools invoke `ssp-cp` endpoints that execute or query deterministic Temporal workflows on `temporal-frontend.spp-temporal.svc.cluster.local:7233` (`namespace = "platform"`):

| Action / Tool | `ssp-cp` Endpoint (`REAL` vs. `PROPOSED`) | Temporal Workflow (`namespace = "platform"`) | Task Queue | Deterministic `workflow_id` | Temporal Signals & Queries |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`validate`** (`spp_validate_request`) | **PROPOSED:** `POST /api/v1/agent/workflows/validate` | `AgentValidateRequestWorkflow` | `spp-agent-actions` *(proposed)* | `wf-val-<sha256(apm_id:idempotency_key)[:20]>` | Query: `get_validation_result` -> normalized `requested_spec`, 8 mandatory labels, 10-entry `guardrail_trace`, `preview_sha256` |
| **`submit`** (`spp_submit_request`) | **REAL:** `POST /api/v1/requests` (`app/main.py:466`) *(wrapped by `AgentSubmitRequestWorkflow`)* | `AgentSubmitRequestWorkflow` -> `RequestWorkflow` (`req-<request_id>`) & `ApprovalGateWorkflow` (`apr-<request_id>`) | `spp-agent-actions` -> `spp-gcs-provisioning` | `wf-sub-<sha256(apm_id:idempotency_key)[:20]>` -> `req-<request_id>` & `apr-<request_id>` | Query: `get_submission_receipt`; Signal on `req-<request_id>`: `cancel` |
| **`status`** (`spp_get_request_status`) | **REAL:** `GET /api/v1/requests/{request_id}` & `GET /api/v1/resources/{resource_id}` (`app/main.py:514, 658`) | `AgentGetStatusWorkflow` / Query on `req-<request_id>` & `su-gcp-<project_id>` | `spp-agent-actions` / `spp-gcs-provisioning` | `wf-sts-<request_id>-<turn_hash[:8]>` | Query: `get_gate_status` (`REQUESTED`, `APPROVED`, `EXPECTED`, `OBSERVED`, `observed.projection`, `open_drift_count`) |
| **`plan retrieval`** (`spp_get_request_plan`) | **REAL:** `GET /api/v1/requests/{request_id}` + **PROPOSED:** `GET /api/v1/requests/{request_id}/plan` | `AgentGetPlanWorkflow` / Query on `su-gcp-<project_id>` | `spp-agent-actions` / `spp-gcs-provisioning` | `wf-pln-<request_id>-<revision_no>` | Query: `get_plan_summary` (`plan_summary` `{add, change, destroy, replace}`, `k8s_job_name = "tf-plan-<20hex>"`, `tf_exit_code`, `logs_uri`) |
| **`approval requests`** (`spp_list_approvals` / `spp_submit_approval_decision`) | **REAL:** `GET /api/v1/approvals` & `POST /api/v1/approvals/{approval_id}/decisions` (`app/main.py:529, 557`) | `ApprovalGateWorkflow` (`apr-<request_id>`) -> starts **`GcsBucketProvisionWorkflow`** (`req-<request_id>`) | `spp-gcs-provisioning` *(existing in `ssp-cp`)* | `apr-<request_id>` -> `req-<request_id>` -> `su-gcp-<project_id>` | Query: `get_pending_decisions`; Signal: `approval_response {decision_id, status, responded_by, comment}`; Signal-with-start: `approval_ready {approval_id}` |

## Requirements

- **REQ-1 (MUST):** The conversational agent ("Jev model") and MCP server MUST NOT perform side effects directly; the LLM output MUST be constrained strictly to structured intent and typed parameters (`IntentEnvelope`), while all actions (`validate`, `submit`, `status`, `plan retrieval`, `approval requests`) execute as deterministic Temporal workflows on namespace `platform` via the `ssp-cp` API.
- **REQ-2 (MUST):** Every workflow-backed tool invocation MUST pass a deterministic `idempotency_key` to `ssp-cp` and return the resulting Temporal `workflow_id` (and `request_id` / `approval_id` where applicable) to the conversation state.
- **REQ-3 (MUST):** `AgentValidateRequestWorkflow` (`spp_validate_request`) MUST enforce the exact `ssp-cp` GCS bucket normalization and OPA rules (`(?i)^APM\d{5}$` -> `^apm\d{5}$`, `nonprod`\|`prod` with `environmentsubtype` forbidden, `location = "us-east1"`, 8 mandatory labels per `LBL-001`, CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek` per `GCS-ENC-001`, and the 10-entry `guardrail_trace`) and return a canonical `preview_sha256`.
- **REQ-4 (MUST):** `AgentSubmitRequestWorkflow` (`spp_submit_request`) MUST reject any submission that lacks a valid, un-expired human `confirmation_token` bound to the latest `preview_sha256`.
- **REQ-5 (MUST):** Human approval gates (`gcs_bucket_owner` v1, `self_approval = "deny"`, and mandatory human approval for all `delete` requests or plans with `destroy > 0` or `replace > 0` in `nonprod` and `prod`) MUST be enforced identically on all agent- and MCP-initiated requests before `GcsBucketProvisionWorkflow` (`req-<request_id>`) starts on task queue `spp-gcs-provisioning`.
- **REQ-6 (MUST):** The MCP server tool registry (`ADR-EXP-002`, pinned to MCP specification revision **`2026-07-28`** / Python SDK **`mcp >= 2.3.0`**) MUST map 1:1 to the same deterministic Temporal workflows defined in this ADR, mapping MCP `io.modelcontextprotocol/tasks` handles (`taskId`, `tasks/get`, `tasks/update`, `tasks/cancel`) directly to Temporal `workflow_id`s, queries, and signals on namespace `platform`.
- **REQ-7 (SHOULD):** Short-lived interactive agent workflows (`validate`, `status`, `plan retrieval`) SHOULD run on a dedicated Temporal task queue `spp-agent-actions` in namespace `platform` so they are never queued behind long-running Terraform runner polling on `spp-gcs-provisioning`.

## Guardrails

- **GR-1:** Never allow the LLM or agent harness to write directly to AlloyDB (`spp_platform`), GCS (`gs://microdrive-dev-spp-tfstate`), Kubernetes APIs, or Temporal without going through `ssp-cp` authenticated as the human caller.
- **GR-2:** Never execute a state-changing workflow (`submit`, `approval decision`) without an explicit human-in-the-loop confirmation token bound to `preview_sha256`.
- **GR-3:** Never allow `self_approval` or `AUTO_APPROVED` / `auto_approved` on any `delete` request or destructive plan in `nonprod` or `prod`.
- **GR-4 (`INV-1`):** Never allow secrets or service account private keys in user prompts, session state, Temporal workflow inputs/histories, or tool outputs.

## Consequences

### Positive

- Complete separation between probabilistic natural-language understanding (Jev model intent/slot extraction) and deterministic execution (Temporal workflows + `ssp-cp` + OPA).
- Every chat turn and MCP tool call produces a verifiable Temporal `workflow_id` and `idempotency_key`, enabling deterministic replay testing (`temporalio.worker.Replayer`) and full auditability.
- 1:1 workflow reuse across `experiences/agentic-chat/` and `experiences/mcp/` eliminates duplicated business logic.

### Negative / Trade-offs

- Adds lightweight Temporal workflow hops (`spp-agent-actions`) for interactive validation and plan inspection; keeping these on a dedicated task queue (`spp-agent-actions`) ensures sub-second latency.

## Acceptance Criteria

- [ ] [`experiences/agentic-chat/agent-harness.md`](../../experiences/agentic-chat/agent-harness.md) documents the Jev model Agent Harness (system prompt, tool registry, context/memory, session state machine, guardrails, HITL checkpoints, eval/replay suites, and tracing).
- [ ] All 7/8 tools in `experiences/agentic-chat/` and `experiences/mcp/` map 1:1 to deterministic Temporal workflows on namespace `platform` (`spp-agent-actions` and `spp-gcs-provisioning`) via `ssp-cp`.
- [ ] Evaluation and Temporal replay test specifications cover slot normalization, `preview_sha256` binding, prompt-injection red-teaming, `self_approval = "deny"`, and no-delete auto-approval.

## Success Criteria

- **SC-1:**
  - **Given** a user asking the Jev model chatbot to create a `gcs_bucket` for `APM12345` in `dev` (`retail-nonprod-orders-svc`)
  - **When** the harness completes slot extraction and invokes `spp_validate_request`
  - **Then** the LLM emits only `IntentEnvelope` JSON (zero direct side effects), `ssp-cp` executes `AgentValidateRequestWorkflow` (`wf-val-*` on namespace `platform`), and the conversation receives `workflow_id`, `preview_sha256`, the 8 mandatory labels (`sppappid = "apm12345"`, `environmenttype = "nonprod"`), and the 10-entry `guardrail_trace` including CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`.
- **SC-2:**
  - **Given** a prompt injection or tool call attempting to invoke `spp_submit_request` without a human `confirmation_token` matching `preview_sha256`, or attempting to self-approve or auto-approve a bucket deletion
  - **When** evaluated by the Jev model Agent Harness and `ssp-cp`
  - **Then** the action is rejected before any state mutation or `GcsBucketProvisionWorkflow` dispatch occurs, and the rejection is logged in `idp.cp_audit_log`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-AUT-004` and [`experiences/agentic-chat/agent-harness.md`](../../experiences/agentic-chat/agent-harness.md) |
| `ssp-cp` | Exposes proposed agent workflow endpoints (`/api/v1/agent/workflows/*`, `/api/v1/requests/{id}/plan`) and dispatches workflows on `platform` |
| `ssp-workers` | Hosts `spp-agent-actions` and `spp-gcs-provisioning` Temporal workers on namespace `platform` |
| `ssp-ui` | Renders Jev model chat cards, `workflow_id` badges, and HITL confirmation buttons (Phase 5) |
| `spp-factory-foundation` | Runs ADR lint, Temporal replay tests, and agent red-team evaluation gates |

## Open Questions

- [ ] **OQ-1 ("Jev Model" Definition & Vertex AI Model Configuration — [Owner: Manoj / Dwayne]):** Confirm the exact definition, origin, and Vertex AI model endpoint/parameters for the **"Jev model"** conversational assistant experience (treated in this ADR as the user's name for the SPP conversational assistant experience).
- [ ] **OQ-2 (Dedicated Task Queue `spp-agent-actions` vs. `spp-gcs-provisioning` — [Owner: Dwayne / Manoj]):** Confirm deploying the dedicated `spp-agent-actions` task queue in Temporal namespace `platform` alongside the existing `spp-gcs-provisioning` task queue (`app/config.py:118`).
- [ ] **OQ-3 (Read-Query Workflows vs. Direct Temporal Queries for `status` and `plan` — [Owner: Manoj]):** Confirm whether `spp_get_request_status` and `spp_get_request_plan` should start short-lived child workflows (`wf-sts-*`, `wf-pln-*`) or issue Temporal `@workflow.query` calls against `req-<request_id>` / `su-gcp-<project_id>` while logging an audit receipt.

## Related ADRs

- [ADR-EXP-001: Agentic Chatbot Experience for Self-Service Provisioning](../experience/ADR-EXP-001-agentic-chatbot-experience.md)
- [ADR-EXP-002: MCP Server Experience for Self-Service Provisioning](../experience/ADR-EXP-002-mcp-server-experience.md)
- [ADR-EXP-003: Client SDK Experience (Python First, TypeScript Later)](../experience/ADR-EXP-003-client-sdk-experience.md)
- [ADR-AUT-001: Temporal Orchestration and Terraform Execution via Deterministic Kubernetes Jobs](ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-AUT-002: Day-2 Operations, Drift Detection, and Deletion Governance](ADR-AUT-002-day-2-operations-scope.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
