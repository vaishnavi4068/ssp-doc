# ADR-GLB-005: Identity, Workload Identity, and Authentication

- **ADR ID:** ADR-GLB-005
- **Level:** global
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-security@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Establish a zero-static-key identity and authentication architecture for SPP using **GKE Workload Identity** for all control-plane and runner pods, **one dedicated service account per target GCP project** impersonated by a central platform runner service account ("kill button"), and **local Argon2id login now (with corporate SSO as a future item)**.

## Context

In the design discussion (`uploads/design-digest.md`), stakeholder clarifications, and factory runtime deployment (`spp-factory-foundation/docs/factory/runbook.md`):

1. **Assume Breach & Eliminate Shared Environment SAs:** Dwayne emphasized "we will be hacked" and the need to limit blast radius. Legacy "taxi" used only 3 shared service accounts (`prod`, `nonprod`, `sandbox`) across all projects. SPP replaces this with **one dedicated service account per 2.0 GCP project**, impersonated for the duration of a single run by the central SPP platform runner service account, which acts as a global **kill button**.
2. **Workload Identity Only — No Static Keys Ever:** All workloads on the SPP GKE cluster (`<spp-factory-host-project-id>`, non-prod) authenticate to GCP services using GKE Workload Identity (`<spp-factory-host-project-id>.svc.id.goog`). Exporting or mounting service account JSON private keys is strictly forbidden.
3. **Strict Isolation Between Factory (`spp-factory`) and Runtime Platform (`spp-platform`):** In `spp-factory-foundation`, Kubernetes ServiceAccount `factory-agent` in `spp-factory` is bound via Workload Identity to `spp-factory-agent@<spp-factory-host-project-id>.iam.gserviceaccount.com` (which has **only** Vertex AI model invocation permissions and zero cloud provisioning permissions). Only the runtime runner service account in `spp-platform` (provided and owned by the **SPP team** in `<spp-factory-host-project-id>`: `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com`, `TODO(vaishnavi4068)`) may impersonate target project provisioning service accounts.
4. **Local Login Now, Corporate SSO Future:** SPP APIs (`ssp-cp` FastAPI) are deployed directly on the SPP GKE cluster (`spp-platform` namespace) and exposed via GKE Ingress / LoadBalancer (no external API gateway layer). For authentication, SPP uses hardened local username/password authentication now (Argon2id hashing, bootstrap passwords in GCP Secret Manager, mandatory password rotation on first login, HTTP-only `__Host-` session cookies, CSRF tokens, rate limiting, and 5-attempt lockout), with corporate SSO deferred as a future enhancement.

## Decision

1. **Pod-to-Cloud Identity (GKE Workload Identity, Zero Keys):**
   - Every GKE pod in `spp-platform` and `spp-factory` authenticates via GKE Workload Identity (`<spp-factory-host-project-id>.svc.id.goog`), including IAM database authentication (`roles/alloydb.client` + `roles/alloydb.databaseUser`) from `ssp-cp` pods in `spp-platform` to the dedicated AlloyDB for PostgreSQL cluster (`spp_platform` database, `ADR-GLB-004`).
   - Long-lived GCP service account JSON keys are prohibited in code, images, ConfigMaps, K8s Secrets, and Terraform state.
2. **Provisioning Blast-Radius Model (1 SA per Project + Platform Runner SA Kill Button):**
   - Each 2.0 target GCP project has a dedicated service account (e.g., `spp-provisioner@<target-project-id>.iam.gserviceaccount.com`).
   - In the non-prod `<spp-factory-host-project-id>` environment, the **SPP team** provides and owns the runner GCP Service Account for `spp-platform`: `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com` (`TODO(vaishnavi4068): fill in exact runner GSA email`).
   - The SPP Terraform runner Kubernetes Job in `spp-platform` runs under a Kubernetes ServiceAccount bound via Workload Identity to `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com` ("kill button"), which holds `roles/iam.serviceAccountTokenCreator` only on onboarded per-project service accounts.
   - Disabling the central SPP runner Service Account immediately halts all impersonation and provisioning across every project.
   - Workloads in `spp-factory` (`factory-api`, `factory-worker`, `factory-agent`) MUST NOT have permission to impersonate `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com` or any tenant project SA.
