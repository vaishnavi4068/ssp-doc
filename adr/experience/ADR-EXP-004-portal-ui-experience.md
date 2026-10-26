# ADR-EXP-004: Portal UI Experience (`ssp-ui` Storefront on IDP Design Variant 17)

- **ADR ID:** ADR-EXP-004
- **Level:** endpoint-service
- **Status:** Proposed
- **Owner:** Dwayne (Shared Mailbox: `spp-experience@tbd`, Named Owner: `Dwayne`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-ui`, `ssp-cp`, `ssp-workers`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define the **Portal UI Experience (`ssp-ui`, `experiences/portal-ui/`, `channel = "ui"`)** for the Self-Service Provisioning Platform (SPP)—deployed live at **`https://portal.taxi.growripple.ai`** using **IDP Design Variant 17** ("Shopify Polaris Infrastructure Storefront") with an **nginx reverse proxy** to `spp-cp` (`ssp-cp`), exposing **Google Cloud Storage Bucket (`kind = "gcs_bucket"`, `us-east1`) as a live end-to-end workflow** and **Cloud Spanner (`spanner_instance`, `spanner_database`) as "Coming Soon"**, while sharing the exact same `ssp-cp` API, OPA policy gates, and human approval path as all other experience lines.

## Context

1. **Unifying All Four Experience Lines Under `experiences/` and `adr/experience/`:**
   - Alongside the Agentic Chatbot (`ADR-EXP-001`), MCP Server (`ADR-EXP-002`), and Client SDK (`ADR-EXP-003`), the **Portal UI (`ssp-ui`)** is one of four peer experience lines over the `ssp-cp` FastAPI Control Plane API.
   - Earlier UI specification files (`10-product/16-ui-spec.md` and `40-repos/44-ssp-ui-structure.md`) lived outside the experience layer and have been moved via `git mv` into [`experiences/portal-ui/16-ui-spec.md`](../../experiences/portal-ui/16-ui-spec.md) and [`experiences/portal-ui/44-ssp-ui-structure.md`](../../experiences/portal-ui/44-ssp-ui-structure.md), paired with [`experiences/portal-ui/README.md`](../../experiences/portal-ui/README.md).
2. **Live `ssp-ui` Deployment (`https://portal.taxi.growripple.ai`):**
   - The live SPP Portal runs at `https://portal.taxi.growripple.ai` on the SPP GKE cluster in `<spp-factory-host-project-id>` (namespace `spp-platform`, node pool `spp-pool`), implementing **IDP Design Variant 17** (React + TypeScript + Vite + Tailwind CSS).
   - An **nginx** container serves the static SPA bundle and reverse-proxies `/api/v1/*`, `/healthz`, and `/readyz` on the same origin to `spp-cp` (`http://spp-cp.spp-platform.svc.cluster.local:8000`).
   - In the catalog today, **GCS Bucket (`gcs_bucket` in `us-east1`) is live** (`form -> ssp-cp FastAPI API -> OPA intake policy -> human approval -> Temporal workflow -> Terraform plan -> apply gate`), and **Cloud Spanner (`spanner_instance`, `spanner_database`) is displayed as "Coming Soon"**.

## Decision

1. **Architecture & Same-Origin nginx Proxy to `spp-cp`:**
   - `ssp-ui` is deployed in Kubernetes namespace `spp-platform` on the SPP GKE cluster behind `https://portal.taxi.growripple.ai`.
   - The nginx container serves the compiled React SPA and forwards all `/api/v1/*`, `/healthz`, and `/readyz` requests to `spp-cp` (`ssp-cp` FastAPI service), preserving the `HttpOnly`, `Secure`, `SameSite=Lax` `__Host-spp_cp_session` cookie and `X-CSRF-Token` header on the same origin.
   - `ssp-ui` has zero direct connectivity to AlloyDB (`spp_platform`), the OPA server (`spp-policy`), Temporal (`spp-temporal`), or `gs://microdrive-dev-spp-tfstate`.
2. **Visual & Interaction Standard (IDP Design Variant 17):**
   - Uses the **IDP Design Variant 17** ("Shopify Polaris Infrastructure Storefront") design tokens defined in [`experiences/portal-ui/16-ui-spec.md`](../../experiences/portal-ui/16-ui-spec.md) (`--primary: 161 62% 28%` / `#1b7a5a`, `--background: 220 20% 97%` / `#f5f6f9`, `12px` card radius, `Inter` + `JetBrains Mono`).
   - Catalog displays **Cloud Storage Bucket (`gcs_bucket`, `us-east1`)** as **LIVE** and **Cloud Spanner (`spanner_instance`, `spanner_database`, `regional-us-east1`)** as **COMING SOON**.
3. **GCS Bucket Form, Validation & Guardrail Display (`ADR-SVC-001`, `ADR-GLB-006..008`):**
   - Enforces and previews APM ID `(?i)^APM\d{5}$` -> lowercase `^apm\d{5}$` (`NAM-APM-001`), environment normalization to `nonprod` (no hyphen) or `prod` (`GLB-ENV-001`, with `environmentsubtype` dropped and forbidden everywhere), `location = "us-east1"` (`GLB-REG-001`), bucket naming `{lob}-{env}-{app}-{purpose}-{suffix}` (`GCS-NAME-001..003`), optional `lifecycle_rules` defaulting to `[]` (NONE), and IAM allowlists (`group:` and `serviceAccount:` only).
   - Previews and renders all **8 mandatory labels** (`sppappid`, `costcenter`, `environmenttype`, `primarylob`, `datasensitivity`, `owner`, `provisionedby`, `idp_resource_id`), CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek` (`GCS-ENC-001`), and the 10-entry `guardrail_trace`.
4. **Authentication, Human Approval Gate, and No-Delete Rule (`ADR-GLB-005`, `ADR-BP-003`, `ADR-GLB-007`):**
   - Authenticates via `POST /api/v1/auth/login` (Argon2id local login) and enforces mandatory first-login password rotation (`POST /api/v1/auth/change-password`) whenever `must_change_password == true`.
   - Submits requests via `POST /api/v1/requests` with `channel = "ui"`.
   - Enforces `gcs_bucket_owner` v1 human approval (`POST /api/v1/approvals/{approval_id}/decisions`) with `self_approval = "deny"` (disabling self-approval in the UI and rejecting it with `403 Forbidden` in `ssp-cp`), which upon approval starts **`GcsBucketProvisionWorkflow`** (`req-<request_id>`) on Temporal namespace `platform` (`task_queue = "spp-gcs-provisioning"`).
   - Requires explicit human approval for all `delete` requests and destructive plans in both `nonprod` and `prod` (`AUTO_APPROVED` / `auto_approved` is forbidden).

## Requirements

- **REQ-1 (MUST):** `ssp-ui` (`https://portal.taxi.growripple.ai`) MUST route all control-plane operations through its nginx reverse proxy to the `ssp-cp` FastAPI REST API (`/api/v1/*`) with `channel = "ui"`, the caller's `__Host-spp_cp_session` cookie, and `X-CSRF-Token`, with zero direct connections to AlloyDB, OPA, Temporal, or GCS.
- **REQ-2 (MUST):** When `GET /api/v1/me` or `POST /api/v1/auth/login` returns `must_change_password == true`, `ssp-ui` MUST block access to catalog/request/approval screens until `POST /api/v1/auth/change-password` succeeds (`ADR-GLB-005`).
- **REQ-3 (MUST):** The GCS Bucket (`kind = "gcs_bucket"`) form and receipt in `ssp-ui` MUST enforce and display APM ID normalization (`(?i)^APM\d{5}$` -> `^apm\d{5}$`), `environmenttype` in `{"nonprod", "prod"}` (with `environmentsubtype` omitted and forbidden), `location = "us-east1"`, the 8 mandatory labels (`LBL-001`), CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek` (`GCS-ENC-001`), `lifecycle_rules` default `[]`, and the 10-entry `guardrail_trace`.
- **REQ-4 (MUST):** `ssp-ui` MUST enforce `self_approval = "deny"` on the Approvals screen and require explicit human approval for any resource deletion (`action = "delete"`) in both `nonprod` and `prod` (`ADR-BP-003`, `ADR-GLB-007`).
- **REQ-5 (SHOULD):** The catalog in `ssp-ui` SHOULD display `gcs_bucket` as **Live** and `spanner_instance` / `spanner_database` as **Coming Soon** until the Spanner module and OPA policies complete end-to-end verification (`WI-007`).

## Guardrails

- **GR-1:** Never expose raw session tokens to browser scripts or bypass `X-CSRF-Token` verification on mutating requests (`POST`, `PUT`, `PATCH`, `DELETE`).
- **GR-2 (`INV-1`):** Never render secret input fields in `ssp-ui` forms or display sensitive `.tfstate` values in the browser; only display the `< 2000`-byte non-sensitive `idp.resource_observed.projection`.
- **GR-3:** Never allow a requester to approve their own request (`self_approval = "deny"`) or allow `AUTO_APPROVED` on any `delete` request in `nonprod` or `prod`.

## Consequences

### Positive

- Consolidates all Portal UI documentation (`README.md`, `16-ui-spec.md`, `44-ssp-ui-structure.md`) and its governing ADR (`ADR-EXP-004`) inside the `experiences/` and `adr/experience/` layer alongside Agentic Chat (`ADR-EXP-001`), MCP (`ADR-EXP-002`), and SDK (`ADR-EXP-003`).
- Accurately documents the live deployment at `https://portal.taxi.growripple.ai` (IDP Design Variant 17, nginx proxy to `spp-cp`, local Argon2id login, GCS Bucket live, Spanner coming soon).

### Negative / Trade-offs

- As additional resource kinds (`spanner_instance`, `spanner_database`) graduate from "Coming Soon" to "Live", `ssp-ui` must transition from static per-kind form definitions to the schema-driven renderer (`@ssp/form-renderer` in [`16-ui-spec.md`](../../experiences/portal-ui/16-ui-spec.md) §5) so new kinds require zero UI redeploys (`ADR-GLB-002 REQ-3`).

## Acceptance Criteria

- [ ] `10-product/16-ui-spec.md` and `40-repos/44-ssp-ui-structure.md` are moved via `git mv` into [`experiences/portal-ui/16-ui-spec.md`](../../experiences/portal-ui/16-ui-spec.md) and [`experiences/portal-ui/44-ssp-ui-structure.md`](../../experiences/portal-ui/44-ssp-ui-structure.md) with all inbound links updated across `ssp-doc`.
- [ ] [`experiences/portal-ui/README.md`](../../experiences/portal-ui/README.md) documents the live Portal (`https://portal.taxi.growripple.ai`, IDP design variant 17, GCS Bucket live, Spanner coming soon, nginx proxy to `spp-cp`) with purpose, user journeys, mermaid architecture, `ssp-cp` endpoint mapping, security/identity, approval/no-delete rules, observability, MVP vs. later scope, and open questions.
- [ ] `ADR-EXP-004` passes ADR structural and link validation.

## Success Criteria

- **SC-1:**
  - **Given** an authenticated user at `https://portal.taxi.growripple.ai` submitting the live GCS Bucket form for `APM12345` in `us-east1`
  - **When** the browser sends `POST /api/v1/requests` through the nginx proxy to `spp-cp`
  - **Then** `ssp-cp` normalizes `APM12345 -> apm12345`, evaluates OPA `stage = 'requested'`, persists `idp.submission` (`channel = "ui"`), `idp.request` (`PENDING_APPROVAL`), and `idp.approval` (`PENDING`), and the Portal UI displays the 4-gate status and pending `gcs_bucket_owner` approval.
- **SC-2:**
  - **Given** a distinct human approver (`bucket_owner` / `approver`) approving the pending request in the Portal UI Approvals queue
  - **When** `POST /api/v1/approvals/{approval_id}/decisions` executes on `ssp-cp`
  - **Then** OPA `stage = 'approved'` records the 10-entry `guardrail_trace` (including the 8 mandatory labels and CMEK key `projects/microdrive-dev/locations/us-east1/keyRings/spp-keyring/cryptoKeys/spp-gcs-cmek`), `GcsBucketProvisionWorkflow` (`req-<request_id>`) is dispatched on Temporal namespace `platform` (`spp-gcs-provisioning`), and the Portal UI renders the updated gate, guardrail trace, and `< 2000`-byte Observed projection.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines `ADR-EXP-004` and [`experiences/portal-ui/`](../../experiences/portal-ui/) (`README.md`, `16-ui-spec.md`, `44-ssp-ui-structure.md`) |
| `ssp-ui` | Implements the live IDP Design Variant 17 storefront (`https://portal.taxi.growripple.ai`) and nginx reverse proxy to `spp-cp` |
| `ssp-cp` | Serves `/api/v1/*` endpoints consumed by the `ssp-ui` nginx proxy and enforces CORS, CSRF, RBAC, and OPA gates |
| `ssp-workers` | Executes `GcsBucketProvisionWorkflow`, `ApprovalGateWorkflow`, and `StateUnitReconcilerWorkflow` triggered from Portal UI approvals |
| `spp-factory-foundation` | Validates `ADR-EXP-004` and `portal-and-catalog` skill alignment |

## Open Questions

- [ ] **OQ-1 (Cloud Spanner Card Activation in `https://portal.taxi.growripple.ai` — [Owner: Manoj / Dwayne]):** Confirm the exit criteria (`WI-007`) for enabling the "Coming Soon" Cloud Spanner (`spanner_instance`, `spanner_database`) checkout flow in `ssp-ui`.
- [ ] **OQ-2 (Embedding Jev Model Chat Drawer in `ssp-ui` — [Owner: Dwayne / Manoj]):** Confirm wiring the Jev model Agentic Chatbot (`ADR-EXP-001`, `ADR-AUT-004`) into the right slide-over drawer of `https://portal.taxi.growripple.ai`.

## Related ADRs

- [ADR-EXP-001: Agentic Chatbot Experience for Self-Service Provisioning](ADR-EXP-001-agentic-chatbot-experience.md)
- [ADR-EXP-002: MCP Server Experience for Self-Service Provisioning](ADR-EXP-002-mcp-server-experience.md)
- [ADR-EXP-003: Client SDK Experience (Python First, TypeScript Later)](ADR-EXP-003-client-sdk-experience.md)
- [ADR-AUT-004: Agent Harness ("Jev Model") and Deterministic Temporal Workflow Execution Layer](../automation/ADR-AUT-004-agent-harness-and-temporal-workflow-execution.md)
- [ADR-SVC-001: First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails](../endpoint-service/ADR-SVC-001-first-vertical-slice-gcs-bucket.md)
- [ADR-SVC-002: Cloud Spanner Instance and Database Specification](../endpoint-service/ADR-SVC-002-spanner-instance-and-database.md)
- [ADR-GLB-002: Languages and Technology Stack](../global/ADR-GLB-002-languages-and-technology-stack.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
- [ADR-BP-003: Roles, Personas, and Approval Gate Governance](../business-process/ADR-BP-003-roles-and-approver-governance.md)
