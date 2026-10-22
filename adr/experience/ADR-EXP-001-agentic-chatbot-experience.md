# ADR-EXP-001: Agentic Chatbot Experience for Self-Service Provisioning

- **ADR ID:** ADR-EXP-001
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Dwayne (Shared Mailbox: `spp-experience@tbd`, Named Owner: `Dwayne`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the **Agentic Chatbot Experience** (`experiences/agentic-chat/`, `channel = "chat"`) for the Self-Service Provisioning Platform (SPP), starting with the **Google Cloud Storage Bucket (`kind = "gcs_bucket"`, `us-east1`)** vertical slice: a conversational agent governed by the **Jev model Agent Harness** (`ADR-AUT-004`) that gathers bucket request parameters via natural dialogue, validates against the canonical schema (8 mandatory labels, APM ID `(?i)^APM\d{5}$` lowercased to `^apm\d{5}$`, CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`), invokes deterministic Temporal workflows via `ssp-cp` on the user's behalf with their identity, renders OPA policy results (`guardrail_trace`) and Terraform `plan` summaries, and never bypasses human approval gates.

## Context

1. **Expanding Experience Lines Beyond the Portal UI (`ssp-ui`):**
   - Initially, SPP specified only the Portal UI experience (`ssp-ui`, `WI-006`) over the headless `ssp-cp` REST API (`form -> ssp-cp FastAPI API -> OPA intake policy -> human approval -> Temporal workflow -> Terraform plan -> apply gate`).
   - Developers and resource owners also require a conversational assistant (**"Jev model"** assistant experience, documented in [`experiences/agentic-chat/README.md`](../../experiences/agentic-chat/README.md) and [`experiences/agentic-chat/agent-harness.md`](../../experiences/agentic-chat/agent-harness.md)) to draft requests, understand why security guardrails were injected, check status/plans, and review pending approvals.
2. **Shared Principle — Zero Privileged Channels & Zero Direct Side Effects:**
   - The chatbot must never have a privileged backdoor around `ssp-cp`, OPA (`idp.gcp.gcs_bucket`), or `ApprovalGateWorkflow` (`gcs_bucket_owner` v1).
   - Per `ADR-AUT-004`, the LLM inside the chatbot emits **only structured intent and typed parameters (`IntentEnvelope`)**; every action (`validate`, `submit`, `status`, `plan retrieval`, `approval requests`) executes as a deterministic Temporal workflow on Temporal namespace `platform` via `ssp-cp`.

## Decision

1. **Conversational Slot-Filling & Validation for `gcs_bucket` (`ADR-SVC-001`):**
   - The chatbot gathers required `RequestMetadataInput` and `GcsBucketSpecInput` fields (`app/schemas.py` in `ssp-cp`), asking at most 3 clarifying questions per turn.
   - Enforces identical normalization and schema rules (`app/naming.py` and `policy/gcs_bucket.rego` in `ssp-cp`):
     - **APM ID (`NAM-APM-001`):** Matches `(?i)^APM\d{5}$` (e.g., `APM12345`) and normalizes to lowercase `^apm\d{5}$` (`apm12345`) in `metadata.apm_id` and the `sppappid` label.
     - **Environment (`GLB-ENV-001`):** Maps `sandbox`, `dev`, `qa`, `test`, `pdev`, `pqa`, `preprod` -> `nonprod` (no hyphen) and `prod` -> `prod`. Drops and rejects `environmentsubtype` everywhere.
     - **Region (`GLB-REG-001`):** Enforces `spec.location == "us-east1"` in both `nonprod` and `prod`.
     - **8 Mandatory Labels (`LBL-001` & `LBL-002`):** `sppappid`, `costcenter`, `environmenttype` (`nonprod`\|`prod`), `primarylob`, `datasensitivity`, `owner` (normalized `@`/`.` -> `_`), `provisionedby` (`"idp"`), and `idp_resource_id` (plus metadata-derived `dataclassification`, `sharedemailaddress`, `tenancy`).
     - **CMEK Key (`GCS-ENC-001`):** Resolves and previews `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`.
     - **Lifecycle Rules (`ADR-SVC-001 REQ-3`):** Default to `[]` (NONE); optional `Delete` (`age_days >= 90`) or `SetStorageClass` rules are validated.
     - **IAM Allowlist (`GCS-IAM-001..002`):** Only `group:` and `serviceAccount:` principals and roles in `{"roles/storage.objectAdmin", "roles/storage.objectViewer", "roles/storage.objectCreator"}`.
2. **Caller Identity & `ssp-cp` API Invocation (`ADR-GLB-005`):**
   - All requests from the chatbot pass the authenticated user's `__Host-spp_cp_session` cookie and `X-CSRF-Token` header (or future SSO Bearer JWT), setting `channel = "chat"`, `submitted_by = <user.email>`, `on_behalf_of = <user.email>`, and `source_ref = "jev-chat:<session_id>:<turn_id>"`.
3. **Policy Result, Plan Display, and Human-in-the-Loop Checkpoints:**
   - Before submission, the chatbot invokes `spp_validate_request` (`AgentValidateRequestWorkflow` `wf-val-*` on namespace `platform`), renders a **Validation & Policy Preview Card** showing the 8 mandatory labels, the 10-entry `guardrail_trace`, the CMEK key URI, the `workflow_id`, and `preview_sha256`, and waits for explicit human confirmation (`confirmation_token`) before calling `POST /api/v1/requests`.
   - After submission and approval, the chatbot retrieves and displays the 4-gate status (`GET /api/v1/requests/{request_id}`, `GET /api/v1/resources/{resource_id}`) and Terraform `plan_summary` (`{add, change, destroy, replace}` from `tf-plan-<20hex>` in `spp-platform`).
4. **Non-Bypassable Human Approval & No-Delete Rule (`ADR-BP-003`, `ADR-GLB-007`):**
   - Requests always enter `PENDING_APPROVAL` under `gcs_bucket_owner` v1 (`bucket_owner`, `self_approval = "deny"`).
   - No deletion (`action = "delete"`), destroy, or replacement (`destroy > 0` or `replace > 0`) may ever be auto-approved (`AUTO_APPROVED` / `auto_approved`) in `nonprod` or `prod`.

## Requirements

- **REQ-1 (MUST):** The Agentic Chatbot Experience MUST submit and query all provisioning requests exclusively through the `ssp-cp` FastAPI API using `channel = "chat"` and the authenticated caller's identity (`ADR-GLB-005`), never bypassing `ssp-cp`, OPA, or `ApprovalGateWorkflow`.
- **REQ-2 (MUST):** For `gcs_bucket` requests, the chatbot MUST validate and preview all 8 mandatory labels (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id` with `environmentsubtype` forbidden), APM ID normalization (`(?i)^APM\d{5}$` -> `^apm\d{5}$`), `location = "us-east1"`, and CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`.
- **REQ-3 (MUST):** Every action invoked by the chatbot (`validate`, `submit`, `status`, `plan retrieval`, `approval requests`) MUST execute as a deterministic Temporal workflow on namespace `platform` via `ssp-cp` (`ADR-AUT-004`), returning the `workflow_id` to the conversation.
- **REQ-4 (MUST):** The chatbot MUST require an explicit human confirmation action bound to `preview_sha256` before invoking `POST /api/v1/requests`, and MUST enforce `self_approval = "deny"` and mandatory human approval on all deletes in `nonprod` and `prod`.
- **REQ-5 (SHOULD):** The chatbot SHOULD ask at most 3 clarifying questions per turn when required `gcs_bucket` slots are missing, while displaying auto-derived values and their `ADR-*` / `GCS-*` rule reasons.

## Guardrails

- **GR-1:** Never grant the chatbot its own privileged service account to submit or approve requests in `ssp-cp`; always act with the human user's session and role.
- **GR-2:** Never allow `POST /api/v1/requests` to be called from chat without a prior passing validation workflow (`preview_sha256`) and explicit human confirmation.
- **GR-3:** Never bypass `gcs_bucket_owner` v1 human approval, `self_approval = "deny"`, or human approval for `action = "delete"` in any environment (`nonprod` or `prod`).
- **GR-4 (`INV-1`):** Never accept, log, or store secret values or GCP service account JSON keys in chat messages or session state.

## Consequences

### Positive

- Gives developers a guided conversational path to create compliant GCS buckets in `us-east1` while preserving 100% of SPP's schema, OPA, and human approval invariants.
- Makes invisible security injections (`guardrail_trace`, CMEK key, 90-day retention, 7-day soft delete, 8 mandatory labels) explicit and understandable before submission.

### Negative / Trade-offs

- Requires maintaining golden conversational evaluation and red-team suites (`experiences/agentic-chat/agent-harness.md` §7) alongside `ssp-cp` schema updates.

## Acceptance Criteria

- [ ] [`experiences/agentic-chat/README.md`](../../experiences/agentic-chat/README.md) and [`experiences/agentic-chat/agent-harness.md`](../../experiences/agentic-chat/agent-harness.md) are committed in `ssp-doc` covering purpose, user journeys, mermaid architecture, real vs. proposed `ssp-cp` API mapping, security/identity, approval/no-delete rules, observability/audit, MVP vs. later scope, and open questions.
- [ ] All chat-initiated requests use the exact `ssp-cp` GCS bucket schema, 8 mandatory labels, `(?i)^APM\d{5}$` -> `^apm\d{5}$` normalization, and CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`.

## Success Criteria

- **SC-1:**
  - **Given** a developer requesting a GCS bucket in chat with `apm_id = "APM12345"`, `environment = "dev"`, `lob = "retail"`, and `owner = "bucket.owner@example.com"`
  - **When** the chatbot runs validation (`AgentValidateRequestWorkflow`) and the developer confirms submission
  - **Then** `ssp-cp` records `idp.submission` (`channel = "chat"`, `apm_id = "apm12345"`), `idp.request` (`status = "PENDING_APPROVAL"`, `location = "us-east1"`), and `idp.approval` (`status = "PENDING"`, `gate_key = "gcs_bucket_owner"`), and returns `request_id`, `approval_id`, `req-<request_id>`, and `apr-<request_id>` to the chat.
- **SC-2:**
  - **Given** the same developer attempting to approve their own bucket request in chat, or attempting to auto-approve a bucket deletion (`action = "delete"`) in `nonprod`
  - **When** the request reaches the harness and `ssp-cp` (`POST /api/v1/approvals/{approval_id}/decisions`)
  - **Then** `ssp-cp` rejects the call with `403 Forbidden` citing `self_approval = "deny"` or the universal human-approval rule for deletes (`ADR-BP-003`).

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-EXP-001`, [`experiences/agentic-chat/README.md`](../../experiences/agentic-chat/README.md), and [`experiences/agentic-chat/agent-harness.md`](../../experiences/agentic-chat/agent-harness.md) |
| `ssp-cp` | Implements `channel = "chat"` intake, proposed `/api/v1/agent/workflows/validate` and `/api/v1/requests/{id}/plan` endpoints, and Jev model harness turn orchestration |
| `ssp-workers` | Executes `spp-agent-actions` and `spp-gcs-provisioning` (`GcsBucketProvisionWorkflow`) workflows on Temporal namespace `platform` |
| `ssp-ui` | Embeds the conversational chat drawer and confirmation cards in Phase 5 (`ADR-BP-002`, `WI-006`) |
| `spp-factory-foundation` | Validates `ADR-EXP-001` via `lint_adrs.py` and runs conversational eval/red-team gates |

## Open Questions

- [ ] **OQ-1 ("Jev Model" Assistant Naming & Vertex AI Model Selection — [Owner: Manoj / Dwayne]):** Formalize the definition of the **"Jev model"** assistant experience and confirm the approved Vertex AI model endpoint in `microdrive-dev` (`us-east1`).
- [ ] **OQ-2 (Proposed Dry-Run Validate & Plan Endpoints in `ssp-cp` — [Owner: Manoj / Norm]):** Confirm adding `POST /api/v1/agent/workflows/validate` (or `POST /api/v1/requests/validate`) and `GET /api/v1/requests/{request_id}/plan` to `ssp-cp` (`app/main.py`) to complement the existing `/api/v1/requests`, `/api/v1/approvals`, `/api/v1/resources`, and `/api/v1/audit` routes.

## Related ADRs

- [ADR-AUT-004: Agent Harness ("Jev Model") and Deterministic Temporal Workflow Execution Layer](../automation/ADR-AUT-004-agent-harness-and-temporal-workflow-execution.md)
- [ADR-EXP-002: MCP Server Experience for Self-Service Provisioning](ADR-EXP-002-mcp-server-experience.md)
- [ADR-EXP-003: Client SDK Experience (Python First, TypeScript Later)](ADR-EXP-003-client-sdk-experience.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-GLB-006: Naming Conventions and Identifier Patterns](../global/ADR-GLB-006-naming-and-labeling-conventions.md)
- [ADR-GLB-007: Governance Gates, Guardrails, Invariants, and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-GLB-008: Label and Tag Standard](../global/ADR-GLB-008-label-and-tag-standard.md)