3. **User & API Authentication (Local Login Now -> Corporate SSO Future):**
   - **Current (Phase 1 — Local Login):** Local username/password authentication in `ssp-cp` (matching `spp-factory-foundation/services/factory-api/app/auth.py`):
     - Initial bootstrap passwords read from GCP Secret Manager (`spp-factory-bootstrap-{manoj,dwayne,norm}` / `spp-cp-bootstrap-*`), hashed with **Argon2id**, with `must_change_password = true` enforced on first login.
     - Role-based access control (RBAC): `manoj` (`architect` role), `dwayne` (`approver` / `operations` role), `norm` (`approver` / `operations` role), plus extensible personas (`developer`, `operations`, `security`, `platform-admin`).
     - Hardened sessions: `__Host-` prefixed `HttpOnly`, `Secure`, `SameSite=Lax` cookies, `X-CSRF-Token` validation on all state-changing requests (`POST`, `PUT`, `PATCH`, `DELETE`), sliding-window IP/user rate limiting, and account lockout after 5 failed attempts.
   - **Future Enhancement:** Corporate SSO (OIDC / SAML) integration, preserving the same RBAC persona claims and audit log schema.

## Requirements

- **REQ-1 (MUST):** All GKE workloads in `spp-platform`, `spp-factory`, and `spp-temporal` MUST use GKE Workload Identity (`<spp-factory-host-project-id>.svc.id.goog`) for GCP authentication and MUST NOT use service account JSON key files.
- **REQ-2 (MUST):** Every target 2.0 GCP project MUST use a dedicated per-project provisioning service account impersonated by the SPP runner Service Account (`<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com`, "kill button").
- **REQ-3 (MUST):** In `Approved` state payloads, `service_account_email` MUST belong to the target `project_id` (enforced by OPA rule in `gates/policies/spp_gate.rego`).
- **REQ-4 (MUST):** Local authentication in `ssp-cp` MUST enforce Argon2id password hashing, Secret Manager bootstrap secrets, mandatory first-login password rotation, CSRF protection, login rate limiting, and account lockout after 5 consecutive failed attempts.
- **REQ-5 (MUST):** The authentication layer in `ssp-cp` MUST use a pluggable principal dependency so adding corporate SSO in the future requires zero changes to downstream API route handlers or audit logging.
- **REQ-6 (MUST):** Every authenticated action MUST record the resolved user identity (`actor_username`), `actor_role`, `source_ip`, and `reason` in the immutable audit log.

## Guardrails

- **GR-1:** Never create, export, mount, or commit GCP service account JSON keys (`private_key_id` / `-----BEGIN PRIVATE KEY-----`) anywhere in SPP or the software factory.
- **GR-2:** Never reuse legacy Taxi's 3 shared `prod` / `nonprod` / `sandbox` service accounts.
- **GR-3:** Never grant `spp-factory` service accounts (`factory-api`, `factory-worker`, `factory-agent`) IAM permission to impersonate `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com` or any target project provisioning SA.
- **GR-4:** Never allow API requests to `ssp-cp` (other than `/healthz` and `/api/v1/auth/login`) while `must_change_password == true`.

## Consequences

### Positive

- Zero static cloud credentials to leak or rotate across GKE pods and Terraform runner Jobs.
- Immediate, single-point emergency stop ("kill button") via `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com` while isolating each run's blast radius to one target GCP project.
- Direct deployment on the SPP GKE cluster (`spp-platform`) with local Argon2id login unblocks immediate operation in `<spp-factory-host-project-id>` with zero external gateway or external SA-issuance bottlenecks.

### Negative / Trade-offs

- The SPP team is directly responsible for provisioning and managing IAM bindings on `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com` in `<spp-factory-host-project-id>`.

## Acceptance Criteria

- [ ] Kubernetes ServiceAccounts in `spp-platform` and `spp-factory` carry `iam.gke.io/gcp-service-account` Workload Identity annotations (`<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com` for the runner in `spp-platform`) and zero mounted GCP key secrets.
- [ ] `ssp-cp` implements the local login flow (Argon2id, Secret Manager bootstrap, mandatory first-login password change, CSRF, rate limit, lockout) and RBAC roles (`architect`: `manoj`; `approver`: `dwayne`, `norm`).
- [ ] OPA gate rules reject any `Approved` payload whose `service_account_email` does not match the target `project_id`.

## Success Criteria

- **SC-1:**
  - **Given** a Terraform runner Kubernetes Job `tf-op-<operation_id>` in `spp-platform` targeting `project_id = "<spp-factory-host-project-id>"`
  - **When** the runner authenticates to GCP
  - **Then** it obtains short-lived credentials via GKE Workload Identity (`<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com`) and service account impersonation without any JSON key file on disk or in environment variables.
- **SC-2:**
  - **Given** a newly bootstrapped user (`manoj`, `dwayne`, or `norm`) logging in for the first time with their Secret Manager bootstrap password
  - **When** they attempt to call `POST /api/v1/requests` before rotating their password
  - **Then** `ssp-cp` returns `403 Forbidden` (`must_change_password`) until `POST /api/v1/auth/change-password` succeeds.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the global Workload Identity, per-project SA impersonation, and local-to-SSO auth contract |
| `ssp-cp` | Implements local Argon2id auth, RBAC personas, Secret Manager bootstrap, and future SSO middleware |
| `ssp-workers` | Configures K8s Job runner ServiceAccount (`<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com`) and per-project `--impersonate-service-account` / `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` |
| `ssp-ui` | Implements login, mandatory first-login password rotation, and CSRF header propagation |
| `ssp-module-<type>` | Uses ambient provider authentication (impersonated token) with zero hardcoded credentials |
| `spp-factory-foundation` | Enforces `service_account_email` project matching and secret scanning in `gates/policies/spp_gate.rego` |

## Open Questions

- [x] **OQ-1 (Runner Service Account Ownership in `<spp-factory-host-project-id>` — RESOLVED 2026-10-21):** *Resolved:* Not issued by Hurley; the **SPP team** provides and owns the runner GCP Service Account for `spp-platform` in `<spp-factory-host-project-id>`. Placeholder to be filled by `vaishnavi4068`: `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com`.
- [x] **OQ-2 (API Gateway / Apigee Dependency — RESOLVED 2026-10-21):** *Resolved:* API Forge / Apigee is **not used**. `ssp-cp` FastAPI is deployed directly on the SPP GKE cluster (`spp-platform` namespace) and exposed via GKE Ingress / LoadBalancer with local login now and corporate SSO as a future item only.
- [x] **OQ-3 (Exact Runner GSA Email in `<spp-factory-host-project-id>` — RESOLVED / USER-SUPPLIED `TODO: vaishnavi4068`):** *Resolved:* The runner GSA placeholder `<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com` is accepted for the ADR contract; `vaishnavi4068` will supply the exact email value at deploy time (and for the first vertical slice in `<spp-factory-host-project-id>`, the runner SA targets `<spp-factory-host-project-id>`).

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](ADR-GLB-003-four-state-model.md)
- [ADR-CLD-GCP-001: Runtime Platform (SPP GKE Cluster and Self-Hosted Temporal)](../per-cloud/gcp/ADR-CLD-GCP-001-runtime-platform-gke-and-temporal.md)
- [ADR-AUT-001: Terraform Execution via Kubernetes Jobs](../automation/ADR-AUT-001-terraform-execution-k8s-job.md)
- [ADR-BP-001: Ownership Map and Stakeholder Governance](../business-process/ADR-BP-001-ownership-map-and-governance.md)
